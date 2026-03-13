import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/draft_order.dart';
import '../models/draft_order_item.dart';
import '../utils/order_upload_formatter.dart';
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
  Future<Map<String, dynamic>?> getUploadPreviewForBooking(
    int bookingId,
  ) async {
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

  /// Build payload matching Android OrderActivity upload:
  /// body keys: order, item (underscore-delimited strings).
  Map<String, dynamic> _buildAndroidPayload(
    Map<String, dynamic> booking,
    List<Map<String, dynamic>> items,
  ) {
    final grossTotal = items.fold<double>(0, (sum, item) {
      final qty =
          (item['quantity'] as num?)?.toDouble() ??
          double.tryParse(item['quantity']?.toString() ?? '0') ??
          0;
      final unit =
          (item['unit_price'] as num?)?.toDouble() ??
          double.tryParse(item['unit_price']?.toString() ?? '0') ??
          0;
      return sum + (qty * unit);
    });
    final totalDiscount = items.fold<double>(0, (sum, item) {
      final qty =
          (item['quantity'] as num?)?.toDouble() ??
          double.tryParse(item['quantity']?.toString() ?? '0') ??
          0;
      final unit =
          (item['unit_price'] as num?)?.toDouble() ??
          double.tryParse(item['unit_price']?.toString() ?? '0') ??
          0;
      final pct =
          (item['discount_percent'] as num?)?.toDouble() ??
          double.tryParse(item['discount_percent']?.toString() ?? '0') ??
          0;
      return sum + ((qty * unit) * (pct / 100));
    });
    final netTotal = grossTotal - totalDiscount;

    final orderHeader = OrderUploadFormatter.formatOrderHeader(
      orderId: booking['localinvno']?.toString() ?? '0',
      partyName: booking['party_name']?.toString() ?? 'x',
      billToPartyId: booking['partyid']?.toString() ?? '0',
      packageName: booking['package_id']?.toString() ?? '0',
      deliveryPoint:
          booking['deliverypoint']?.toString() ?? 'Direct to Party (Bilty)',
      checkedBy: booking['employeeid']?.toString() ?? '1013',
      orderBy: booking['employeeid']?.toString() ?? '1013',
      salesmanName: booking['salesman_name']?.toString() ?? 'Salesman',
      timestamp: booking['invdate']?.toString() ?? '',
      remarks: booking['remarks']?.toString() ?? '',
      grossTotal: grossTotal.toStringAsFixed(2),
      discount: totalDiscount.toStringAsFixed(2),
      netTotal: netTotal.toStringAsFixed(2),
      deliveryParty: booking['delivery_party']?.toString() ?? '0',
      advancePaymentDeal: booking['deal_id']?.toString() ?? '0',
      deliveryPartyRemarks: booking['delivery_party_remarks']?.toString() ?? '',
      deliveryPointRemarks: booking['delivery_point_remarks']?.toString() ?? '',
      visitId: booking['visit_id']?.toString() ?? '',
      cityId: booking['city_id']?.toString() ?? '',
      location: booking['loc']?.toString() ?? '',
      routeId: booking['routeid']?.toString() ?? '',
      goodsAgencyId: booking['goodsagency_id']?.toString() ?? '0',
      goodsAgencyName: booking['goodsagency_name']?.toString() ?? '',
    );

    final orderItems = OrderUploadFormatter.formatOrderItems(
      items: items.map((item) {
        return {
          'item_id': item['item_id']?.toString() ?? '',
          'name': item['item_name']?.toString() ?? '',
          'price': item['unit_price']?.toString() ?? '0',
          'quantity': item['quantity']?.toString() ?? '0',
          'discount_percent': item['discount_percent']?.toString() ?? '0',
          'total': _lineNet(item).toStringAsFixed(2),
          'remarks': item['remarks']?.toString() ?? '',
          'direction_store': item['direction_store']?.toString() ?? '',
          'special_remarks': item['special_remarks']?.toString() ?? '',
          'special_price': item['special_price']?.toString() ?? '0',
          'subitem_id': item['subitem_id']?.toString() ?? '',
        };
      }).toList(),
      orderId: booking['localinvno']?.toString() ?? '0',
    );

    return OrderUploadFormatter.buildOrderPayload(
      orderHeader: orderHeader,
      orderItems: orderItems,
    );
  }

  double _lineNet(Map<String, dynamic> item) {
    final qty =
        (item['quantity'] as num?)?.toDouble() ??
        double.tryParse(item['quantity']?.toString() ?? '0') ??
        0;
    final unit =
        (item['unit_price'] as num?)?.toDouble() ??
        double.tryParse(item['unit_price']?.toString() ?? '0') ??
        0;
    final pct =
        (item['discount_percent'] as num?)?.toDouble() ??
        double.tryParse(item['discount_percent']?.toString() ?? '0') ??
        0;
    final gross = qty * unit;
    return gross - (gross * pct / 100);
  }

  /// Legacy: upload from draft order + items (builds Android-style payload from draft).
  Future<bool> uploadIfInterNetAvailable({
    required DraftOrder order,
    required List<DraftOrderItem> items,
  }) async {
    final employeeId = await SessionService.getEmployeeId();
    if (employeeId == null) return false;
    final invdate = order.finalizedAt ?? order.updatedAt;
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
      'deliverypoint':
          order.deliveryPointName ??
          order.deliveryAddress ??
          'Direct to Party (Bilty)',
      'isandroid': '1',
      'delivery_party': order.shipToPartyId ?? '0',
      'deal_id': order.paymentDealId ?? '0',
      'goodsagency_id': order.goodsAgencyId ?? '0',
      'goodsagency_name': order.goodsAgencyName ?? '',
      'delivery_party_remarks':
          order.deliveryPartyRemarks ?? order.deliveryAddress ?? '',
      'delivery_point_remarks': order.deliveryPointRemarks ?? '',
      'visit_id': order.visitId ?? '',
      'city_id': order.cityId ?? '',
      'loc': order.location ?? '',
      'routeid': order.routeId ?? '',
    };
    final itemsMap = items
        .map(
          (i) => {
            'item_id': i.itemId,
            'item_name': i.itemName,
            'quantity': i.quantity,
            'unit_price': i.unitPrice,
            'discount_percent': i.discountPercent,
            'remarks': i.remarks,
            'direction_store': i.directionStore,
            'special_remarks': i.specialRemarks,
            'special_price': i.specialPrice,
            'subitem_id': i.subItemId,
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
      final headers = <String, String>{
        'Accept': 'application/json',
        'Content-Type': Headers.formUrlEncodedContentType,
      };

      print('URL: $url');
      print('Headers: $headers');
      print('Body: $formData');

      final response = await ApiClient.instance.dio.post<String>(
        url,
        data: formData,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Accept': 'application/json'},
        ),
      );

      final rawBody = response.data?.toString() ?? '';
      print('Status Code: ${response.statusCode}');
      print('Response: $rawBody');
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
      final ok =
          statusCode == 200 &&
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
      print('SyncService _postOrderDetailed Error: $e');
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
