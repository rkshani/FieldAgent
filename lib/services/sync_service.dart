import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/draft_order.dart';
import '../models/draft_order_item.dart';
import 'api_client.dart';
import 'api_endpoints.dart';
import 'draft_order_service.dart';
import 'session_service.dart';

/// Uploads finalized order when internet is available.
/// Android: uploadIfInterNetAvailable(); payload aligns with Android bookings INSERT.
class SyncService {
  SyncService._();

  static final SyncService instance = SyncService._();

  String get uploadEndpoint => ApiEndpoints.postOrderZNewTest();

  /// Upload using booking id (loads booking + booking_items, Android param names).
  /// Returns true if upload succeeded.
  Future<bool> uploadBooking(int bookingId) async {
    final result = await uploadBookingWithResult(bookingId);
    return result.success;
  }

  /// Upload with detailed response info for debugging and user preview.
  Future<SyncUploadResult> uploadBookingWithResult(int bookingId) async {
    final booking = await DraftOrderService.instance.getBookingById(bookingId);
    if (booking == null) {
      return SyncUploadResult(
        bookingId: bookingId,
        api: uploadEndpoint,
        success: false,
        error: 'Booking not found',
      );
    }
    final items = await DraftOrderService.instance.getBookingItems(bookingId);
    final payload = _buildAndroidPayload(booking, items);
    return _postOrderDetailed(bookingId, payload);
  }

  /// Build exact POST preview payload for one pending booking.
  Future<Map<String, dynamic>?> getUploadPreviewForBooking(int bookingId) async {
    final booking = await DraftOrderService.instance.getBookingById(bookingId);
    if (booking == null) return null;
    final items = await DraftOrderService.instance.getBookingItems(bookingId);
    final payload = _buildAndroidPayload(booking, items);
    return {
      'booking_id': bookingId,
      'api': uploadEndpoint,
      'method': 'POST',
      'content_type': 'application/x-www-form-urlencoded',
      'body': payload.map((k, v) => MapEntry(k, v?.toString() ?? '')),
    };
  }

  /// Build payload matching Android INSERT: orderby, invdate, partyid, package_id, remarks, status, employeeid, localinvno, deliverypoint, isandroid, delivery_party, deal_id, goodsagency_id + items.
  Map<String, dynamic> _buildAndroidPayload(
    Map<String, dynamic> booking,
    List<Map<String, dynamic>> items,
  ) {
    final map = <String, dynamic>{
      'orderby': booking['orderby'] ?? 1013,
      'invdate': booking['invdate'] ?? '',
      'partyid': booking['partyid'] ?? '0',
      'package_id': booking['package_id'] ?? '1',
      'remarks': booking['remarks'] ?? '',
      'status': booking['status'] ?? 1,
      'employeeid': booking['employeeid'] ?? '1013',
      'localinvno': booking['localinvno'] ?? '0',
      'deliverypoint': booking['deliverypoint'] ?? 'Direct to Party (Bilty)',
      'isandroid': booking['isandroid'] ?? '1',
      'delivery_party': booking['delivery_party'] ?? '0',
      'deal_id': booking['deal_id'] ?? '0',
      'goodsagency_id': booking['goodsagency_id'] ?? '0',
    };
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      map['item_id_$i'] = item['item_id'];
      map['item_name_$i'] = item['item_name'];
      map['qty_$i'] = item['quantity'];
      map['unit_price_$i'] = item['unit_price'];
      map['discount_percent_$i'] = item['discount_percent'];
    }
    map['item_count'] = items.length;
    return map;
  }

  /// Legacy: upload from draft order + items (builds Android-style payload from draft).
  Future<bool> uploadIfInterNetAvailable({
    required DraftOrder order,
    required List<DraftOrderItem> items,
  }) async {
    final employeeId = await SessionService.getEmployeeId();
    if (employeeId == null) return false;
    final invdate = order.finalizedAt ?? order.updatedAt ?? DateTime.now().toIso8601String();
    final localinvno = (order.orderSerialNo ?? order.id).toString();
    final booking = <String, dynamic>{
      'orderby': int.tryParse(employeeId.toString()) ?? 1013,
      'invdate': invdate,
      'partyid': order.billToPartyId ?? '0',
      'package_id': order.packageId ?? '1',
      'remarks': order.orderRemarks ?? '',
      'status': 1,
      'employeeid': employeeId.toString(),
      'localinvno': localinvno,
      'deliverypoint': order.deliveryPointName ?? order.deliveryAddress ?? 'Direct to Party (Bilty)',
      'isandroid': '1',
      'delivery_party': order.shipToPartyId ?? '0',
      'deal_id': order.paymentDealId ?? '0',
      'goodsagency_id': order.goodsAgencyId ?? '0',
    };
    final itemsMap = items
        .map(
          (i) => {
            'item_id': i.itemId,
            'item_name': i.itemName,
            'quantity': i.quantity,
            'unit_price': i.unitPrice,
            'discount_percent': i.discountPercent,
          },
        )
        .toList();
    final list = itemsMap.map((m) => Map<String, dynamic>.from(m)).toList();
    final payload = _buildAndroidPayload(booking, list);
    return _postOrder(payload);
  }

  Future<bool> _postOrder(Map<String, dynamic> payload) async {
    final result = await _postOrderDetailed(0, payload);
    return result.success;
  }

  Future<SyncUploadResult> _postOrderDetailed(
    int bookingId,
    Map<String, dynamic> payload,
  ) async {
    try {
      final url = ApiEndpoints.postOrderZNewTest();
      final formData = payload.map((k, v) => MapEntry(k, v?.toString() ?? ''));
      final response = await ApiClient.instance.dio.post<String>(
        url,
        data: formData,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Accept': 'application/json'},
        ),
      );

      final rawBody = response.data?.toString() ?? '';
      Map<String, dynamic>? parsed;
      try {
        final decoded = jsonDecode(rawBody);
        if (decoded is Map<String, dynamic>) {
          parsed = decoded;
        }
      } catch (_) {
        // raw text response is still useful for preview.
      }

      final statusCode = response.statusCode ?? 0;
      final parsedStatus = parsed?['status']?.toString().toLowerCase();
      final ok = statusCode == 200 &&
          (parsed == null ||
              parsedStatus == null ||
              parsedStatus == 'success' ||
              parsedStatus == 'true' ||
              parsedStatus == '1');

      if (!ok) {
        debugPrint('SyncService._postOrder: status=$statusCode body=$rawBody');
      }

      return SyncUploadResult(
        bookingId: bookingId,
        api: url,
        success: ok,
        statusCode: statusCode,
        requestBody: formData,
        responseBody: rawBody,
        parsedResponse: parsed,
      );
    } catch (e) {
      debugPrint('SyncService._postOrder: $e');
      return SyncUploadResult(
        bookingId: bookingId,
        api: uploadEndpoint,
        success: false,
        requestBody: payload.map((k, v) => MapEntry(k, v?.toString() ?? '')),
        error: e.toString(),
      );
    }
  }
}

class SyncUploadResult {
  final int bookingId;
  final String api;
  final bool success;
  final int? statusCode;
  final Map<String, String>? requestBody;
  final String? responseBody;
  final Map<String, dynamic>? parsedResponse;
  final String? error;

  const SyncUploadResult({
    required this.bookingId,
    required this.api,
    required this.success,
    this.statusCode,
    this.requestBody,
    this.responseBody,
    this.parsedResponse,
    this.error,
  });

  Map<String, dynamic> toMap() {
    return {
      'booking_id': bookingId,
      'api': api,
      'success': success,
      'status_code': statusCode,
      'request_body': requestBody,
      'response_body': responseBody,
      'parsed_response': parsedResponse,
      'error': error,
    };
  }
}
