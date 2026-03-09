import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/already_added_item.dart';
import 'api_client.dart';
import 'local_db_service.dart';
import 'session_service.dart';
import 'order_data_normalizer.dart';

/// Fetches already-in-order items and saves locally.
/// Android: order_web_api_z.php?get_already_in_order_items=1...
class AlreadyAddedItemService {
  AlreadyAddedItemService._();

  static final AlreadyAddedItemService instance = AlreadyAddedItemService._();

  static const String cacheKey = 'local_already_in_order_items';

  /// Builds URL with userid and optional order/draft params. Adjust to match Android.
  Future<String> _buildUrl({String? orderId}) async {
    final employeeId = await SessionService.getEmployeeId();
    final uid = employeeId?.toString() ?? '';
    final base = 'order_web_api_z.php?get_already_in_order_items=1&userid=$uid';
    if (orderId != null && orderId.isNotEmpty)
      return base + '&order_id=$orderId';
    return base;
  }

  /// Fetches already-in-order items and saves to cache.
  Future<bool> fetchAndSave({String? orderId}) async {
    try {
      final path = await _buildUrl(orderId: orderId);
      final url = ApiClient.instance.getTclOrderWebUrl(path);
      final response = await ApiClient.instance.dio.get<String>(url);
      if (response.statusCode == 200 &&
          response.data != null &&
          response.data!.trim().isNotEmpty) {
        await LocalDbService.instance.saveLocalData(
          cacheKey: cacheKey,
          payload: response.data!,
        );
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('AlreadyAddedItemService.fetchAndSave: $e');
      return false;
    }
  }

  /// Returns cached list of already-in-order items (parsed).
  Future<List<Map<String, dynamic>>> getCachedItems() async {
    final payload = await LocalDbService.instance.getLocalData(cacheKey);
    if (payload == null || payload.isEmpty) return [];
    try {
      final d = jsonDecode(payload);
      if (d is List) {
        return d
            .whereType<Map>()
            .map(
              (e) => OrderDataNormalizer.normalizeItem(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList();
      }
      if (d is Map) {
        final map = d as Map<String, dynamic>;
        for (final key in const [
          'data',
          'items',
          'result',
          'rows',
          'records',
        ]) {
          final value = map[key];
          if (value is List) {
            return value
                .whereType<Map>()
                .map(
                  (e) => OrderDataNormalizer.normalizeItem(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList();
          }
        }
      }
    } catch (_) {}
    return [];
  }

  /// Get already-added items as AlreadyAddedItem models
  Future<List<AlreadyAddedItem>> getAlreadyAddedItems() async {
    final payload = await LocalDbService.instance.getLocalData(cacheKey);
    if (payload == null || payload.isEmpty) return [];
    try {
      final d = jsonDecode(payload);
      if (d is List) {
        return d
            .whereType<Map>()
            .map((e) => AlreadyAddedItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      if (d is Map) {
        final map = d as Map<String, dynamic>;
        for (final key in const [
          'data',
          'items',
          'result',
          'rows',
          'records',
        ]) {
          final value = map[key];
          if (value is List) {
            return value
                .whereType<Map>()
                .map(
                  (e) =>
                      AlreadyAddedItem.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList();
          }
        }
      }
    } catch (e) {
      debugPrint('AlreadyAddedItemService.getAlreadyAddedItems: $e');
    }
    return [];
  }

  /// Check if an item is already in an order
  Future<bool> isItemAlreadyAdded(String itemId) async {
    final items = await getAlreadyAddedItems();
    return items.any((item) => item.bookId == itemId && item.isInOrder);
  }

  /// Get set of already-added book IDs for fast lookup
  Future<Set<String>> getAlreadyAddedBookIds() async {
    final items = await getAlreadyAddedItems();
    return items
        .where((item) => item.isInOrder && item.bookId != null)
        .map((item) => item.bookId!)
        .toSet();
  }
}
