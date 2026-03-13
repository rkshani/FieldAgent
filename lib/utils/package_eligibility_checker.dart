import 'package:flutter/foundation.dart';

/// Package eligibility checker matching legacy Android logic.
/// Android methods: pkgAllowed, pkgNotAllowed
class PackageEligibilityChecker {
  /// Check if package is allowed for the user/party combination
  /// Android logic from pkgAllowed method:
  /// - If parties_allowed is empty → allow all
  /// - If parties_allowed contains partyId → allow
  /// - Check users_active and allowed_users for userId
  static bool isPackageAllowed({
    required Map<String, dynamic> package,
    required String partyId,
    required String userId,
  }) {
    final partiesAllowed = package['parties_allowed']?.toString() ?? '';
    final usersActive = package['users_active']?.toString() ?? '0';
    final allowedUsers = package['allowed_users']?.toString() ?? '';

    // Legacy party behavior:
    // - empty parties_allowed => party is allowed
    // - non-empty => selected party must exist in the list
    if (partiesAllowed.trim().isNotEmpty) {
      final partyList = partiesAllowed
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      if (!partyList.contains(partyId.trim())) {
        debugPrint(
          '[PackageEligibility] blocked by party package=${package['packageid'] ?? package['id']} party=$partyId',
        );
        return false;
      }
    }

    final allowed = _checkUserEligibility(
      usersActive: usersActive,
      allowedUsers: allowedUsers,
      userId: userId,
    );
    debugPrint(
      '[PackageEligibility] package=${package['packageid'] ?? package['id']} party=$partyId user=$userId users_active=$usersActive allowed_users="$allowedUsers" allowed=$allowed',
    );
    return allowed;
  }

  /// Check user eligibility based on users_active and allowed_users
  static bool _checkUserEligibility({
    required String usersActive,
    required String allowedUsers,
    required String userId,
  }) {
    final normalizedUserId = userId.trim();
    final userList = allowedUsers
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    // Legacy Android parity (intentionally odd):
    // users_active == "0": allowed_users is block-list
    if (usersActive.trim() == '0') {
      if (userList.isEmpty) return true;
      if (userList.contains(normalizedUserId)) return false;
      return true;
    }

    // users_active == "1": allowed_users is whitelist
    if (usersActive.trim() == '1') {
      if (userList.isEmpty) return false;
      return userList.contains(normalizedUserId);
    }

    // Defensive fallback for malformed users_active values.
    return true;
  }

  /// Get reason why package is not allowed (for user feedback)
  static String getDisallowedReason({
    required Map<String, dynamic> package,
    required String partyId,
    required String userId,
  }) {
    final partiesAllowed = package['parties_allowed']?.toString() ?? '';
    final usersActive = package['users_active']?.toString() ?? '0';
    final allowedUsers = package['allowed_users']?.toString() ?? '';

    if (partiesAllowed.isNotEmpty) {
      final partyList = partiesAllowed.split(',').map((e) => e.trim()).toList();
      if (!partyList.contains(partyId)) {
        return 'Package not allowed to you, Please select another package';
      }
    }

    final userList = allowedUsers
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final normalizedUserId = userId.trim();

    if (usersActive.trim() == '0') {
      if (userList.isNotEmpty && userList.contains(normalizedUserId)) {
        return 'Package not allowed to you, Please select another package';
      }
    }
    if (usersActive.trim() == '1') {
      if (userList.isEmpty || !userList.contains(normalizedUserId)) {
        return 'Package not allowed to you, Please select another package';
      }
    }

    return '';
  }

  /// Filter packages list to show only allowed packages
  static List<Map<String, dynamic>> filterAllowedPackages({
    required List<Map<String, dynamic>> packages,
    required String partyId,
    required String userId,
  }) {
    return packages.where((pkg) {
      return isPackageAllowed(package: pkg, partyId: partyId, userId: userId);
    }).toList();
  }

  /// Check minimum order amount requirement
  /// Android: minorderamount field in package
  static bool meetsMinimumAmount({
    required Map<String, dynamic> package,
    required double orderTotal,
  }) {
    final minAmountStr = package['minorderamount']?.toString() ?? '0';
    final minAmount = double.tryParse(minAmountStr) ?? 0;
    return orderTotal >= minAmount;
  }

  /// Get minimum order amount
  static double getMinimumAmount(Map<String, dynamic> package) {
    final minAmountStr = package['minorderamount']?.toString() ?? '0';
    return double.tryParse(minAmountStr) ?? 0;
  }
}
