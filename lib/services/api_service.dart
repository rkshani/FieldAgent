import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import 'api_config.dart';
import 'api_endpoints.dart';
import 'device_info_service.dart';
import 'local_db_service.dart';
import 'session_service.dart';

class ApiService {
  static const String baseUrl = ApiConfig.orderNewUrl;
  static const String androidApiRoot = '/order_android_api/';
  static const String fullApiUrl = '${ApiConfig.domain}$androidApiRoot';

  /// Login API – same as Android: API root = /tclorder_apis_new_test/
  static const String loginApiUrl = ApiConfig.loginUrl;

  /// TCL Local Data APIs (from Local Data Loading spec)
  static const String tclApiBase = ApiConfig.tclApiBase;

  /// Parties (and optional others) – use new_test base
  static const String tclApiBaseNewTest = ApiConfig.tclApiBaseNewTest;

  /// Per-endpoint result: { name, success, count, errorMessage? }
  static Map<String, dynamic> _endpointResult(
    String name,
    bool success, {
    int count = 0,
    String? errorMessage,
  }) => {
    'name': name,
    'success': success,
    'count': count,
    'error': errorMessage,
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

  /// Heavy endpoints can timeout on slow networks, so allow custom timeout + retry.
  static Future<http.Response> _getWithRetry(
    Uri uri, {
    required Duration timeout,
    int maxAttempts = 1,
  }) async {
    Object? lastError;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await http.get(uri).timeout(timeout);
      } catch (e) {
        lastError = e;
        if (attempt < maxAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
      }
    }
    throw Exception(lastError?.toString() ?? 'Request failed');
  }

  // Login API – POST (same as Android). Normal: check_login=1; special zeeshanjaved/123456: check_login_for_google_test=1.
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    String? fcmToken,
  }) async {
    const timeout = Duration(seconds: 45);
    final useGoogleTest = username == 'zeeshanjaved' && password == '123456';
    if (useGoogleTest) {
      // ignore: avoid_print
      debugPrint('[Login] path=google_test');
    } else {
      // ignore: avoid_print
      debugPrint('[Login] path=normal');
    }
    try {
      final deviceInfo = DeviceInfoService();
      await deviceInfo.initialize();

      final body = <String, String>{
        'username': username,
        'password': password,
        if (useGoogleTest)
          'check_login_for_google_test': '1'
        else
          'check_login': '1',
        'tokenid': fcmToken ?? '',
        ...deviceInfo.getDeviceParams(),
      };

      // ignore: avoid_print
      debugPrint('[Login] request start');
      final response = await http
          .post(Uri.parse(loginApiUrl), body: body)
          .timeout(
            timeout,
            onTimeout: () => throw Exception(
              'Request timeout. Please check your internet connection.',
            ),
          );
      // ignore: avoid_print
      debugPrint('[Login] request end status=${response.statusCode}');

      if (response.statusCode != 200) {
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
          'status': 'error',
          'data': null,
        };
      }

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
        final recId = userData['user_receipts']?.toString();
        if (recId != null) await SessionService.setUserRecId(recId);
        final account = userData['account']?.toString();
        if (account != null) await SessionService.setUserAccount(account);

        // ignore: avoid_print
        debugPrint(
          '[Login] success username=${user.username} employeeId=${user.employeeid} role=${user.role} account=${user.account}',
        );

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
              jsonResponse['message']?.toString() ??
              'Please contact administrator',
          'status': 'contact',
          'data': jsonResponse,
        };
      }
      if (status == 'showDialog') {
        final employeeId = jsonResponse['data']?.toString();
        return {
          'success': false,
          'message':
              jsonResponse['message']?.toString() ??
              'Device verification required',
          'status': 'showDialog',
          'employeeid': employeeId,
          'data': jsonResponse,
        };
      }
      // status == 'false' – show server data as error
      return {
        'success': false,
        'message':
            jsonResponse['data']?.toString() ??
            jsonResponse['message']?.toString() ??
            'Invalid username or password',
        'status': 'false',
        'data': jsonResponse,
      };
    } catch (e) {
      // ignore: avoid_print
      debugPrint('[Login] error: $e');
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
            'message':
                jsonResponse['message']?.toString() ?? 'Verification processed',
            'data': jsonResponse,
          };
        } on FormatException {
          return {
            'success': false,
            'message': 'Invalid response',
            'data': null,
          };
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
    {
      'name': 'Package Details 1',
      'url': 'taj_api.php?getPackageDetails=1&userid={userid}',
    },
    {
      'name': 'Package Details 2',
      'url': 'taj_api.php?getPackageDetails2=1&userid={userid}',
    },
    {'name': 'Packages', 'url': 'taj_api.php?getPackages=1&userid={userid}'},
    {'name': 'Store Data', 'url': 'taj_api.php?getStore=1'},
    {'name': 'Deliver Points', 'url': 'taj_api.php?getStore=1&userid={userid}'},
    {'name': 'Party', 'url': 'taj_api.php?getParty=1&userid={userid}'},
    {'name': 'Items', 'url': 'taj_api.php?getItems=1&userid={userid}'},
    {'name': 'Item Store Reorder', 'url': 'taj_api.php?getitemstorereorder=1'},
    {'name': 'Stock Update 2', 'url': 'taj_api.php?getstockupdate2=1'},
  ];

  static final String _goodsAgencyUrl = ApiEndpoints.goodsAgency();

  // Fetch and save all local data from TCL APIs; returns per-endpoint results for dialog.
  static Future<Map<String, dynamic>> fetchAndSaveLocalData() async {
    try {
      final storedUserId = await SessionService.getUserId();
      final userId = (storedUserId ?? 1013).toString();

      final List<Map<String, dynamic>> results = [];
      const defaultDuration = Duration(seconds: 30);

      for (final ep in _localDataEndpoints) {
        final name = ep['name']!;
        final urlTemplate = ep['url']!;
        // Party, Items, Packages: use new_test base (same as Party); rest use tclApiBase
        final useNewTest =
            name == 'Party' || name == 'Items' || name == 'Packages';
        final base = useNewTest ? tclApiBaseNewTest : tclApiBase;
        final url = urlTemplate.contains('{userid}')
            ? '$base${urlTemplate.replaceAll('{userid}', userId)}'
            : '$base$urlTemplate';
        final cacheKey = 'local_${name.toLowerCase().replaceAll(' ', '_')}';
        final isPackageDetails =
            name == 'Package Details 1' || name == 'Package Details 2';
        final timeout = isPackageDetails
            ? const Duration(seconds: 75)
            : defaultDuration;
        final attempts = isPackageDetails ? 2 : 1;

        try {
          final response = await _getWithRetry(
            Uri.parse(url),
            timeout: timeout,
            maxAttempts: attempts,
          );
          if (response.statusCode == 200 && response.body.isNotEmpty) {
            await LocalDbService.instance.saveLocalData(
              cacheKey: cacheKey,
              payload: response.body,
            );
            final count = _countItems(response.body);
            debugPrint(
              '[LocalSync] $name saved -> $cacheKey | bytes=${response.body.length} count=$count',
            );
            results.add(_endpointResult(name, true, count: count));
          } else {
            debugPrint('[LocalSync] $name failed: HTTP ${response.statusCode}');
            results.add(
              _endpointResult(
                name,
                false,
                errorMessage: 'HTTP ${response.statusCode}',
              ),
            );
          }
        } catch (e) {
          results.add(
            _endpointResult(
              name,
              false,
              errorMessage: e.toString().replaceFirst('Exception: ', ''),
            ),
          );
        }
      }

      // Goods Agency (different base URL)
      try {
        const name = 'Goods Agency';
        const cacheKey = 'local_goods_agency';
        final response = await _getWithRetry(
          Uri.parse(_goodsAgencyUrl),
          timeout: defaultDuration,
        );
        if (response.statusCode == 200 && response.body.isNotEmpty) {
          await LocalDbService.instance.saveLocalData(
            cacheKey: cacheKey,
            payload: response.body,
          );
          final count = _countItems(response.body);
          debugPrint(
            '[LocalSync] Goods Agency saved -> $cacheKey | bytes=${response.body.length} count=$count',
          );
          results.add(_endpointResult(name, true, count: count));
        } else {
          results.add(
            _endpointResult(
              name,
              false,
              errorMessage: 'HTTP ${response.statusCode}',
            ),
          );
        }
      } catch (e) {
        results.add(
          _endpointResult(
            'Goods Agency',
            false,
            errorMessage: e.toString().replaceFirst('Exception: ', ''),
          ),
        );
      }

      final successCount = results.where((r) => r['success'] == true).length;
      final total = results.length;
      final stats = <String, int>{};
      for (final r in results) {
        final name = r['name'] as String? ?? '';
        final count = r['count'] as int? ?? 0;
        if (name == 'Packages') {
          stats['packages'] = count;
        } else if (name == 'Items')
          stats['items'] = count;
        else if (name == 'Package Details 1')
          stats['package_details_1'] = count;
        else if (name == 'Package Details 2')
          stats['package_details_2'] = count;
        else if (name == 'Deliver Points')
          stats['delivery_points'] = count;
        else if (name == 'Party')
          stats['parties'] = count;
        else if (name == 'Goods Agency')
          stats['goods_agencies'] = count;
        else if (name == 'Store Data')
          stats['store_data'] = count;
      }
      stats['package_details'] =
          (stats['package_details_1'] ?? 0) + (stats['package_details_2'] ?? 0);
      stats['visits'] = 0;
      return {
        'success': successCount > 0,
        'message': successCount == total
            ? 'All $total datasets loaded and saved.'
            : '$successCount of $total datasets loaded. Check details below.',
        'results': results,
        'stats': stats,
      };
    } on UnsupportedError catch (e) {
      return {
        'success': false,
        'message': e.message ?? 'SQLite is not supported on this platform.',
        'results': <Map<String, dynamic>>[],
        'stats': <String, int>{},
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
        'results': <Map<String, dynamic>>[],
        'stats': <String, int>{},
      };
    }
  }

  /// Fetches Items API and saves to local_items (for Order Add when cache empty).
  static Future<bool> fetchItemsAndSave(String userId) async {
    try {
      final url = ApiEndpoints.itemsNewTest(userId);
      final response = await _getWithRetry(
        Uri.parse(url),
        timeout: const Duration(seconds: 30),
      );
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        await LocalDbService.instance.saveLocalData(
          cacheKey: 'local_items',
          payload: response.body,
        );
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('ApiService.fetchItemsAndSave: $e');
      return false;
    }
  }

  /// Fetches Packages API and saves to local_packages (for Order Add when cache empty).
  static Future<bool> fetchPackagesAndSave(String userId) async {
    try {
      final url = ApiEndpoints.packagesNewTest(userId);
      final response = await _getWithRetry(
        Uri.parse(url),
        timeout: const Duration(seconds: 30),
      );
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        await LocalDbService.instance.saveLocalData(
          cacheKey: 'local_packages',
          payload: response.body,
        );
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('ApiService.fetchPackagesAndSave: $e');
      return false;
    }
  }

  /// Android parity: POST order using postOrderZ endpoint with underscore-delimited format
  static Future<Map<String, dynamic>> postOrder({
    required String orderHeader,
    required String orderItems,
  }) async {
    try {
      final url = ApiEndpoints.postOrderZNewTest();
      final headers = <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
      };

      final body = {'order': orderHeader, 'item': orderItems};

      print('URL: $url');
      print('Headers: $headers');
      print('Body: $body');

      String preview(String value, {int max = 100}) {
        return value.length <= max ? value : value.substring(0, max);
      }

      debugPrint(
        '[ApiService.postOrder] Uploading order: ${preview(orderHeader)}...',
      );
      debugPrint('[ApiService.postOrder] Items: ${preview(orderItems)}...');

      final response = await http
          .post(Uri.parse(url), headers: headers, body: body)
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () =>
                throw Exception('Order upload timeout. Please try again.'),
          );

      print('Status Code: ${response.statusCode}');
      print('Response: ${response.body}');

      debugPrint(
        '[ApiService.postOrder] Response status: ${response.statusCode}',
      );
      debugPrint('[ApiService.postOrder] Response body: ${response.body}');

      if (response.statusCode != 200) {
        return {
          'status': 'failed',
          'message': 'Server error: ${response.statusCode}',
        };
      }

      final responseBody = response.body.trim();
      if (responseBody.isEmpty) {
        return {
          'status': 'failed',
          'message': 'Server returned empty response',
        };
      }

      try {
        final jsonResponse = jsonDecode(responseBody) as Map<String, dynamic>;
        final status = jsonResponse['status']?.toString().toLowerCase() ?? '';
        if (status == 'true' || status == '1') {
          return {...jsonResponse, 'status': 'success'};
        }
        return jsonResponse;
      } catch (e) {
        // If response is not JSON, check if it's a simple status string
        if (responseBody.toLowerCase().contains('success')) {
          return {'status': 'success', 'message': responseBody};
        }
        return {
          'status': 'failed',
          'message': 'Invalid server response: $responseBody',
        };
      }
    } catch (e) {
      print('postOrder Error: $e');
      debugPrint('[ApiService.postOrder] Error: $e');
      return {'status': 'failed', 'message': 'Upload failed: $e'};
    }
  }

  /// Fetch my orders from server.
  /// GET /tclorder_apis_new_test/order_web_api_z.php?get_my_orders=1&employeeid={id}
  static Future<Map<String, dynamic>> fetchMyOrders() async {
    try {
      final employeeId = await SessionService.getEmployeeId();
      if (employeeId == null) {
        return {
          'success': false,
          'message': 'No logged-in employee id found',
          'endpoint': null,
          'orders': <Map<String, dynamic>>[],
          'raw': null,
        };
      }

      // Try taj_api.php first (same file that receives postOrderZ uploads)
      // If that returns empty/fails, fall back to order_web_api_z.php
      final urlTaj = ApiEndpoints.myOrdersTajApi(employeeId.toString());
      final urlLegacy = ApiEndpoints.myOrders(employeeId.toString());

      for (final url in [urlTaj, urlLegacy]) {
        debugPrint('[fetchMyOrders] GET $url');
        try {
          final response = await _getWithRetry(
            Uri.parse(url),
            timeout: const Duration(seconds: 30),
          );

          if (response.statusCode != 200) {
            debugPrint(
              '[fetchMyOrders] $url returned ${response.statusCode}, trying next...',
            );
            continue;
          }

          final raw = response.body.trim();
          if (raw.isEmpty) {
            debugPrint('[fetchMyOrders] $url returned empty, trying next...');
            continue;
          }

          final parsed = _extractOrdersFromPayload(raw);
          debugPrint('[fetchMyOrders] $url parsed ${parsed.length} orders');

          if (parsed.isNotEmpty || url == urlLegacy) {
            return {
              'success': true,
              'message': 'Orders fetched successfully',
              'endpoint': url,
              'orders': parsed,
              'raw': raw,
            };
          }
        } catch (e) {
          debugPrint('[fetchMyOrders] $url error: $e, trying next...');
          continue;
        }
      }

      return {
        'success': false,
        'message': 'No orders found on any endpoint',
        'endpoint': urlLegacy,
        'orders': <Map<String, dynamic>>[],
        'raw': null,
      };
    } catch (e) {
      debugPrint('[fetchMyOrders] error: $e');
      return {
        'success': false,
        'message': 'Error: $e',
        'endpoint': null,
        'orders': <Map<String, dynamic>>[],
        'raw': null,
      };
    }
  }

  static List<Map<String, dynamic>> _extractOrdersFromPayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> && _looksLikeOrder(decoded)) {
        return [decoded];
      }
      final list = _extractList(decoded);
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static List<dynamic> _extractList(dynamic node) {
    if (node is List) return node;
    if (node is Map) {
      for (final key in const [
        'data',
        'orders',
        'result',
        'rows',
        'records',
        'list',
        'my_orders',
      ]) {
        final value = node[key];
        if (value is List) return value;
      }
      for (final value in node.values) {
        if (value is List && value.isNotEmpty) return value;
      }
      for (final value in node.values) {
        final nested = _extractList(value);
        if (nested.isNotEmpty) return nested;
      }
    }
    return const [];
  }

  static bool _looksLikeOrder(Map<String, dynamic> row) {
    const keys = <String>{
      'order_id',
      'id',
      'party_name',
      'package_name',
      'created_at',
      'date',
      'net_total',
    };
    for (final key in keys) {
      if (row.containsKey(key)) return true;
    }
    return false;
  }
}
