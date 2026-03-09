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
      'tclorder_apis/taj_api.php?getVisits=1&userid=';
  static const String visitedPartiesPath =
      'tclorder_apis/taj_api.php?get_visited_parties=1&user_id=';

  static const String cacheKey = 'local_approved_visit';
  static const String routeCacheKey = 'local_route_data';
  static const String visitedPartiesCachePrefix = 'local_visited_parties_';

  Future<List<int>> _candidateUserIds() async {
    final ids = <int>[];
    final userId = await SessionService.getUserId();
    final employeeId = await SessionService.getEmployeeId();
    if (userId != null && userId > 0) ids.add(userId);
    if (employeeId != null && employeeId > 0 && employeeId != userId) {
      ids.add(employeeId);
    }
    debugPrint(
      '[VisitService] candidate ids -> userId=$userId employeeId=$employeeId final=$ids',
    );
    return ids;
  }

  Future<void> _saveVisitPayloadForKnownIds(String payload) async {
    final ids = await _candidateUserIds();
    debugPrint(
      '[VisitService] saving visit payload for ids=$ids bytes=${payload.length}',
    );
    for (final id in ids) {
      await SessionService.saveUserVisitPayload(
        employeeId: id,
        payload: payload,
      );
      await SessionService.saveUserVisitMeta(employeeId: id);
      debugPrint('[VisitService] saved visit payload/meta for id=$id');
    }
  }

  Future<void> _saveVisitedPartiesForKnownIds({
    required String payload,
    required String visitId,
    required String routeId,
    String? cityId,
  }) async {
    final ids = await _candidateUserIds();
    debugPrint(
      '[VisitService] saving visited-parties payload for ids=$ids visitId=$visitId routeId=$routeId cityId=$cityId bytes=${payload.length}',
    );
    for (final id in ids) {
      await SessionService.saveUserVisitedPartiesPayload(
        employeeId: id,
        payload: payload,
      );
      await SessionService.saveUserVisitMeta(
        employeeId: id,
        selectedVisitId: visitId,
        selectedRouteId: routeId,
        selectedCityId: cityId,
      );
      debugPrint('[VisitService] saved visited-parties/meta for id=$id');
    }
  }

  List<AgentApprovedVisit> _parseApprovedVisits(dynamic parsed) {
    List<dynamic> rows = [];
    if (parsed is List) {
      rows = parsed;
    } else if (parsed is Map) {
      final map = Map<String, dynamic>.from(parsed);
      if (map['data'] is List) {
        rows = map['data'] as List;
      } else if (map['visits'] is List) {
        rows = map['visits'] as List;
      } else if (map['result'] is List) {
        rows = map['result'] as List;
      } else if (map['records'] is List) {
        rows = map['records'] as List;
      } else if (map['rows'] is List) {
        rows = map['rows'] as List;
      } else {
        for (final value in map.values) {
          if (value is List && value.isNotEmpty) {
            rows = value;
            break;
          }
        }
        if (rows.isEmpty) {
          rows = [map];
        }
      }
    }

    return rows
        .whereType<Map>()
        .map((e) => AgentApprovedVisit.fromJson(Map<String, dynamic>.from(e)))
        .where((v) => (v.visitId ?? '').trim().isNotEmpty)
        .toList();
  }

  /// Fetches approved visit data and saves to local cache.
  /// Returns the parsed list of visits or empty list on failure.
  Future<List<AgentApprovedVisit>> fetchAndSaveApprovedVisits() async {
    try {
      final baseUrl = await ApiClient.instance.getAgentBaseUrl();
      final ids = await _candidateUserIds();
      debugPrint(
        '[VisitService] fetchAndSaveApprovedVisits baseUrl=$baseUrl ids=$ids',
      );
      if (ids.isEmpty) return [];

      for (final id in ids) {
        try {
          final url =
              '${baseUrl.replaceAll(RegExp(r'/$'), '')}/$agentApprovedVisitPath$id';
          debugPrint('[VisitService] GET visits url=$url');
          final response = await ApiClient.instance.dio.get<String>(url);
          debugPrint(
            '[VisitService] visits response id=$id status=${response.statusCode} bytes=${response.data?.length ?? 0}',
          );
          if (response.statusCode != 200 ||
              response.data == null ||
              response.data!.trim().isEmpty) {
            debugPrint(
              '[VisitService] visits skipped for id=$id due to empty/non-200 response',
            );
            continue;
          }

          final raw = response.data!;
          final parsed = jsonDecode(raw);
          final visits = _parseApprovedVisits(parsed);
          debugPrint(
            '[VisitService] parsed visits id=$id count=${visits.length}',
          );
          if (visits.isEmpty) {
            debugPrint(
              '[VisitService] parsed visits empty for id=$id, trying next id',
            );
            continue;
          }

          await LocalDbService.instance.saveLocalData(
            cacheKey: cacheKey,
            payload: raw,
          );
          await _saveVisitPayloadForKnownIds(raw);
          debugPrint('[VisitService] visits fetch/save success using id=$id');
          return visits;
        } catch (e) {
          debugPrint(
            '[VisitService] visits request failed for id=$id error=$e',
          );
          continue;
        }
      }
      debugPrint('[VisitService] visits fetch exhausted all ids with no data');
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
      debugPrint(
        '[VisitService] cached visits payload bytes=${payload?.length ?? 0}',
      );
      if (payload != null && payload.trim().isNotEmpty) {
        final parsed = jsonDecode(payload);
        final visits = _parseApprovedVisits(parsed);
        debugPrint(
          '[VisitService] cached visits parsed count=${visits.length}',
        );
        if (visits.isNotEmpty) {
          return visits;
        }
      }

      // Cache is missing/stale/empty; fetch from API as fallback.
      return await fetchAndSaveApprovedVisits();
    } catch (e) {
      debugPrint('VisitService.getCachedApprovedVisits: $e');
      return await fetchAndSaveApprovedVisits();
    }
  }

  /// Prefer network for spinner parity with Android; fallback to local cache.
  Future<List<AgentApprovedVisit>> getApprovedVisits({
    bool preferRemote = true,
  }) async {
    if (preferRemote) {
      final remote = await fetchAndSaveApprovedVisits();
      debugPrint(
        '[VisitService] getApprovedVisits remote count=${remote.length}',
      );
      if (remote.isNotEmpty) return remote;
    }
    final cached = await getCachedApprovedVisits();
    debugPrint(
      '[VisitService] getApprovedVisits cached count=${cached.length}',
    );
    return cached;
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
              (e) =>
                  e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{},
            )
            .toList();
      }
      if (d is Map) {
        final map = d as Map<String, dynamic>;
        if (map['data'] is List) {
          return (map['data'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
        if (map['visits'] is List) {
          return (map['visits'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
        return [map];
      }
    } catch (_) {}
    return [];
  }

  String _visitedPartiesCacheKey({
    required int employeeId,
    required String visitId,
    required String routeId,
  }) {
    return '$visitedPartiesCachePrefix${employeeId}_${visitId}_$routeId';
  }

  List<Map<String, dynamic>> _parseVisitedParties(dynamic parsed) {
    List<dynamic> rows = [];
    if (parsed is List) {
      rows = parsed;
    } else if (parsed is Map) {
      final map = Map<String, dynamic>.from(parsed);
      if (map['data'] is List) {
        rows = map['data'] as List;
      } else if (map['parties'] is List) {
        rows = map['parties'] as List;
      } else if (map['visited_parties'] is List) {
        rows = map['visited_parties'] as List;
      } else if (map['result'] is List) {
        rows = map['result'] as List;
      }
    }

    return rows
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchAndSaveVisitedParties({
    required String visitId,
    required String routeId,
    String? cityId,
  }) async {
    try {
      final baseUrl = await ApiClient.instance.getAgentBaseUrl();
      final ids = await _candidateUserIds();
      debugPrint(
        '[VisitService] fetchAndSaveVisitedParties baseUrl=$baseUrl ids=$ids visitId=$visitId routeId=$routeId cityId=$cityId',
      );
      if (ids.isEmpty) return [];

      for (final id in ids) {
        try {
          final url =
              '${baseUrl.replaceAll(RegExp(r'/$'), '')}/$visitedPartiesPath$id&visitid=$visitId&routeid=$routeId';
          debugPrint('[VisitService] GET visited parties url=$url');

          final response = await ApiClient.instance.dio.get<String>(url);
          debugPrint(
            '[VisitService] visited parties response id=$id status=${response.statusCode} bytes=${response.data?.length ?? 0}',
          );
          if (response.statusCode != 200 ||
              response.data == null ||
              response.data!.trim().isEmpty) {
            debugPrint(
              '[VisitService] visited parties skipped for id=$id due to empty/non-200 response',
            );
            continue;
          }

          final raw = response.data!;
          final parsed = jsonDecode(raw);
          final parties = _parseVisitedParties(parsed);
          debugPrint(
            '[VisitService] parsed visited parties id=$id count=${parties.length}',
          );
          if (parties.isEmpty) {
            debugPrint(
              '[VisitService] parsed visited parties empty for id=$id, trying next id',
            );
            continue;
          }

          final cacheKey = _visitedPartiesCacheKey(
            employeeId: id,
            visitId: visitId,
            routeId: routeId,
          );
          await LocalDbService.instance.saveLocalData(
            cacheKey: cacheKey,
            payload: raw,
          );
          await _saveVisitedPartiesForKnownIds(
            payload: raw,
            visitId: visitId,
            routeId: routeId,
            cityId: cityId,
          );

          debugPrint(
            '[VisitService] visited parties fetch/save success using id=$id',
          );
          return parties;
        } catch (e) {
          debugPrint(
            '[VisitService] visited parties request failed for id=$id error=$e',
          );
          continue;
        }
      }
      debugPrint(
        '[VisitService] visited parties fetch exhausted all ids with no data',
      );
    } catch (e) {
      debugPrint('VisitService.fetchAndSaveVisitedParties: $e');
    }
    return [];
  }
}
