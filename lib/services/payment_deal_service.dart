import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/payment_method.dart';
import 'api_client.dart';
import 'api_endpoints.dart';

/// Fetches payment methods for a party when package rules require payment deal.
/// Android: getPaymentMethods(partyId)
class PaymentDealService {
  PaymentDealService._();

  static final PaymentDealService instance = PaymentDealService._();

  /// Path and param: API format /tclorder_apis_new_test/app_web_api.php?get_payment_deals=1&partyid=
  static String path(String partyId) =>
      'app_web_api.php?get_payment_deals=1&partyid=$partyId';

  /// Fetches payment methods for the given party. Returns list of PaymentMethod objects.
  Future<List<PaymentMethod>> getPaymentMethods(String partyId) async {
    try {
      final url = ApiEndpoints.paymentDeals(partyId);
      final response = await ApiClient.instance.dio.get<String>(url);
      if (response.statusCode == 200 &&
          response.data != null &&
          response.data!.trim().isNotEmpty) {
        final d = jsonDecode(response.data!);
        if (d is List) {
          return d
              .map(
                (e) => PaymentMethod.fromJson(
                  e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{},
                ),
              )
              .toList();
        }
        if (d is Map) {
          final map = d as Map<String, dynamic>;
          if (map['data'] is List) {
            return (map['data'] as List)
                .map(
                  (e) => PaymentMethod.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList();
          }
          if (map['payment_methods'] is List) {
            return (map['payment_methods'] as List)
                .map(
                  (e) => PaymentMethod.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList();
          }
        }
      }
    } catch (e) {
      debugPrint('PaymentDealService.getPaymentMethods: $e');
    }
    return [];
  }

  /// Check if payment deal is required based on package scheme
  /// Android logic: if package scheme == 2, show payment deal section
  bool isPaymentDealRequired(Map<String, dynamic>? packageData) {
    if (packageData == null) return false;
    final scheme = packageData['scheme']?.toString();
    return scheme == '2';
  }
}
