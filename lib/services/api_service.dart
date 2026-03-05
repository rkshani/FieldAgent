import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import 'device_info_service.dart';
import 'local_db_service.dart';
import 'session_service.dart';

class ApiService {
  static const String baseUrl = 'https://www.hisaab.org/order/new.php';
  static const String androidApiRoot = '/order_android_api/';
  static const String fullApiUrl = 'https://www.hisaab.org$androidApiRoot';

  /// Login API – POST to new.php (use tclorder_apis_new_test; change if your server uses order_android_api)
  static const String loginApiUrl =
      'https://www.hisaab.org/tclorder_apis_new_test/new.php';

  /// TCL Local Data APIs (from Local Data Loading spec)
  static const String tclApiBase = 'https://www.hisaab.org/tclorder_apis/';

  /// Per-endpoint result: { name, success, count, errorMessage? }
  static Map<String, dynamic> _endpointResult(
    String name,
    bool success, {
    int count = 0,
    String? errorMessage,
  }) =>
      {
        'name': name,
        'success': success,
        'count': count,
        if (errorMessage != null) 'error': errorMessage,
      };

  static int _countItems(String rawPayload) {
    try {
      final d = jsonDecode(rawPayload);
      if (d is List) return d.length;
      if (d is Map) return d.length;
      return 1;
    } catch (_) {
      return 1;
    }
  }

  // Login API – GET with query params (tclorder_apis_new_test/new.php?check_login=1&username=...&password=...&Android_id=...)
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    String? fcmToken,
  }) async {
    try {
      final deviceInfo = DeviceInfoService();
      await deviceInfo.initialize();

      final params = <String, String>{
        'check_login': '1',
        'username': username,
        'password': password,
        ...deviceInfo.getDeviceParams(),
        if (fcmToken != null && fcmToken.isNotEmpty) 'tokenid': fcmToken,
      };

      final uri = Uri.parse(loginApiUrl).replace(queryParameters: params);
      final response = await http
          .get(uri)
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () {
              throw Exception(
                'Request timeout. Please check your internet connection.',
              );
            },
          );

      if (response.statusCode == 200) {
        final responseBody = response.body.trim();
        if (responseBody.isEmpty) {
          return {
            'success': false,
            'message': 'Server returned empty response. Please try again.',
            'status': 'error',
            'data': null,
          };
        }
        Map<String, dynamic> jsonResponse;
        try {
          jsonResponse = jsonDecode(responseBody) as Map<String, dynamic>;
        } on FormatException catch (_) {
          return {
            'success': false,
            'message': 'Invalid server response. Please try again later.',
            'status': 'error',
            'data': null,
          };
        }

        final status = jsonResponse['status']?.toString() ?? '';

        if (status == 'success') {
          // Android: user from obj.getJSONObject("data")
          final userData = jsonResponse['data'];
          if (userData == null || userData is! Map<String, dynamic>) {
            return {
              'success': false,
              'message': 'Invalid login response.',
              'status': 'error',
              'data': null,
            };
          }
          final user = User.fromJson(userData);

          await SessionService.saveUser(user);

          // Android: recID = userJson.getString("user_receipts"), account = userJson.getString("account")
          final recId = userData['user_receipts']?.toString();
          if (recId != null) await SessionService.setUserRecId(recId);
          final account = userData['account']?.toString();
          if (account != null) await SessionService.setUserAccount(account);

          return {
            'success': true,
            'message': jsonResponse['message']?.toString() ?? 'Login successful',
            'status': 'success',
            'user': user,
            'data': jsonResponse,
          };
        }
        if (status == 'contact') {
          return {
            'success': false,
            'message':
                jsonResponse['message']?.toString() ?? 'Please contact administrator',
            'status': 'contact',
            'data': jsonResponse,
          };
        }
        if (status == 'showDialog') {
          // Android: ChangeDeviceDialog(obj.getString("data")) – data is employeeid
          final employeeId = jsonResponse['data']?.toString();
          return {
            'success': false,
            'message':
                jsonResponse['message']?.toString() ?? 'Device verification required',
            'status': 'showDialog',
            'employeeid': employeeId,
            'data': jsonResponse,
          };
        }
        // status == 'false'
        return {
          'success': false,
          'message':
              jsonResponse['message']?.toString() ?? jsonResponse['data']?.toString() ?? 'Invalid username or password',
          'status': 'false',
          'data': jsonResponse,
        };
      }

      return {
        'success': false,
        'message': 'Server error: ${response.statusCode}',
        'status': 'error',
        'data': null,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
        'status': 'error',
        'data': null,
      };
    }
  }

  // Device verification – POST same URL as Android: employeeid, update_device=1, device params
  static Future<Map<String, dynamic>> verifyNewDevice({
    required String employeeId,
  }) async {
    try {
      final deviceInfo = DeviceInfoService();
      await deviceInfo.initialize();

      final body = <String, String>{
        'employeeid': employeeId,
        'update_device': '1',
        ...deviceInfo.getDeviceParams(),
      };

      final response = await http
          .post(Uri.parse(loginApiUrl), body: body)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final bodyStr = response.body.trim();
        if (bodyStr.isEmpty) {
          return {'success': false, 'message': 'Empty response', 'data': null};
        }
        try {
          final jsonResponse = jsonDecode(bodyStr) as Map<String, dynamic>;
          return {
            'success': jsonResponse['status']?.toString() == 'success',
            'message': jsonResponse['message']?.toString() ?? 'Verification processed',
            'data': jsonResponse,
          };
        } on FormatException {
          return {'success': false, 'message': 'Invalid response', 'data': null};
        }
      }

      return {
        'success': false,
        'message': 'Server error: ${response.statusCode}',
        'data': null,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
        'data': null,
      };
    }
  }

  /// Local data endpoints from spec (name, url with {userid} placeholder if needed)
  static const List<Map<String, String>> _localDataEndpoints = [
    {'name': 'Package Details 1', 'url': 'taj_api.php?getPackageDetails=1&userid={userid}'},
    {'name': 'Package Details 2', 'url': 'taj_api.php?getPackageDetails2=1&userid={userid}'},
    {'name': 'Packages', 'url': 'taj_api.php?getPackages=1&userid={userid}'},
    {'name': 'Store Data', 'url': 'taj_api.php?getStore=1'},
    {'name': 'Deliver Points', 'url': 'taj_api.php?getStore=1&userid={userid}'},
    {'name': 'Party', 'url': 'taj_api.php?getParty=1&userid={userid}'},
    {'name': 'Items', 'url': 'taj_api.php?getItems=1&userid={userid}'},
    {'name': 'Item Store Reorder', 'url': 'taj_api.php?getitemstorereorder=1'},
    {'name': 'Stock Update 2', 'url': 'taj_api.php?getstockupdate2=1'},
  ];

  static const String _goodsAgencyUrl =
      'https://www.hisaab.org/tclorder_apis/order_web_api_z.php?get_goodsagency=1';

  // Fetch and save all local data from TCL APIs; returns per-endpoint results for dialog.
  static Future<Map<String, dynamic>> fetchAndSaveLocalData() async {
    try {
      final storedUserId = await SessionService.getUserId();
      final userId = (storedUserId ?? 1013).toString();

      final List<Map<String, dynamic>> results = [];
      final duration = const Duration(seconds: 30);

      for (final ep in _localDataEndpoints) {
        final name = ep['name']!;
        final urlTemplate = ep['url']!;
        final url = urlTemplate.contains('{userid}')
            ? '${tclApiBase}${urlTemplate.replaceAll('{userid}', userId)}'
            : '${tclApiBase}$urlTemplate';
        final cacheKey = 'local_${name.toLowerCase().replaceAll(' ', '_')}';

        try {
          final response = await http.get(Uri.parse(url)).timeout(duration);
          if (response.statusCode == 200 && response.body.isNotEmpty) {
            await LocalDbService.instance.saveLocalData(
              cacheKey: cacheKey,
              payload: response.body,
            );
            final count = _countItems(response.body);
            results.add(_endpointResult(name, true, count: count));
          } else {
            results.add(_endpointResult(
              name,
              false,
              errorMessage: 'HTTP ${response.statusCode}',
            ));
          }
        } catch (e) {
          results.add(_endpointResult(
            name,
            false,
            errorMessage: e.toString().replaceFirst('Exception: ', ''),
          ));
        }
      }

      // Goods Agency (different base URL)
      try {
        const name = 'Goods Agency';
        const cacheKey = 'local_goods_agency';
        final response = await http.get(Uri.parse(_goodsAgencyUrl)).timeout(duration);
        if (response.statusCode == 200 && response.body.isNotEmpty) {
          await LocalDbService.instance.saveLocalData(
            cacheKey: cacheKey,
            payload: response.body,
          );
          final count = _countItems(response.body);
          results.add(_endpointResult(name, true, count: count));
        } else {
          results.add(_endpointResult(
            name,
            false,
            errorMessage: 'HTTP ${response.statusCode}',
          ));
        }
      } catch (e) {
        results.add(_endpointResult(
          'Goods Agency',
          false,
          errorMessage: e.toString().replaceFirst('Exception: ', ''),
        ));
      }

      final successCount = results.where((r) => r['success'] == true).length;
      final total = results.length;
      return {
        'success': successCount > 0,
        'message': successCount == total
            ? 'All $total datasets loaded and saved.'
            : '$successCount of $total datasets loaded. Check details below.',
        'results': results,
      };
    } on UnsupportedError catch (e) {
      return {
        'success': false,
        'message': e.message ?? 'SQLite is not supported on this platform.',
        'results': <Map<String, dynamic>>[],
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
        'results': <Map<String, dynamic>>[],
      };
    }
  }
}
