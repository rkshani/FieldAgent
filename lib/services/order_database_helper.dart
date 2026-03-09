import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/package_details.dart';
import 'local_db_service.dart';
import 'order_data_normalizer.dart';

/// Reads local API cache and returns counts for Update DB summary (no separate DB).
class OrderDatabaseHelper {
  OrderDatabaseHelper._();
  static final OrderDatabaseHelper instance = OrderDatabaseHelper._();

  static const List<String> _itemsKeys = [
    'items',
    'Items',
    'ITEM',
    'item',
    'Item',
    'data',
    'Data',
    'DATA',
    'result',
    'Result',
    'rows',
    'records',
    'list',
    'List',
  ];

  static const List<String> _packagesKeys = [
    'packages',
    'Packages',
    'PACKAGES',
    'package',
    'Package',
    'data',
    'Data',
    'DATA',
    'result',
    'Result',
    'rows',
    'records',
    'list',
    'List',
  ];

  static const List<String> _partiesKeys = [
    'parties',
    'party',
    'data',
    'result',
    'rows',
    'records',
  ];

  static const List<String> _deliveryPointsKeys = [
    'delivery_points',
    'deliver_points',
    'stores',
    'data',
    'result',
    'rows',
    'records',
  ];

  static const List<String> _agenciesKeys = [
    'agencies',
    'goods_agency',
    'agency',
    'data',
    'result',
    'rows',
    'records',
  ];

  static const List<String> _storeDataKeys = [
    'stores',
    'store_data',
    'data',
    'result',
    'rows',
    'records',
  ];

  static List<String> _preferredKeysForCache(String cacheKey) {
    switch (cacheKey) {
      case 'local_items':
        return _itemsKeys;
      case 'local_packages':
        return _packagesKeys;
      case 'local_party':
        return _partiesKeys;
      case 'local_deliver_points':
        return _deliveryPointsKeys;
      case 'local_goods_agency':
        return _agenciesKeys;
      case 'local_store_data':
        return _storeDataKeys;
      default:
        return const ['data', 'result', 'rows', 'records'];
    }
  }

  static List? _findListByPreferredKeys(dynamic node, List<String> keys) {
    if (node is List) return node;
    if (node is Map) {
      final map = node as Map;
      final keysLower = keys.map((k) => k.toLowerCase()).toSet();

      // First pass: direct preferred keys on this level.
      for (final key in keys) {
        final value = map[key];
        if (value is List) return value;
      }

      // Second pass: case-insensitive key match (e.g. API returns "Items" or "Packages").
      for (final entry in map.entries) {
        final key = entry.key?.toString() ?? '';
        final value = entry.value;
        if (value is List && keysLower.contains(key.toLowerCase()))
          return value;
      }

      // Third pass: any key whose value is a non-empty list (fallback).
      for (final value in map.values) {
        if (value is List && value.isNotEmpty) return value;
      }

      // Fourth pass: recurse into nested map/list values.
      for (final value in map.values) {
        final nested = _findListByPreferredKeys(value, keys);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  static List<Map<String, dynamic>> _toMapList(List raw) {
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// If map has numeric-like keys (0,1,2...), return list of map values; else null.
  static List<Map<String, dynamic>>? _listFromMapWithNumericKeys(Map map) {
    final keys = map.keys.toList();
    if (keys.isEmpty) return null;
    final indices = <int>[];
    for (final k in keys) {
      final i = int.tryParse(k.toString());
      if (i == null || i < 0) return null;
      indices.add(i);
    }
    indices.sort();
    if (indices.first != 0 || indices.last != indices.length - 1) return null;
    final list = <Map<String, dynamic>>[];
    for (var i = 0; i < indices.length; i++) {
      final v = map[indices[i].toString()];
      if (v is Map) {
        list.add(Map<String, dynamic>.from(v));
      } else {
        return null;
      }
    }
    return list;
  }

  static Future<int> _countFromKey(String cacheKey) async {
    try {
      final payload = await LocalDbService.instance.getLocalData(cacheKey);
      if (payload == null || payload.isEmpty) return 0;
      final d = jsonDecode(payload);
      final preferredKeys = _preferredKeysForCache(cacheKey);
      final list = _findListByPreferredKeys(d, preferredKeys);
      if (list != null) return list.length;
      if (d is List) return d.length;
      if (d is Map) return 1;
      return 0;
    } catch (_) {
      return 0;
    }
  }

  Future<int> getPackagesCount() => _countFromKey('local_packages');
  Future<int> getItemsCount() => _countFromKey('local_items');
  Future<int> getPackageDetails1Count() =>
      _countFromKey('local_package_details_1');
  Future<int> getPackageDetails2Count() =>
      _countFromKey('local_package_details_2');
  Future<int> getDeliveryPointsCount() => _countFromKey('local_deliver_points');
  Future<int> getPartiesCount() => _countFromKey('local_party');
  Future<int> getGoodsAgenciesCount() => _countFromKey('local_goods_agency');
  Future<int> getStoreDataCount() => _countFromKey('local_store_data');

  /// Returns parsed list from cache (for Order Add screen). Empty list on missing/error.
  /// Handles both raw arrays and wrapped responses (e.g. { "data": [...] }).
  static Future<List<Map<String, dynamic>>> _listFromKey(
    String cacheKey,
  ) async {
    try {
      final payload = await LocalDbService.instance.getLocalData(cacheKey);
      if (payload == null || payload.isEmpty) {
        debugPrint('[OrderDB] $cacheKey: no payload');
        return [];
      }
      final d = jsonDecode(payload);
      final preferredKeys = _preferredKeysForCache(cacheKey);
      final list = _findListByPreferredKeys(d, preferredKeys);
      if (list != null) {
        final out = _toMapList(list);
        debugPrint(
          '[OrderDB] $cacheKey: found list length=${list.length}, maps=${out.length}',
        );
        return out;
      }

      if (d is List) {
        final out = _toMapList(d);
        debugPrint(
          '[OrderDB] $cacheKey: root is List length=${d.length}, maps=${out.length}',
        );
        return out;
      }
      if (d is Map) {
        final map = d as Map<String, dynamic>;
        // PHP sometimes returns array as object: {"0": {...}, "1": {...}}
        final listFromNumericKeys = _listFromMapWithNumericKeys(map);
        if (listFromNumericKeys != null && listFromNumericKeys.isNotEmpty) {
          debugPrint(
            '[OrderDB] $cacheKey: used numeric-keys map, length=${listFromNumericKeys.length}',
          );
          return listFromNumericKeys;
        }
        debugPrint(
          '[OrderDB] $cacheKey: list not found, root keys: ${map.keys.join(', ')}',
        );
        return [Map<String, dynamic>.from(map)];
      }
      return [];
    } catch (e, st) {
      debugPrint('[OrderDB] $cacheKey: error $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getParties() =>
      _listFromKey('local_party').then(
        (rows) => rows
            .map(OrderDataNormalizer.normalizeParty)
            .where(
              (m) => (m['display_name']?.toString().trim().isNotEmpty ?? false),
            )
            .toList(),
      );
  Future<List<Map<String, dynamic>>> getItems() =>
      _listFromKey('local_items').then(
        (rows) => rows
            .map(OrderDataNormalizer.normalizeItem)
            .where((m) => (m['name']?.toString().trim().isNotEmpty ?? false))
            .toList(),
      );
  Future<List<Map<String, dynamic>>> getPackages() =>
      _listFromKey('local_packages').then(
        (rows) => rows
            .map(OrderDataNormalizer.normalizePackage)
            .where((m) => (m['name']?.toString().trim().isNotEmpty ?? false))
            .toList(),
      );
  Future<List<Map<String, dynamic>>> getDeliveryPoints() =>
      _listFromKey('local_deliver_points').then(
        (rows) => rows
            .map(OrderDataNormalizer.normalizeDeliveryPoint)
            .where(
              (m) => (m['display_name']?.toString().trim().isNotEmpty ?? false),
            )
            .toList(),
      );
  Future<List<Map<String, dynamic>>> getGoodsAgencies() =>
      _listFromKey('local_goods_agency').then(
        (rows) => rows
            .map(OrderDataNormalizer.normalizeAgency)
            .where(
              (m) => (m['display_name']?.toString().trim().isNotEmpty ?? false),
            )
            .toList(),
      );
  Future<List<Map<String, dynamic>>> getStoreData() =>
      _listFromKey('local_store_data');

  /// Get PackageDetails1 list from cache
  Future<List<PackageDetails1>> getPackageDetails1() async {
    final rows = await _listFromKey('local_package_details_1');
    return rows.map((row) => PackageDetails1.fromJson(row)).toList();
  }

  /// Get PackageDetails2 list from cache
  Future<List<PackageDetails2>> getPackageDetails2() async {
    final rows = await _listFromKey('local_package_details_2');
    return rows.map((row) => PackageDetails2.fromJson(row)).toList();
  }

  /// Package details total (sum of 1 + 2).
  Future<int> getPackageDetailsCount() async {
    final a = await getPackageDetails1Count();
    final b = await getPackageDetails2Count();
    return a + b;
  }

  /// All counts for Local Database Summary. Keys match UI labels.
  Future<Map<String, int>> getAllLocalStats() async {
    final packages = await getPackagesCount();
    final items = await getItemsCount();
    final packageDetails = await getPackageDetailsCount();
    final deliveryPoints = await getDeliveryPointsCount();
    final parties = await getPartiesCount();
    final goodsAgencies = await getGoodsAgenciesCount();
    final storeData = await getStoreDataCount();
    return {
      'packages': packages,
      'items': items,
      'package_details': packageDetails,
      'delivery_points': deliveryPoints,
      'parties': parties,
      'goods_agencies': goodsAgencies,
      'visits': 0,
      'store_data': storeData,
    };
  }
}
