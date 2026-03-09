import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/visit_route.dart';
import 'api_client.dart';
import 'local_db_service.dart';
import 'session_service.dart';

/// Fetches approved visit/route for the agent and saves locally.
/// Android: SharedPrefManager.getStaticIP() + URLs.AGENT_APPROVED_VISIT + "&userid=" + user.getEmployeeid()
class VisitService {
  VisitService._();

  static final VisitService instance = VisitService._();

  /// Android endpoint: /tclorder_apis/taj_api.php?getVisits=1&userid=
  static const String agentApprovedVisitPath =
      'taj_api.php?getVisits=1&userid=';

  static const String cacheKey = 'local_approved_visit';
  static const String routeCacheKey = 'local_route_data';

  /// Fetches approved visit data and saves to local cache.
  /// Returns the parsed list of visits or empty list on failure.
  Future<List<AgentApprovedVisit>> fetchAndSaveApprovedVisits() async {
    try {
      final baseUrl = await ApiClient.instance.getAgentBaseUrl();
      final employeeId = await SessionService.getEmployeeId();
      if (employeeId == null) return [];

      final url =
          baseUrl.replaceAll(RegExp(r'/$'), '') +
          '/' +
          agentApprovedVisitPath +
          employeeId.toString();
      final response = await ApiClient.instance.dio.get<String>(url);
      if (response.statusCode == 200 &&
          response.data != null &&
          response.data!.trim().isNotEmpty) {
        await LocalDbService.instance.saveLocalData(
          cacheKey: cacheKey,
          payload: response.data!,
        );
        final parsed = jsonDecode(response.data!);
        if (parsed is List) {
          return parsed
              .map(
                (e) => AgentApprovedVisit.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('VisitService.fetchAndSaveApprovedVisits: $e');
      return [];
    }
  }

  /// Reads cached approved visits
  Future<List<AgentApprovedVisit>> getCachedApprovedVisits() async {
    try {
      final payload = await LocalDbService.instance.getLocalData(cacheKey);
      if (payload == null) return [];
      final parsed = jsonDecode(payload);
      if (parsed is List) {
        return parsed
            .map(
              (e) => AgentApprovedVisit.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('VisitService.getCachedApprovedVisits: $e');
      return [];
    }
  }

  /// Reads cached route data
  Future<List<VisitRouteData>> getCachedRouteData() async {
    try {
      final payload = await LocalDbService.instance.getLocalData(routeCacheKey);
      if (payload == null) return [];
      final parsed = jsonDecode(payload);
      if (parsed is List) {
        return parsed
            .map(
              (e) =>
                  VisitRouteData.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('VisitService.getCachedRouteData: $e');
      return [];
    }
  }

  /// Get route by name (Android: getRouteDataByName)
  Future<VisitRouteData?> getRouteByName(String routeName) async {
    final routes = await getCachedRouteData();
    try {
      return routes.firstWhere((route) => route.routes == routeName);
    } catch (e) {
      return null;
    }
  }

  /// Reads cached approved visit payload (raw JSON string).
  Future<String?> getCachedPayload() async {
    return LocalDbService.instance.getLocalData(cacheKey);
  }

  /// Returns list of visits for dropdown (e.g. from response data or parsed list).
  Future<List<Map<String, dynamic>>> getVisitsForPicker() async {
    final payload = await getCachedPayload();
    if (payload == null || payload.isEmpty) return [];
    try {
      final d = jsonDecode(payload);
      if (d is List) {
        return d
            .map(
              (e) => e is Map
                  ? Map<String, dynamic>.from(e as Map)
                  : <String, dynamic>{},
            )
            .toList();
      }
      if (d is Map) {
        final map = d as Map<String, dynamic>;
        if (map['data'] is List)
          return (map['data'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        if (map['visits'] is List)
          return (map['visits'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        return [map];
      }
    } catch (_) {}
    return [];
  }
}
