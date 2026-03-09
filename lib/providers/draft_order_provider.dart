import 'package:flutter/foundation.dart';

import '../models/draft_order.dart';
import '../models/draft_order_item.dart';
import '../services/draft_order_service.dart';
import '../services/sync_service.dart';

/// Provider for the current draft order. Data of record is in SQLite (DraftOrderService).
class DraftOrderProvider extends ChangeNotifier {
  DraftOrderProvider() {
    loadDraft();
  }

  DraftOrderWithItems? _draft;
  bool _loading = true;
  String? _error;

  DraftOrderWithItems? get draft => _draft;
  bool get loading => _loading;
  String? get error => _error;

  int? get currentDraftId => _draft?.order.id;

  List<DraftOrderItem> get items => _draft?.items ?? [];
  double get grossAmount => _draft?.grossAmount ?? 0;
  double get totalDiscount => _draft?.totalDiscount ?? 0;
  double get netAmount => _draft?.netAmount ?? 0;

  /// Loads current draft from DB (or creates one).
  Future<void> loadDraft() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _draft = await DraftOrderService.instance.getCurrentDraft();
      _error = null;
    } catch (e) {
      _error = e.toString();
      _draft = null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Updates header field(s). Keys: snake_case (e.g. bill_to_party_id, party_name).
  Future<void> updateHeader(Map<String, dynamic> updates) async {
    final id = _draft?.order.id;
    if (id == null) return;
    await DraftOrderService.instance.updateDraftHeader(id, updates);
    await loadDraft();
  }

  Future<void> updateParty(String? partyId, String? partyName) async {
    await updateHeader({'bill_to_party_id': partyId, 'party_name': partyName});
  }

  Future<void> updateShipTo(String? partyId, String? name) async {
    await updateHeader({'ship_to_party_id': partyId, 'delivery_party_name': name});
  }

  Future<void> updateGoodsAgency(String? id, String? name) async {
    await updateHeader({'goods_agency_id': id, 'goods_agency_name': name});
  }

  Future<void> updatePackage(String? id, String? name) async {
    await updateHeader({'package_id': id, 'package_name': name});
  }

  Future<void> updatePaymentDeal(String? id) async {
    await updateHeader({'payment_deal_id': id});
  }

  Future<void> updateDeliveryPoint(String? id, String? name) async {
    await updateHeader({'delivery_point_id': id, 'delivery_point_name': name});
  }

  Future<void> updateVisit(String? visitId, String? routeId) async {
    await updateHeader({'visit_id': visitId, 'route_id': routeId});
  }

  Future<void> updateDeliveryAddress(String? address) async {
    await updateHeader({'delivery_address': address});
  }

  /// Adds a line item (persists to DB).
  Future<void> addLineItem({
    String? itemId,
    required String itemName,
    required int quantity,
    required double unitPrice,
    double discountPercent = 0,
    String? specialRemarks,
  }) async {
    final id = _draft?.order.id;
    if (id == null) return;
    await DraftOrderService.instance.insertLineItem(
      draftOrderId: id,
      itemId: itemId,
      itemName: itemName,
      quantity: quantity,
      unitPrice: unitPrice,
      discountPercent: discountPercent,
      specialRemarks: specialRemarks,
    );
    await loadDraft();
  }

  /// Removes a line item by id.
  Future<void> removeLineItem(int itemId) async {
    await DraftOrderService.instance.deleteLineItem(itemId);
    await loadDraft();
  }

  /// Resets current draft (clear header and items in DB).
  Future<void> reset() async {
    final id = _draft?.order.id;
    if (id == null) return;
    _draft = await DraftOrderService.instance.resetDraft(id);
    notifyListeners();
  }

  /// Finalizes current draft, triggers sync, creates new blank draft.
  Future<bool> finalize() async {
    final id = _draft?.order.id;
    if (id == null || (_draft?.items.isEmpty ?? true)) return false;
    final finalized = await DraftOrderService.instance.finalizeDraft(id);
    if (finalized != null) {
      await SyncService.instance.uploadIfInterNetAvailable(
        order: finalized.order,
        items: finalized.items,
      );
    }
    await DraftOrderService.instance.createNewDraft();
    await loadDraft();
    return true;
  }
}
