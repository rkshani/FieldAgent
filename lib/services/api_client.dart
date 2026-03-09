import 'package:dio/dio.dart';

import 'session_service.dart';

/// Dio-based client for Order Add / agent APIs.
/// Base URL for agent-specific endpoints comes from SessionService (static IP).
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  static const String defaultBaseUrl = 'https://www.hisaab.org';

  /// Base for TCL order web APIs (e.g. order_web_api_z.php).
  static const String androidApiRoot = '/tclorder_apis/';

  Dio? _dio;

  Dio get dio {
    _dio ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ));
    return _dio!;
  }

  /// Base URL for agent APIs (approved visit, sync). Uses static IP from session.
  Future<String> getAgentBaseUrl() async {
    return SessionService.getStaticIP();
  }

  /// Full URL for hisaab.org TCL APIs (goods agency, payment methods, etc.).
  String getTclOrderWebUrl(String path) {
    return '$defaultBaseUrl$androidApiRoot$path';
  }
}
