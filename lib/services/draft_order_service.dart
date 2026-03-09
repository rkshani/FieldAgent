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
    final orderRows = await db.query('draft_orders', where: 'id = ?', whereArgs: [draftId]);
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
    final id = await db.insert('draft_orders', {
      'local_order_id': localOrderId,
      'status': 'draft',
      'created_at': now,
      'updated_at': now,
      'employee_id': employeeId?.toString(),
    });
    await _setCurrentDraftId(id);
    final draft = await getDraftById(id);
    return draft?.order;
  }

  /// Updates header fields on the current draft (party, ship-to, agency, package, payment deal, address, etc.).
  Future<void> updateDraftHeader(int draftId, Map<String, dynamic> updates) async {
    final db = await _db;
    final allowed = {
      'bill_to_party_id', 'party_name', 'ship_to_party_id', 'delivery_party_name',
      'delivery_point_id', 'delivery_point_name', 'goods_agency_id', 'goods_agency_name',
      'visit_id', 'route_id', 'package_id', 'package_name', 'payment_deal_id', 'delivery_address',
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
    final row = await db.query('draft_order_items', where: 'id = ?', whereArgs: [itemId]);
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

  /// Resets current draft: clear header and delete all line items (or create new blank draft).
  Future<DraftOrderWithItems?> resetDraft(int draftId) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    await db.delete('draft_order_items', where: 'draft_order_id = ?', whereArgs: [draftId]);
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
      {'status': 'finalized', 'finalized_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [draftId],
    );
    return getDraftById(draftId);
  }
}
