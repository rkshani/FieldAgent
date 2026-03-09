import 'dart:convert';

/// Formats order data to match Android's upload format
/// Android: createJson in OrderActivity using underscore-delimited strings
class OrderUploadFormatter {
  /// Format order header to Android format
  /// Format: id_partyName_pkgName_deliveryPoint_orderBy_timestamp_remarks_grossTotal_
  ///         discount_netTotal_deliveryParty_advancePaymentDeal_deliveryPartyRemarks_
  ///         deliveryPointRemarks_visit_id_city_id_loc_routeid_goodsAgencyid_goodsAgencyname
  static String formatOrderHeader({
    required String orderId,
    required String partyName,
    required String packageName,
    required String deliveryPoint,
    required String orderBy,
    required String timestamp,
    required String remarks,
    required String grossTotal,
    required String discount,
    required String netTotal,
    required String deliveryParty,
    required String advancePaymentDeal,
    required String deliveryPartyRemarks,
    required String deliveryPointRemarks,
    required String visitId,
    required String cityId,
    required String location,
    required String routeId,
    required String goodsAgencyId,
    required String goodsAgencyName,
  }) {
    return [
      orderId,
      partyName,
      packageName,
      deliveryPoint,
      orderBy,
      timestamp,
      remarks,
      grossTotal,
      discount,
      netTotal,
      deliveryParty,
      advancePaymentDeal,
      deliveryPartyRemarks,
      deliveryPointRemarks,
      visitId,
      cityId,
      location,
      routeId,
      goodsAgencyId,
      goodsAgencyName,
    ].join('_');
  }

  /// Format order items to Android format
  /// Format per item: orderID_name_price_qty_percent_total_grossAmount_remarks_directionStore_
  ///                   specialRemarks_specialPrice_subitemid/
  /// Items are joined without separator (each ends with /)
  static String formatOrderItems({
    required List<Map<String, dynamic>> items,
    required String orderId,
  }) {
    final formattedItems = <String>[];

    for (final item in items) {
      final specialRemarks = item['special_remarks']?.toString() ?? '';
      final parts = specialRemarks.contains('_')
          ? specialRemarks.split('_')
          : [specialRemarks, ''];

      final remarksPart = parts[0];
      final subitemId = parts.length > 1 ? parts[1] : '';

      final price = _safeString(item['price'] ?? '0');
      final qty = _safeString(item['quantity'] ?? item['qty'] ?? '0');
      final priceNum = double.tryParse(price) ?? 0;
      final qtyNum = int.tryParse(qty) ?? 0;
      final grossAmount = (priceNum * qtyNum).toString();

      final itemStr = [
        orderId,
        _safeString(item['name'] ?? item['bookname'] ?? ''),
        price,
        qty,
        _safeString(item['discount_percent'] ?? item['percent'] ?? '0'),
        _safeString(item['total'] ?? grossAmount),
        grossAmount,
        _safeString(item['remarks'] ?? ''),
        _safeString(item['direction_store'] ?? ''),
        remarksPart,
        _safeString(item['special_price'] ?? '0'),
        subitemId,
      ].join('_');

      formattedItems.add('$itemStr/');
    }

    // Join all items and remove trailing /
    final joined = formattedItems.join('');
    return joined.endsWith('/')
        ? joined.substring(0, joined.length - 1)
        : joined;
  }

  /// Safe string conversion (empty string if null)
  static String _safeString(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  /// Build complete order payload for API
  static Map<String, String> buildOrderPayload({
    required String orderHeader,
    required String orderItems,
  }) {
    return {'order': orderHeader, 'item': orderItems};
  }

  /// Parse order response (Android expects {"status": "success"} or {"status": "failed"})
  static OrderUploadResult parseResponse(String responseBody) {
    try {
      // Try to parse as JSON
      final json = _tryParseJson(responseBody);
      if (json != null && json is Map) {
        final status = json['status']?.toString().toLowerCase() ?? '';
        if (status == 'success') {
          return OrderUploadResult(
            success: true,
            message:
                json['message']?.toString() ?? 'Order uploaded successfully',
            bookingId: json['booking_id']?.toString(),
          );
        } else {
          return OrderUploadResult(
            success: false,
            message: json['message']?.toString() ?? 'Upload failed',
            error: json['error']?.toString(),
          );
        }
      }

      // Fallback: assume failure if not parseable
      return OrderUploadResult(
        success: false,
        message: 'Invalid response format',
        error: responseBody,
      );
    } catch (e) {
      return OrderUploadResult(
        success: false,
        message: 'Error parsing response',
        error: e.toString(),
      );
    }
  }

  static dynamic _tryParseJson(String text) {
    try {
      final parsed = text.trim();
      if (parsed.isEmpty) return null;
      return json.decode(parsed);
    } catch (_) {
      return null;
    }
  }
}

/// Result of order upload attempt
class OrderUploadResult {
  final bool success;
  final String message;
  final String? bookingId;
  final String? error;

  OrderUploadResult({
    required this.success,
    required this.message,
    this.bookingId,
    this.error,
  });
}
