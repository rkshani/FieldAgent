import 'package:flutter/foundation.dart';

import '../models/invoice_item.dart';
import '../models/package_details.dart';

class PackagePricingResult {
  final bool allowed;
  final String? reason;
  final double basePrice;
  final double finalPrice;
  final double discountPercent;
  final bool usedPackageDetails1;
  final bool usedPackageDetails2;
  final bool defaultPriceMismatch;
  final bool groupwiseApplied;
  final String? groupwiseBookIds;

  const PackagePricingResult({
    required this.allowed,
    this.reason,
    required this.basePrice,
    required this.finalPrice,
    required this.discountPercent,
    required this.usedPackageDetails1,
    required this.usedPackageDetails2,
    required this.defaultPriceMismatch,
    required this.groupwiseApplied,
    this.groupwiseBookIds,
  });

  factory PackagePricingResult.notAllowed(String reason) {
    return PackagePricingResult(
      allowed: false,
      reason: reason,
      basePrice: 0,
      finalPrice: 0,
      discountPercent: 0,
      usedPackageDetails1: false,
      usedPackageDetails2: false,
      defaultPriceMismatch: false,
      groupwiseApplied: false,
    );
  }
}

class OrderPackagePricingService {
  static int? toIntSafe(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  static double? toDoubleSafe(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  static DateTime? parseDateSafe(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final raw = value.trim();
    final canonical = raw.replaceAll('/', '-');
    final parts = canonical.split('-');
    if (parts.length == 3) {
      // yyyy-MM-dd
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y != null && m != null && d != null) {
        return DateTime(y, m, d);
      }
      // dd-MM-yyyy
      final d2 = int.tryParse(parts[0]);
      final m2 = int.tryParse(parts[1]);
      final y2 = int.tryParse(parts[2]);
      if (y2 != null && m2 != null && d2 != null) {
        return DateTime(y2, m2, d2);
      }
    }
    return DateTime.tryParse(raw);
  }

  static Set<String> splitCsvSafe(String? value) {
    if (value == null || value.trim().isEmpty) return const <String>{};
    return value
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  static bool comparePriceSafe(double a, double b) {
    return (a - b).abs() < 0.0001;
  }

  static bool isPaymentDealRequired(Map<String, dynamic>? package) {
    final scheme = package?['scheme']?.toString().trim() ?? '';
    return scheme == '2';
  }

  static String packageIdFromMap(Map<String, dynamic>? package) {
    return package?['packageid']?.toString().trim() ??
        package?['package_id']?.toString().trim() ??
        package?['id']?.toString().trim() ??
        '';
  }

  static String itemIdFromMap(Map<String, dynamic>? item) {
    return item?['bookid']?.toString().trim() ??
        item?['item_id']?.toString().trim() ??
        item?['id']?.toString().trim() ??
        '';
  }

  static String groupIdFromMap(Map<String, dynamic>? item) {
    return item?['group_id']?.toString().trim() ??
        item?['groupid']?.toString().trim() ??
        '';
  }

  static String packageCountryId(Map<String, dynamic>? package) {
    return package?['country_id']?.toString().trim() ??
        package?['countryid']?.toString().trim() ??
        package?['country']?.toString().trim() ??
        '';
  }

  static Map<String, double> parseAllPricesMap(String? allPricesRaw) {
    final result = <String, double>{};
    final raw = allPricesRaw?.trim() ?? '';
    if (raw.isEmpty) return result;

    for (final entry in raw.split('|')) {
      final token = entry.trim();
      if (token.isEmpty) continue;
      final pair = token.split(':');
      if (pair.length < 2) continue;
      final key = pair.first.trim();
      final value = toDoubleSafe(pair.sublist(1).join(':'));
      if (key.isNotEmpty && value != null) {
        result[key] = value;
      }
    }

    if (result.isNotEmpty) {
      return result;
    }

    final fallbackPairs = raw.split(RegExp(r'[;,]'));
    for (final token in fallbackPairs) {
      final part = token.trim();
      if (part.isEmpty) continue;
      final pair = part.split(RegExp(r'[:=-]'));
      if (pair.length < 2) continue;
      final key = pair.first.trim();
      final value = toDoubleSafe(pair.sublist(1).join(''));
      if (key.isNotEmpty && value != null) {
        result[key] = value;
      }
    }

    return result;
  }

  static double? resolveBasePriceForPackageCountry({
    required Map<String, dynamic>? package,
    required Map<String, dynamic>? item,
  }) {
    if (package == null || item == null) return null;
    final countryId = packageCountryId(package);
    if (countryId.isEmpty) return null;

    final allPricesMap = parseAllPricesMap(item['allprices']?.toString());
    if (allPricesMap.isEmpty) return null;

    if (allPricesMap.containsKey(countryId)) {
      return allPricesMap[countryId];
    }

    for (final entry in allPricesMap.entries) {
      if (entry.key.trim() == countryId) {
        return entry.value;
      }
    }

    return null;
  }

  static int calculateGroupwiseQty({
    required Set<String> groupBookIds,
    required Map<String, int> qtyByBookId,
  }) {
    var total = 0;
    for (final id in groupBookIds) {
      total += qtyByBookId[id] ?? 0;
    }
    return total;
  }

  static double calculateGroupwiseAmount({
    required Set<String> groupBookIds,
    required Map<String, InvoiceItem> cartByBookId,
    required String currentBookId,
    required int currentQty,
    required double currentUnitPrice,
    required double currentDiscountPercent,
  }) {
    var total = 0.0;
    for (final id in groupBookIds) {
      if (id == currentBookId) {
        final subtotal = currentQty * currentUnitPrice;
        final discounted = subtotal - (subtotal * currentDiscountPercent / 100);
        total += discounted;
        continue;
      }

      final cartItem = cartByBookId[id];
      if (cartItem == null) continue;
      final subtotal = cartItem.price * cartItem.quantity;
      final discounted = subtotal - (subtotal * cartItem.discountPercent / 100);
      total += discounted;
    }
    return total;
  }

  static PackagePricingResult resolveItemPricing({
    required Map<String, dynamic>? package,
    required Map<String, dynamic>? item,
    required int quantity,
    required List<PackageDetails1> packageDetails1,
    required List<PackageDetails2> packageDetails2,
    required List<InvoiceItem> cartItems,
    DateTime? currentDate,
  }) {
    final packageId = packageIdFromMap(package);
    final itemId = itemIdFromMap(item);
    final groupId = groupIdFromMap(item);

    if (package == null || packageId.isEmpty) {
      return PackagePricingResult.notAllowed('Please select package first');
    }
    if (item == null || itemId.isEmpty) {
      return PackagePricingResult.notAllowed('Item Not Allowed');
    }

    final basePrice = resolveBasePriceForPackageCountry(
      package: package,
      item: item,
    );
    if (basePrice == null || basePrice <= 0) {
      debugPrint(
        '[PackagePricing] base price not found package=$packageId item=$itemId',
      );
      return PackagePricingResult.notAllowed('Item Not Allowed');
    }

    final matches1 = packageDetails1.where((row) {
      return (row.packageId ?? '').trim() == packageId &&
          (row.itemId ?? '').trim() == itemId &&
          (row.groupId ?? '').trim() == groupId;
    }).toList();

    final match2 = packageDetails2.cast<PackageDetails2?>().firstWhere((row) {
      if (row == null) return false;
      return (row.packageId ?? '').trim() == packageId &&
          (row.groupId ?? '').trim() == groupId;
    }, orElse: () => null);

    debugPrint(
      '[PackagePricing] package=$packageId item=$itemId group=$groupId pd1=${matches1.length} pd2=${match2 != null}',
    );

    for (final row in matches1) {
      final defaultPrice = toDoubleSafe(row.defaultPrice);
      if (defaultPrice != null && !comparePriceSafe(defaultPrice, basePrice)) {
        debugPrint(
          '[PackagePricing] default price mismatch item=$itemId base=$basePrice default=$defaultPrice',
        );
        return PackagePricingResult(
          allowed: false,
          reason: 'Item Not Allowed',
          basePrice: basePrice,
          finalPrice: 0,
          discountPercent: 0,
          usedPackageDetails1: true,
          usedPackageDetails2: false,
          defaultPriceMismatch: true,
          groupwiseApplied: false,
        );
      }
    }

    var resolvedPrice = basePrice;
    var resolvedDiscount = 0.0;
    var usedDetails1 = false;
    var usedDetails2 = false;
    var groupwiseApplied = false;
    String? groupwiseBookIds;

    final qtyByBookId = <String, int>{
      for (final cart in cartItems) cart.id: cart.quantity,
      itemId: quantity,
    };
    final cartByBookId = <String, InvoiceItem>{
      for (final c in cartItems) c.id: c,
    };

    bool applyFromRow(PackageDetails1 row) {
      var matched = false;
      final overridePrice = toDoubleSafe(row.price);
      final overridePct = toDoubleSafe(row.percentage);
      if (overridePct != null && overridePct > 0) {
        resolvedDiscount = overridePct;
        matched = true;
      }
      if (overridePrice != null && overridePrice > 0) {
        resolvedPrice = overridePrice;
        matched = true;
      }
      return matched;
    }

    bool inOpenOrBoundRange({
      required double value,
      required double min,
      required double max,
    }) {
      if (max > 0) {
        return value >= min && value <= max;
      }
      return value >= min;
    }

    for (final row in matches1) {
      final discountType = (row.discountType ?? '').trim().toLowerCase();
      final groupwiseIds = splitCsvSafe(row.groupwiseBookIds);
      final isGroupwise = groupwiseIds.isNotEmpty;

      if (discountType == 'quantity') {
        if (!isGroupwise) {
          final minQty = (toIntSafe(row.minQty) ?? 0).toDouble();
          final maxQty = (toIntSafe(row.maxQty) ?? 0).toDouble();
          if (inOpenOrBoundRange(
            value: quantity.toDouble(),
            min: minQty,
            max: maxQty,
          )) {
            final didApply = applyFromRow(row);
            if (didApply) {
              usedDetails1 = true;
              debugPrint('[PackagePricing] quantity rule hit item=$itemId');
            }
          }
          continue;
        }

        final minQty = (toIntSafe(row.groupwiseMinQty) ?? 0).toDouble();
        final maxQty = (toIntSafe(row.groupwiseMaxQty) ?? 0).toDouble();
        final totalQty = calculateGroupwiseQty(
          groupBookIds: groupwiseIds,
          qtyByBookId: qtyByBookId,
        ).toDouble();

        if (inOpenOrBoundRange(value: totalQty, min: minQty, max: maxQty)) {
          final didApply = applyFromRow(row);
          if (didApply) {
            usedDetails1 = true;
            groupwiseApplied = true;
            groupwiseBookIds = row.groupwiseBookIds;
            debugPrint(
              '[PackagePricing] groupwise quantity rule hit item=$itemId totalQty=$totalQty',
            );
          }
        }
        continue;
      }

      if (discountType == 'amount') {
        if (!isGroupwise) {
          final lineTotal = quantity * resolvedPrice;
          final discountedLine =
              lineTotal - (lineTotal * resolvedDiscount / 100);
          final minAmt = toDoubleSafe(row.minAmt) ?? 0;
          final maxAmt = toDoubleSafe(row.maxAmt) ?? 0;

          if (inOpenOrBoundRange(
            value: discountedLine,
            min: minAmt,
            max: maxAmt,
          )) {
            final didApply = applyFromRow(row);
            if (didApply) {
              usedDetails1 = true;
              debugPrint('[PackagePricing] amount rule hit item=$itemId');
            }
          }
          continue;
        }

        final groupTotal = calculateGroupwiseAmount(
          groupBookIds: groupwiseIds,
          cartByBookId: cartByBookId,
          currentBookId: itemId,
          currentQty: quantity,
          currentUnitPrice: resolvedPrice,
          currentDiscountPercent: resolvedDiscount,
        );

        final minAmt =
            toDoubleSafe(row.groupwiseMinAmt) ??
            toDoubleSafe(row.minAmt) ??
            (toIntSafe(row.groupwiseMinQty)?.toDouble() ?? 0);
        final maxAmt =
            toDoubleSafe(row.groupwiseMaxAmt) ?? toDoubleSafe(row.maxAmt) ?? 0;

        if (inOpenOrBoundRange(value: groupTotal, min: minAmt, max: maxAmt)) {
          final didApply = applyFromRow(row);
          if (didApply) {
            usedDetails1 = true;
            groupwiseApplied = true;
            groupwiseBookIds = row.groupwiseBookIds;
            debugPrint(
              '[PackagePricing] groupwise amount rule hit item=$itemId total=$groupTotal',
            );
          }
        }
      }
    }

    final now = currentDate ?? DateTime.now();
    for (final row in matches1) {
      final start = parseDateSafe(row.startDate);
      final end = parseDateSafe(row.endDate);
      if (start == null || end == null) continue;

      if (now.isAfter(start) && now.isBefore(end)) {
        final didApply = applyFromRow(row);
        if (didApply) {
          usedDetails1 = true;
          debugPrint('[PackagePricing] date override hit item=$itemId');
        }
      }
    }

    if (!usedDetails1 && match2 != null) {
      final fallbackPct = toDoubleSafe(match2.percentage);
      if (fallbackPct != null && fallbackPct > 0) {
        resolvedDiscount = fallbackPct;
        usedDetails2 = true;
        debugPrint(
          '[PackagePricing] packageDetails2 fallback used item=$itemId',
        );
      }
    }

    debugPrint(
      '[PackagePricing] final item=$itemId price=$resolvedPrice discount=$resolvedDiscount',
    );

    return PackagePricingResult(
      allowed: true,
      basePrice: basePrice,
      finalPrice: resolvedPrice,
      discountPercent: resolvedDiscount,
      usedPackageDetails1: usedDetails1,
      usedPackageDetails2: usedDetails2,
      defaultPriceMismatch: false,
      groupwiseApplied: groupwiseApplied,
      groupwiseBookIds: groupwiseBookIds,
    );
  }

  static Map<String, PackagePricingResult> recalculateGroupwiseCartItems({
    required Map<String, dynamic>? package,
    required Map<String, Map<String, dynamic>> itemById,
    required List<InvoiceItem> cartItems,
    required List<PackageDetails1> packageDetails1,
    required List<PackageDetails2> packageDetails2,
  }) {
    final results = <String, PackagePricingResult>{};
    for (final cart in cartItems) {
      final item = itemById[cart.id];
      if (item == null) continue;
      results[cart.id] = resolveItemPricing(
        package: package,
        item: item,
        quantity: cart.quantity,
        packageDetails1: packageDetails1,
        packageDetails2: packageDetails2,
        cartItems: cartItems,
      );
    }
    return results;
  }
}
