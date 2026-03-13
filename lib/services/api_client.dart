import 'package:dio/dio.dart';

import 'api_endpoints.dart';
import 'session_service.dart';

/// Dio-based client for Order Add / agent APIs.
/// Base URL for agent-specific endpoints comes from SessionService (static IP).
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  Dio? _dio;

  Dio get dio {
    _dio ??= Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    return _dio!;
  }

  /// Base URL for agent APIs (approved visit, sync). Uses static IP from session.
  Future<String> getAgentBaseUrl() async {
    return SessionService.getStaticIP();
  }

  /// Full URL for hisaab.org TCL APIs (goods agency, payment methods, etc.).
  String getTclOrderWebUrl(String path) {
    return ApiEndpoints.tclOrderWeb(path);
  }
}
