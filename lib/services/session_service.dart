import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

class SessionService {
  static const String _userDataKey = 'user_data';
  static const String _savedUsernameKey = 'saved_username';
  static const String _savedPasswordKey = 'saved_password';
  static const String _staticIpKey = 'static_ip';
  static const String _userRecIdKey = 'user_rec_id';
  static const String _userAccountKey = 'user_account';
  static const String _dataUpdateDateKey = 'data_update_date';
  static const String _isActivityRunningKey = 'is_activity_running';
  static const String _previousBiltyNoKey = 'previous_bilty_no';
  static const String _previousBiltyTimeKey = 'previous_bilty_time';
  static const String _dataUpdateIdKey = 'data_update_id';
  static const String _isAppUpdateImportantKey = 'is_app_update_important';

  static const String domainName = 'https://www.hisaab.org';
  static const String domainName2 = 'https://www.hisaab.org';

  // Save complete user data
  static Future<void> saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userDataKey, jsonEncode(user.toJson()));
  }

  // Get complete user data
  static Future<User?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userDataKey);
    if (userJson == null) return null;

    return User.fromJson(jsonDecode(userJson));
  }

  // Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userDataKey) != null;
  }

  /// Save credentials in SharedPreferences (like Android LoginActivity insertUserCredentials).
  /// Cleared on logout so user can re-login when needed.
  static Future<void> saveCredentials({
    required String username,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedUsernameKey, username);
    await prefs.setString(_savedPasswordKey, password);
  }

  static Future<String?> getSavedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_savedUsernameKey);
  }

  static Future<String?> getSavedPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_savedPasswordKey);
  }

  /// Direct login (bypass API): saves user id 1013 in session for development.
  /// TODO: Remove when API login is fixed and use ApiService.login() in LoginScreen.
  static Future<void> performDirectLogin({String? username}) async {
    const userId = 1013;
    const employeeId = '1013';
    final user = User(
      id: userId,
      username: username ?? 'user_1013',
      email: '',
      role: '',
      usermlevel: '',
      businessunit: '',
      dept: '',
      employeeid: employeeId,
      storeid: '',
      passdate: '',
      roles: '',
      emLocationId: '',
      emLocationName: '',
      allowAllUsers: '',
      allowedStoreInvoices: '',
      allowedStoreOrders: '',
      allowAllInvoices: '',
      orderFinances: '',
      allowSalaryFinances: '',
      allowedOffices: '',
      ordersPage: '',
      account: '1',
      pinverification: '0',
    );
    await saveUser(user);
    await setUserRecId('1');
    await setUserAccount('1');
  }

  // Legacy methods for compatibility
  static Future<void> saveUserSession({
    required int userId,
    required int employeeId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_id', userId);
    await prefs.setInt('employee_id', employeeId);
  }

  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final user = await getUser();
    return user?.id ?? prefs.getInt('user_id');
  }

  static Future<int?> getEmployeeId() async {
    final prefs = await SharedPreferences.getInstance();
    final user = await getUser();
    if (user?.employeeid != null && user!.employeeid.isNotEmpty) {
      return int.tryParse(user.employeeid);
    }
    return prefs.getInt('employee_id');
  }

  // Static IP methods
  static Future<void> setStaticIP(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_staticIpKey, ip);
  }

  static Future<String> getStaticIP() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_staticIpKey) ?? domainName2;
  }

  // User Rec ID methods
  static Future<void> setUserRecId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userRecIdKey, id);
  }

  static Future<String> getUserRecId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userRecIdKey) ?? '1';
  }

  // User Account methods
  static Future<void> setUserAccount(String account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userAccountKey, account);
  }

  static Future<String?> getUserAccount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userAccountKey);
  }

  // Data Update Date methods
  static Future<void> setDataUpdateDate(String date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dataUpdateDateKey, date);
  }

  static Future<String> getDataUpdateDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_dataUpdateDateKey) ?? '00-00-0000';
  }

  // Activity Running methods
  static Future<String> getIsActivityRunning() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_isActivityRunningKey) ?? domainName2;
  }

  static Future<void> setIsActivityRunning(String isRunning) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_isActivityRunningKey, isRunning);
  }

  // Bilty methods
  static Future<String> getPreviousBiltyNo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_previousBiltyNoKey) ?? '0';
  }

  static Future<void> setPreviousBiltyNo(String biltyNo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_previousBiltyNoKey, biltyNo);
  }

  static Future<String> getPreviousBiltyTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_previousBiltyTimeKey) ?? '0';
  }

  static Future<void> setPreviousBiltyTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_previousBiltyTimeKey, time);
  }

  // Data Update ID methods
  static Future<String> getDataUpdateId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_dataUpdateIdKey) ?? '0';
  }

  static Future<void> setDataUpdateId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dataUpdateIdKey, id);
  }

  // App Update Important methods
  static Future<String> getIsAppUpdateImportant() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_isAppUpdateImportantKey) ?? '0';
  }

  static Future<void> setIsAppUpdateImportant(String isImportant) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_isAppUpdateImportantKey, isImportant);
  }

  // Generic String methods
  static Future<void> setString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  static Future<String> getString(String key, String defaultValue) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key) ?? defaultValue;
  }

  // Generic Integer methods
  static Future<void> setInteger(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  static Future<int> getInteger(String key, int defaultValue) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key) ?? defaultValue;
  }

  // Clear session (logout). Keeps saved credentials so user can re-login without re-entering.
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userDataKey);
    await prefs.remove(_userRecIdKey);
    await prefs.remove(_userAccountKey);
    await prefs.remove(_staticIpKey);
    await prefs.remove(_dataUpdateDateKey);
    await prefs.remove(_isActivityRunningKey);
    await prefs.remove(_previousBiltyNoKey);
    await prefs.remove(_previousBiltyTimeKey);
    await prefs.remove(_dataUpdateIdKey);
    await prefs.remove(_isAppUpdateImportantKey);
    await prefs.remove('user_id');
    await prefs.remove('employee_id');
    // Keep _savedUsernameKey, _savedPasswordKey for next login pre-fill
  }
}
