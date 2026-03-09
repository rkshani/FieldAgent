import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';

class SessionService {
  // Keys
  static const String _userDataKey = 'user_data';
  static const String _savedUsernameKey = 'saved_username';
  static const String _savedPasswordKey = 'saved_password';

  static const String _staticIpKey = 'static_ip';
  static const String _userRecIdKey = 'user_rec_id';
  static const String _userAccountKey = 'user_account';

  static const String _dataUpdateDateKey = 'data_update_date';
  static const String _dataUpdateIdKey = 'data_update_id';

  static const String _previousBiltyNoKey = 'previous_bilty_no';
  static const String _previousBiltyTimeKey = 'previous_bilty_time';

  static const String _isActivityRunningKey = 'is_activity_running';
  static const String _isAppUpdateImportantKey = 'is_app_update_important';

  static const String _legacyUserIdKey = 'user_id';
  static const String _legacyEmployeeIdKey = 'employee_id';

  static const String domainName = 'https://www.hisaab.org';
  static const String domainName2 = 'https://www.hisaab.org';

  static const String _defaultStaticIp = domainName2;
  static const String _defaultUserRecId = '1';
  static const String _defaultUserAccount = '1';
  static const String _defaultDataUpdateDate = '00-00-0000';
  static const String _defaultDataUpdateId = '0';
  static const String _defaultPreviousBiltyNo = '0';
  static const String _defaultPreviousBiltyTime = '0';
  static const String _defaultIsActivityRunning = '0';
  static const String _defaultIsAppUpdateImportant = '0';

  // User Session
  static Future<void> saveUser(User user) async {
    final prefs = await _prefs;
    await prefs.setString(_userDataKey, jsonEncode(user.toJson()));

    // Keep old keys in sync for legacy callers while user model remains source of truth.
    await prefs.setInt(_legacyUserIdKey, user.id);
    final employeeId = int.tryParse(user.employeeid);
    if (employeeId != null) {
      await prefs.setInt(_legacyEmployeeIdKey, employeeId);
    }
  }

  static Future<User?> getUser() async {
    final prefs = await _prefs;
    final userJson = prefs.getString(_userDataKey);
    if (userJson == null) return null;

    try {
      return User.fromJson(jsonDecode(userJson));
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await _prefs;
    return prefs.getString(_userDataKey) != null;
  }

  // Credentials
  static Future<void> saveCredentials({
    required String username,
    required String password,
  }) async {
    final prefs = await _prefs;
    await prefs.setString(_savedUsernameKey, username.trim());
    await prefs.setString(_savedPasswordKey, password);
  }

  static Future<String?> getSavedUsername() async {
    final prefs = await _prefs;
    return prefs.getString(_savedUsernameKey);
  }

  static Future<String?> getSavedPassword() async {
    final prefs = await _prefs;
    return prefs.getString(_savedPasswordKey);
  }

  static Future<bool> hasStoredCredentialsFor(String username) async {
    final stored = await getSavedUsername();
    return stored != null && stored == username.trim();
  }

  // Static IP
  static Future<void> setStaticIP(String ip) async {
    final prefs = await _prefs;
    final sanitized = _normalizedOrDefault(ip, _defaultStaticIp);
    await prefs.setString(_staticIpKey, sanitized);
  }

  static Future<String> getStaticIP() async {
    final prefs = await _prefs;
    return _normalizedOrDefault(prefs.getString(_staticIpKey), _defaultStaticIp);
  }

  // User Info
  static Future<void> setUserRecId(String id) async {
    final prefs = await _prefs;
    await prefs.setString(_userRecIdKey, _normalizedOrDefault(id, _defaultUserRecId));
  }

  static Future<String> getUserRecId() async {
    final prefs = await _prefs;
    return _normalizedOrDefault(prefs.getString(_userRecIdKey), _defaultUserRecId);
  }

  static Future<void> setUserAccount(String account) async {
    final prefs = await _prefs;
    await prefs.setString(
      _userAccountKey,
      _normalizedOrDefault(account, _defaultUserAccount),
    );
  }

  static Future<String?> getUserAccount() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_userAccountKey);
    if (raw == null || raw.trim().isEmpty) {
      return _defaultUserAccount;
    }
    return raw.trim();
  }

  // Data Update
  static Future<void> setDataUpdateDate(String date) async {
    final prefs = await _prefs;
    await prefs.setString(
      _dataUpdateDateKey,
      _normalizedOrDefault(date, _defaultDataUpdateDate),
    );
  }

  static Future<String> getDataUpdateDate() async {
    final prefs = await _prefs;
    return _normalizedOrDefault(
      prefs.getString(_dataUpdateDateKey),
      _defaultDataUpdateDate,
    );
  }

  static Future<void> setDataUpdateId(String id) async {
    final prefs = await _prefs;
    await prefs.setString(_dataUpdateIdKey, _normalizedOrDefault(id, _defaultDataUpdateId));
  }

  static Future<String> getDataUpdateId() async {
    final prefs = await _prefs;
    return _normalizedOrDefault(prefs.getString(_dataUpdateIdKey), _defaultDataUpdateId);
  }

  static Future<void> setDataUpdateInfo({
    required String date,
    required String id,
  }) async {
    final prefs = await _prefs;
    await prefs.setString(_dataUpdateDateKey, _normalizedOrDefault(date, _defaultDataUpdateDate));
    await prefs.setString(_dataUpdateIdKey, _normalizedOrDefault(id, _defaultDataUpdateId));
  }

  static Future<Map<String, String>> getDataUpdateInfo() async {
    return {
      'date': await getDataUpdateDate(),
      'id': await getDataUpdateId(),
    };
  }

  // Activity State
  static Future<void> setIsActivityRunning(String isRunning) async {
    final prefs = await _prefs;
    await prefs.setString(
      _isActivityRunningKey,
      _normalizedOrDefault(isRunning, _defaultIsActivityRunning),
    );
  }

  static Future<String> getIsActivityRunning() async {
    final prefs = await _prefs;
    return _normalizedOrDefault(
      prefs.getString(_isActivityRunningKey),
      _defaultIsActivityRunning,
    );
  }

  static Future<void> setIsAppUpdateImportant(String isImportant) async {
    final prefs = await _prefs;
    await prefs.setString(
      _isAppUpdateImportantKey,
      _normalizedOrDefault(isImportant, _defaultIsAppUpdateImportant),
    );
  }

  static Future<String> getIsAppUpdateImportant() async {
    final prefs = await _prefs;
    return _normalizedOrDefault(
      prefs.getString(_isAppUpdateImportantKey),
      _defaultIsAppUpdateImportant,
    );
  }

  // Bilty Info
  static Future<void> setPreviousBiltyNo(String biltyNo) async {
    final prefs = await _prefs;
    await prefs.setString(
      _previousBiltyNoKey,
      _normalizedOrDefault(biltyNo, _defaultPreviousBiltyNo),
    );
  }

  static Future<String> getPreviousBiltyNo() async {
    final prefs = await _prefs;
    return _normalizedOrDefault(
      prefs.getString(_previousBiltyNoKey),
      _defaultPreviousBiltyNo,
    );
  }

  static Future<void> setPreviousBiltyTime(String time) async {
    final prefs = await _prefs;
    await prefs.setString(
      _previousBiltyTimeKey,
      _normalizedOrDefault(time, _defaultPreviousBiltyTime),
    );
  }

  static Future<String> getPreviousBiltyTime() async {
    final prefs = await _prefs;
    return _normalizedOrDefault(
      prefs.getString(_previousBiltyTimeKey),
      _defaultPreviousBiltyTime,
    );
  }

  static Future<void> setPreviousBiltyInfo({
    required String biltyNo,
    required String biltyTime,
  }) async {
    final prefs = await _prefs;
    await prefs.setString(
      _previousBiltyNoKey,
      _normalizedOrDefault(biltyNo, _defaultPreviousBiltyNo),
    );
    await prefs.setString(
      _previousBiltyTimeKey,
      _normalizedOrDefault(biltyTime, _defaultPreviousBiltyTime),
    );
  }

  static Future<Map<String, String>> getPreviousBiltyInfo() async {
    return {
      'no': await getPreviousBiltyNo(),
      'time': await getPreviousBiltyTime(),
    };
  }

  // Legacy methods kept for compatibility with existing callers.
  static Future<void> saveUserSession({
    required int userId,
    required int employeeId,
  }) async {
    final prefs = await _prefs;
    await prefs.setInt(_legacyUserIdKey, userId);
    await prefs.setInt(_legacyEmployeeIdKey, employeeId);
  }

  static Future<int?> getUserId() async {
    final prefs = await _prefs;
    final user = await getUser();
    return user?.id ?? prefs.getInt(_legacyUserIdKey);
  }

  static Future<int?> getEmployeeId() async {
    final prefs = await _prefs;
    final user = await getUser();
    if (user?.employeeid != null && user!.employeeid.isNotEmpty) {
      return int.tryParse(user.employeeid);
    }
    return prefs.getInt(_legacyEmployeeIdKey);
  }

  // Generic Helpers
  static Future<void> setString(String key, String value) async {
    final prefs = await _prefs;
    await prefs.setString(key, value);
  }

  static Future<String> getString(String key, String defaultValue) async {
    final prefs = await _prefs;
    return prefs.getString(key) ?? defaultValue;
  }

  static Future<void> setInteger(String key, int value) async {
    final prefs = await _prefs;
    await prefs.setInt(key, value);
  }

  static Future<int> getInteger(String key, int defaultValue) async {
    final prefs = await _prefs;
    return prefs.getInt(key) ?? defaultValue;
  }

  static Future<SharedPreferences> get _prefs async {
    return SharedPreferences.getInstance();
  }

  static String _normalizedOrDefault(String? value, String defaultValue) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return defaultValue;
    }
    return normalized;
  }

  // Logout
  static Future<void> clearSession() async {
    final prefs = await _prefs;
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
    await prefs.remove(_legacyUserIdKey);
    await prefs.remove(_legacyEmployeeIdKey);
    // Keep saved credentials for login pre-fill flow.
  }
}
