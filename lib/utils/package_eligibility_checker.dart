/// Package eligibility checker matching Android logic
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
    // Extract eligibility fields
    final partiesAllowed = package['parties_allowed']?.toString() ?? '';
    final usersActive = package['users_active']?.toString() ?? '';
    final allowedUsers = package['allowed_users']?.toString() ?? '';

    // If no party restriction, check user eligibility only
    if (partiesAllowed.isEmpty) {
      return _checkUserEligibility(
        usersActive: usersActive,
        allowedUsers: allowedUsers,
        userId: userId,
      );
    }

    // Check if party is in allowed list
    final partyList = partiesAllowed.split(',').map((e) => e.trim()).toList();
    final partyAllowed = partyList.contains(partyId);

    if (!partyAllowed) {
      return false; // Party not in allowed list
    }

    // Party is allowed, now check user
    return _checkUserEligibility(
      usersActive: usersActive,
      allowedUsers: allowedUsers,
      userId: userId,
    );
  }

  /// Check user eligibility based on users_active and allowed_users
  static bool _checkUserEligibility({
    required String usersActive,
    required String allowedUsers,
    required String userId,
  }) {
    // If users_active is "1", check allowed_users list
    if (usersActive == '1') {
      if (allowedUsers.isEmpty) {
        return false; // Active user restriction but no users specified
      }
      final userList = allowedUsers.split(',').map((e) => e.trim()).toList();
      return userList.contains(userId);
    }

    // No user restriction
    return true;
  }

  /// Get reason why package is not allowed (for user feedback)
  static String getDisallowedReason({
    required Map<String, dynamic> package,
    required String partyId,
    required String userId,
  }) {
    final partiesAllowed = package['parties_allowed']?.toString() ?? '';
    final usersActive = package['users_active']?.toString() ?? '';
    final allowedUsers = package['allowed_users']?.toString() ?? '';

    if (partiesAllowed.isNotEmpty) {
      final partyList = partiesAllowed.split(',').map((e) => e.trim()).toList();
      if (!partyList.contains(partyId)) {
        return 'This package is not available for the selected party.';
      }
    }

    if (usersActive == '1') {
      if (allowedUsers.isEmpty) {
        return 'This package requires user authorization.';
      }
      final userList = allowedUsers.split(',').map((e) => e.trim()).toList();
      if (!userList.contains(userId)) {
        return 'You are not authorized to use this package.';
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
