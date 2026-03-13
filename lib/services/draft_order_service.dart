import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/draft_order.dart';
import '../models/draft_order_item.dart';
import 'local_db_service.dart';
import 'session_service.dart';

/// Holder for draft order header + line items (from DB).
class DraftOrderWithItems {
  final DraftOrder order;
  final List<DraftOrderItem> items;

  const DraftOrderWithItems({required this.order, required this.items});

  double get grossAmount => items.fold(0.0, (s, i) => s + i.subtotal);
  double get totalDiscount => items.fold(0.0, (s, i) => s + i.discountAmount);
  double get netAmount => grossAmount - totalDiscount;
}

/// Manages the current draft order and its line items in SQLite.
/// One active draft per user; all updates persist to DB.
class DraftOrderService {
  DraftOrderService._();

  static final DraftOrderService instance = DraftOrderService._();

  static const String _currentDraftIdKey = 'current_draft_id';

  Future<Database> get _db async => await LocalDbService.instance.database;

  Future<int?> _nextOrderSerialNo(Database db) async {
    try {
      final rows = await db.rawQuery(
        'SELECT MAX(order_serial_no) AS max_no FROM draft_orders',
      );
      if (rows.isEmpty) return 1;
      final raw = rows.first['max_no'];
      int maxNo = 0;
      if (raw is int) {
        maxNo = raw;
      } else if (raw is num) {
        maxNo = raw.toInt();
      } else if (raw != null) {
        maxNo = int.tryParse(raw.toString()) ?? 0;
      }
      return maxNo + 1;
    } catch (_) {
      // Older database may not have order_serial_no; keep backward compatible.
      return null;
    }
  }

  Future<int?> _ensureOrderSerialNoForDraft(Database db, int draftId) async {
    try {
      final rows = await db.query(
        'draft_orders',
        columns: ['order_serial_no'],
        where: 'id = ?',
        whereArgs: [draftId],
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final raw = rows.first['order_serial_no'];
      int? current;
      if (raw is int) {
        current = raw;
      } else if (raw is num) {
        current = raw.toInt();
      } else if (raw != null) {
        current = int.tryParse(raw.toString());
      }

      if (current != null && current > 0) {
        return current;
      }

      final next = await _nextOrderSerialNo(db);
      if (next == null) return null;

      await db.update(
        'draft_orders',
        {
          'order_serial_no': next,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [draftId],
      );
      return next;
    } catch (_) {
      // Backward compatibility: schema may not yet include this column.
      return null;
    }
  }

  /// Returns the current draft id (stored in SharedPreferences or first draft row).
  Future<int?> getCurrentDraftId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getInt(_currentDraftIdKey);
      if (id != null) return id;
      final draft = await _getLatestDraftForUser();
      if (draft != null) {
        await _setCurrentDraftId(draft.id);
        return draft.id;
      }
      return null;
    } catch (e) {
      debugPrint('DraftOrderService.getCurrentDraftId: $e');
      return null;
    }
  }

  Future<void> _setCurrentDraftId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_currentDraftIdKey, id);
  }

  Future<DraftOrder?> _getLatestDraftForUser() async {
    final db = await _db;
    final employeeId = await SessionService.getEmployeeId();
    final userId = employeeId?.toString() ?? '';
    final rows = await db.query(
      'draft_orders',
      where: 'status = ? AND (employee_id IS NULL OR employee_id = ?)',
      whereArgs: ['draft', userId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DraftOrder.fromMap(rows.first);
  }

  /// Loads the current draft with its line items; creates one if none exists.
  Future<DraftOrderWithItems?> getCurrentDraft() async {
    var id = await getCurrentDraftId();
    if (id == null) {
      final created = await createNewDraft();
      if (created == null) return null;
      id = created.id;
    }
    return getDraftById(id);
  }

  /// Loads a draft by id with items.
  Future<DraftOrderWithItems?> getDraftById(int draftId) async {
    final db = await _db;
    await _ensureOrderSerialNoForDraft(db, draftId);
    final orderRows = await db.query(
      'draft_orders',
      where: 'id = ?',
      whereArgs: [draftId],
    );
    if (orderRows.isEmpty) return null;
    final order = DraftOrder.fromMap(orderRows.first);
    final itemRows = await db.query(
      'draft_order_items',
      where: 'draft_order_id = ?',
      whereArgs: [draftId],
      orderBy: 'sort_order ASC, id ASC',
    );
    final items = itemRows.map((m) => DraftOrderItem.fromMap(m)).toList();
    return DraftOrderWithItems(order: order, items: items);
  }

  /// Creates a new draft and sets it as current.
  Future<DraftOrder?> createNewDraft() async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final employeeId = await SessionService.getEmployeeId();
    final localOrderId = const Uuid().v4();
    final serialNo = await _nextOrderSerialNo(db);

    final payload = {
      'local_order_id': localOrderId,
      if (serialNo != null) 'order_serial_no': serialNo,
      'status': 'draft',
      'finalize_flag': '0',
      'uploaded': 'NO',
      'uploaded_at': null,
      'created_at': now,
      'updated_at': now,
      'employee_id': employeeId?.toString(),
    };

    int id;
    try {
      id = await db.insert('draft_orders', payload);
    } catch (_) {
      // Fallback for very old schema where order_serial_no may still be absent.
      payload.remove('order_serial_no');
      id = await db.insert('draft_orders', payload);
    }

    await _setCurrentDraftId(id);
    final draft = await getDraftById(id);
    return draft?.order;
  }

  /// Updates header fields on the current draft (party, ship-to, agency, package, payment deal, address, etc.).
  Future<void> updateDraftHeader(
    int draftId,
    Map<String, dynamic> updates,
  ) async {
    final db = await _db;
    final allowed = {
      'bill_to_party_id',
      'party_name',
      'ship_to_party_id',
      'delivery_party_name',
      'delivery_point_id',
      'delivery_point_name',
      'goods_agency_id',
      'goods_agency_name',
      'visit_id',
      'route_id',
      'package_id',
      'package_name',
      'payment_deal_id',
      'delivery_address',
      'order_remarks',
    };
    final map = <String, dynamic>{};
    for (final k in updates.keys) {
      if (allowed.contains(k)) map[k] = updates[k];
    }
    if (map.isEmpty) return;
    map['updated_at'] = DateTime.now().toIso8601String();
    await db.update('draft_orders', map, where: 'id = ?', whereArgs: [draftId]);
  }

  /// Inserts a line item and returns its id.
  Future<int> insertLineItem({
    required int draftOrderId,
    String? itemId,
    required String itemName,
    required int quantity,
    required double unitPrice,
    double discountPercent = 0,
    String? specialRemarks,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final count = await db.rawQuery(
      'SELECT COUNT(*) as c FROM draft_order_items WHERE draft_order_id = ?',
      [draftOrderId],
    );
    final sortOrder = (count.first['c'] as int? ?? 0);
    final id = await db.insert('draft_order_items', {
      'draft_order_id': draftOrderId,
      'item_id': itemId,
      'item_name': itemName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'discount_percent': discountPercent,
      'special_remarks': specialRemarks,
      'sort_order': sortOrder,
      'created_at': now,
    });
    await db.update(
      'draft_orders',
      {'updated_at': now},
      where: 'id = ?',
      whereArgs: [draftOrderId],
    );
    return id;
  }

  /// Removes a line item by id.
  Future<void> deleteLineItem(int itemId) async {
    final db = await _db;
    final row = await db.query(
      'draft_order_items',
      where: 'id = ?',
      whereArgs: [itemId],
    );
    if (row.isEmpty) return;
    final draftId = row.first['draft_order_id'] as int;
    await db.delete('draft_order_items', where: 'id = ?', whereArgs: [itemId]);
    await db.update(
      'draft_orders',
      {'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [draftId],
    );
  }

  /// Delete all line items for a specific draft.
  Future<void> deleteAllLineItems(int draftOrderId) async {
    final db = await _db;
    await db.delete(
      'draft_order_items',
      where: 'draft_order_id = ?',
      whereArgs: [draftOrderId],
    );
    await db.update(
      'draft_orders',
      {'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [draftOrderId],
    );
  }

  /// Resets current draft: clear header and delete all line items (or create new blank draft).
  Future<DraftOrderWithItems?> resetDraft(int draftId) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    await db.delete(
      'draft_order_items',
      where: 'draft_order_id = ?',
      whereArgs: [draftId],
    );
    await db.update(
      'draft_orders',
      {
        'bill_to_party_id': null,
        'party_name': null,
        'ship_to_party_id': null,
        'delivery_party_name': null,
        'delivery_point_id': null,
        'delivery_point_name': null,
        'goods_agency_id': null,
        'goods_agency_name': null,
        'visit_id': null,
        'route_id': null,
        'package_id': null,
        'package_name': null,
        'payment_deal_id': null,
        'delivery_address': null,
        'order_remarks': null,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [draftId],
    );
    return getDraftById(draftId);
  }

  /// Marks draft as finalized and returns the same draft (with items). Caller then creates new draft.
  Future<DraftOrderWithItems?> finalizeDraft(int draftId) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'draft_orders',
      {
        'status': 'finalized',
        'finalize_flag': '1',
        'uploaded': 'NO',
        'uploaded_at': null,
        'finalized_at': now,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [draftId],
    );
    return getDraftById(draftId);
  }

  /// Marks a finalized order as uploaded (Android parity: finalize=2, uploaded=YES).
  Future<void> markUploadSuccess(int draftId, {bool clearItems = true}) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    await db.update(
      'draft_orders',
      {
        'finalize_flag': '2',
        'uploaded': 'YES',
        'uploaded_at': now,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [draftId],
    );

    if (clearItems) {
      await db.delete(
        'draft_order_items',
        where: 'draft_order_id = ?',
        whereArgs: [draftId],
      );
    }
  }

  /// Android parity: save finalized draft into bookings + booking_items (local save).
  /// Call after finalizeDraft. Returns booking id or null.
  Future<int?> saveFinalizedOrderToBookings(int draftId) async {
    final draft = await getDraftById(draftId);
    if (draft == null || !draft.order.isFinalized) return null;

    final db = await _db;
    final order = draft.order;
    final employeeId = await SessionService.getEmployeeId();
    final empId = employeeId?.toString() ?? '1013';
    final now = DateTime.now();
    final invdate = order.finalizedAt != null
        ? order.finalizedAt!
        : order.updatedAt;

    final localinvno = (order.orderSerialNo ?? order.id).toString();
    final bookingId = await db.insert('bookings', {
      'draft_order_id': draftId,
      'orderby': int.tryParse(empId) ?? 1013,
      'invdate': invdate ?? _formatInvDate(now),
      'partyid': order.billToPartyId ?? '0',
      'package_id': order.packageId ?? '1',
      'remarks': order.orderRemarks ?? '',
      'status': 1,
      'employeeid': empId,
      'localinvno': localinvno,
      'deliverypoint': order.deliveryPointName ?? order.deliveryAddress ?? 'Direct to Party (Bilty)',
      'isandroid': '1',
      'delivery_party': order.shipToPartyId ?? '0',
      'deal_id': order.paymentDealId ?? '0',
      'goodsagency_id': order.goodsAgencyId ?? '0',
      'uploaded': 'NO',
      'created_at': now.toIso8601String(),
    });

    final createdAt = now.toIso8601String();
    for (var i = 0; i < draft.items.length; i++) {
      final item = draft.items[i];
      await db.insert('booking_items', {
        'booking_id': bookingId,
        'item_id': item.itemId,
        'item_name': item.itemName,
        'quantity': item.quantity,
        'unit_price': item.unitPrice,
        'discount_percent': item.discountPercent,
        'sort_order': i,
        'created_at': createdAt,
      });
    }

    return bookingId;
  }

  static String _formatInvDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
  }

  /// Returns booking row by id (for upload).
  Future<Map<String, dynamic>?> getBookingById(int bookingId) async {
    final db = await _db;
    final rows = await db.query(
      'bookings',
      where: 'id = ?',
      whereArgs: [bookingId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  /// Returns booking row by draft_order_id.
  Future<Map<String, dynamic>?> getBookingByDraftOrderId(int draftOrderId) async {
    final db = await _db;
    final rows = await db.query(
      'bookings',
      where: 'draft_order_id = ?',
      whereArgs: [draftOrderId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  /// Returns all booking_items for a booking_id.
  Future<List<Map<String, dynamic>>> getBookingItems(int bookingId) async {
    final db = await _db;
    final rows = await db.query(
      'booking_items',
      where: 'booking_id = ?',
      whereArgs: [bookingId],
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Mark booking as uploaded (Android parity).
  Future<void> markBookingUploaded(int bookingId) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'bookings',
      {'uploaded': 'YES', 'uploaded_at': now},
      where: 'id = ?',
      whereArgs: [bookingId],
    );
  }

  /// Returns bookings pending upload (uploaded != YES) for current employee.
  Future<List<Map<String, dynamic>>> getPendingBookings() async {
    final db = await _db;
    final employeeId = await SessionService.getEmployeeId();
    final empId = employeeId?.toString() ?? '';

    final rows = await db.query(
      'bookings',
      where: "(uploaded IS NULL OR uploaded != 'YES') AND (employeeid = ? OR ? = '')",
      whereArgs: [empId, empId],
      orderBy: 'id ASC',
    );

    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<int> getPendingBookingsCount() async {
    final pending = await getPendingBookings();
    return pending.length;
  }

  /// Returns all finalized orders for current user with their line items.
  Future<List<DraftOrderWithItems>> getFinalizedOrders() async {
    final db = await _db;
    final employeeId = await SessionService.getEmployeeId();
    final userId = employeeId?.toString() ?? '';

    final rows = await db.query(
      'draft_orders',
      where: 'status = ? AND (employee_id IS NULL OR employee_id = ?)',
      whereArgs: ['finalized', userId],
      orderBy: 'finalized_at DESC, updated_at DESC, id DESC',
    );

    final out = <DraftOrderWithItems>[];
    for (final row in rows) {
      final id = row['id'] as int?;
      if (id == null) continue;
      final draft = await getDraftById(id);
      if (draft != null) {
        out.add(draft);
      }
    }
    return out;
  }
}
