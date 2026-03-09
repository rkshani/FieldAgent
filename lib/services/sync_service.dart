import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/draft_order.dart';
import '../models/draft_order_item.dart';
import 'api_client.dart';
import 'session_service.dart';

/// Uploads finalized order and attendance when internet is available.
/// Android: uploadIfInterNetAvailable()
class SyncService {
  SyncService._();

  static final SyncService instance = SyncService._();

  /// Adjust path to match Android upload endpoint.
  static const String uploadOrderPath = 'order_web_api_z.php?upload_order=1';

  /// Calls upload when online. Pass the finalized draft (header + items).
  /// Returns true if upload succeeded.
  Future<bool> uploadIfInterNetAvailable({
    required DraftOrder order,
    required List<DraftOrderItem> items,
  }) async {
    try {
      final baseUrl = await ApiClient.instance.getAgentBaseUrl();
      final employeeId = await SessionService.getEmployeeId();
      if (employeeId == null) return false;
      final base = baseUrl.replaceAll(RegExp(r'/$'), '');
      final url = '$base/tclorder_apis/$uploadOrderPath';
      final payload = _buildPayload(order, items, employeeId.toString());

      final response = await ApiClient.instance.dio.post<String>(
        url,
        data: payload,
        options: Options(contentType: 'application/x-www-form-urlencoded', headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode == 200) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('SyncService.uploadIfInterNetAvailable: $e');
      return false;
    }
  }

  Map<String, dynamic> _buildPayload(DraftOrder order, List<DraftOrderItem> items, String employeeId) {
    return {
      'employee_id': employeeId,
      'local_order_id': order.localOrderId,
      'party_id': order.billToPartyId,
      'party_name': order.partyName,
      'delivery_address': order.deliveryAddress,
      'goods_agency_id': order.goodsAgencyId,
      'visit_id': order.visitId,
      'package_id': order.packageId,
      'payment_deal_id': order.paymentDealId,
      'items': items.map((i) => {
            'item_id': i.itemId,
            'item_name': i.itemName,
            'quantity': i.quantity,
            'unit_price': i.unitPrice,
            'discount_percent': i.discountPercent,
          }).toList(),
    };
  }
}
