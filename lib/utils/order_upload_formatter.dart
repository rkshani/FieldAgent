import 'dart:convert';

/// Formats order data to match Android's upload format
/// Android: createJson in OrderActivity using underscore-delimited strings
class OrderUploadFormatter {
  static const String _defaultFieldValue = '0';

  /// Format order header to Android format
  /// Strict legacy format (as provided sample):
  /// orderId_partyName_billToPartyId_packageId_deliveryPoint_checkedBy_orderBy_salesman_
  /// timestamp_remarks_gross_discount_net_deliveryParty_advancePaymentDeal_
  /// deliveryPartyRemarks_visitId_cityId_loc_routeId_goodsAgencyId_goodsAgencyName//
  static String formatOrderHeader({
    required String orderId,
    required String partyName,
    required String billToPartyId,
    required String packageName,
    required String deliveryPoint,
    required String checkedBy,
    required String orderBy,
    required String salesmanName,
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
      _safeString(orderId, fallback: _defaultFieldValue),
      _safeString(partyName, fallback: _defaultFieldValue),
      _safeString(billToPartyId, fallback: _defaultFieldValue),
      _safeString(packageName, fallback: _defaultFieldValue),
      _safeString(deliveryPoint, fallback: _defaultFieldValue),
      _safeString(checkedBy, fallback: _defaultFieldValue),
      _safeString(orderBy, fallback: _defaultFieldValue),
      _safeString(salesmanName, fallback: _defaultFieldValue),
      _safeString(timestamp, fallback: _defaultFieldValue),
      _safeString(remarks, fallback: _defaultFieldValue),
      _safeString(grossTotal, fallback: _defaultFieldValue),
      _safeString(discount, fallback: _defaultFieldValue),
      _safeString(netTotal, fallback: _defaultFieldValue),
      _safeString(deliveryParty, fallback: _defaultFieldValue),
      _safeString(advancePaymentDeal, fallback: _defaultFieldValue),
      _safeString(deliveryPartyRemarks, fallback: _defaultFieldValue),
      _safeString(deliveryPointRemarks, fallback: _defaultFieldValue),
      _safeString(visitId, fallback: _defaultFieldValue),
      _safeString(cityId, fallback: _defaultFieldValue),
      _safeString(location, fallback: _defaultFieldValue),
      _safeString(routeId, fallback: _defaultFieldValue),
      _safeString(goodsAgencyId, fallback: _defaultFieldValue),
      _safeString(goodsAgencyName, fallback: _defaultFieldValue),
    ].join('_') + '//';
  }

  /// Format order items to Android format
  /// Strict legacy item format per item:
  /// orderId_x_x_itemId_qty_price_percent_groupDiscount_total_gross_x_directionStore_remark_specialPrice_subitemId/
  /// Items are joined without extra separator and each item keeps trailing '/'.
  static String formatOrderItems({
    required List<Map<String, dynamic>> items,
    required String orderId,
  }) {
    final formattedItems = <String>[];

    for (final item in items) {
      final parsedSpecial = _extractSpecialRemarkParts(
        item['special_remarks']?.toString() ?? '',
      );
      final remarksPart = parsedSpecial.remarks;
      final subitemId = _safeString(
        item['subitem_id'] ?? parsedSpecial.subItemId,
        fallback: '',
      );

      final price = _safeString(item['price'] ?? '0', fallback: '0');
      final qty = _safeString(
        item['quantity'] ?? item['qty'] ?? '0',
        fallback: '0',
      );
      final priceNum = double.tryParse(price) ?? 0;
      final qtyNum = int.tryParse(qty) ?? 0;
      final grossAmount = (priceNum * qtyNum).toString();

      final itemStr = [
        orderId,
        'x',
        'x',
        _safeString(item['item_id'] ?? item['bookid'] ?? '', fallback: _defaultFieldValue),
        qty,
        price,
        _safeString(
          item['discount_percent'] ?? item['percent'] ?? '0',
          fallback: '0',
        ),
        _safeString(item['group_discount'] ?? '0', fallback: '0'),
        _safeString(item['total'] ?? grossAmount, fallback: '0'),
        grossAmount,
        'x',
        _safeString(item['direction_store'] ?? '', fallback: _defaultFieldValue),
        _safeString(remarksPart, fallback: _defaultFieldValue),
        _safeString(item['special_price'] ?? '0', fallback: '0'),
        _safeString(subitemId, fallback: _defaultFieldValue),
      ].join('_');

      formattedItems.add('$itemStr/');
    }

    // Keep trailing slash to match strict legacy sample.
    return formattedItems.join('');
  }

  /// Safe string conversion (empty string if null)
  static String _safeString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final raw = value.toString().trim();
    if (raw.isEmpty) return fallback;

    // Strings are parsed by backend using underscore and slash delimiters.
    return raw
        .replaceAll('_', ' ')
        .replaceAll('/', '-')
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .trim();
  }

  static _SpecialRemarkParts _extractSpecialRemarkParts(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return const _SpecialRemarkParts(remarks: '', subItemId: '');
    }

    final parts = value.split('_');
    if (parts.length < 2) {
      return _SpecialRemarkParts(remarks: parts.first, subItemId: '');
    }

    return _SpecialRemarkParts(
      remarks: parts.first,
      subItemId: parts.sublist(1).join('_'),
    );
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

class _SpecialRemarkParts {
  final String remarks;
  final String subItemId;

  const _SpecialRemarkParts({required this.remarks, required this.subItemId});
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
