import 'package:flutter/material.dart';
import 'dart:convert';

import '../models/user.dart';
import '../services/session_service.dart';
import '../services/visit_service.dart';

class LoginTestingScreen extends StatefulWidget {
  const LoginTestingScreen({super.key});

  @override
  State<LoginTestingScreen> createState() => _LoginTestingScreenState();
}

class _LoginTestingScreenState extends State<LoginTestingScreen> {
  bool _isLoading = true;
  bool _showPassword = false;
  String? _errorMessage;

  User? _user;
  bool _isLoggedIn = false;
  String? _savedUsername;
  String? _savedPassword;
  int? _userId;
  int? _employeeId;
  String? _staticIp;
  String? _userAccount;
  String? _userRecId;
  String? _dataUpdateDate;
  String? _dataUpdateId;
  String? _visitPayload;
  String? _visitedPartiesPayload;
  Map<String, dynamic> _visitMeta = {};
  int _visitCount = 0;
  int _visitedPartiesCount = 0;
  final List<Map<String, String>> _visitPreviewRows = [];

  @override
  void initState() {
    super.initState();
    _loadLoginData();
  }

  Future<void> _loadLoginData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await SessionService.getUser();
      final isLoggedIn = await SessionService.isLoggedIn();
      final savedUsername = await SessionService.getSavedUsername();
      final savedPassword = await SessionService.getSavedPassword();
      final userId = await SessionService.getUserId();
      final employeeId = await SessionService.getEmployeeId();
      final staticIp = await SessionService.getStaticIP();
      final userAccount = await SessionService.getUserAccount();
      final userRecId = await SessionService.getUserRecId();
      final dataUpdateDate = await SessionService.getDataUpdateDate();
      final dataUpdateId = await SessionService.getDataUpdateId();
      debugPrint(
        '[LoginTesting] ids userId=$userId employeeId=$employeeId staticIp=$staticIp',
      );
      String? visitPayload = await SessionService.getUserVisitPayload(
        employeeId: employeeId,
      );
      String? visitedPartiesPayload =
          await SessionService.getUserVisitedPartiesPayload(
            employeeId: employeeId,
          );
      Map<String, dynamic> visitMeta = await SessionService.getUserVisitMeta(
        employeeId: employeeId,
      );
      debugPrint(
        '[LoginTesting] primary read employeeId=$employeeId visitBytes=${visitPayload?.length ?? 0} visitedPartiesBytes=${visitedPartiesPayload?.length ?? 0} metaKeys=${visitMeta.keys.toList()}',
      );

      if ((visitPayload == null || visitPayload.trim().isEmpty) &&
          userId != null) {
        visitPayload = await SessionService.getUserVisitPayload(
          employeeId: userId,
        );
        debugPrint(
          '[LoginTesting] fallback visit payload from userId=$userId bytes=${visitPayload?.length ?? 0}',
        );
      }
      if ((visitedPartiesPayload == null ||
              visitedPartiesPayload.trim().isEmpty) &&
          userId != null) {
        visitedPartiesPayload =
            await SessionService.getUserVisitedPartiesPayload(
              employeeId: userId,
            );
        debugPrint(
          '[LoginTesting] fallback visited-parties payload from userId=$userId bytes=${visitedPartiesPayload?.length ?? 0}',
        );
      }
      if (visitMeta.isEmpty && userId != null) {
        visitMeta = await SessionService.getUserVisitMeta(employeeId: userId);
        debugPrint(
          '[LoginTesting] fallback meta from userId=$userId metaKeys=${visitMeta.keys.toList()}',
        );
      }

      // If nothing is saved locally yet, force a visit fetch so this testing
      // screen can verify end-to-end API -> local storage flow.
      final noVisitData = visitPayload == null || visitPayload.trim().isEmpty;
      if (noVisitData) {
        debugPrint(
          '[LoginTesting] local visit payload empty. Triggering remote fetch...',
        );
        final fetchedVisits = await VisitService.instance
            .fetchAndSaveApprovedVisits();
        debugPrint(
          '[LoginTesting] remote visits fetched count=${fetchedVisits.length}',
        );

        if (fetchedVisits.isNotEmpty) {
          final first = fetchedVisits.first;
          final visitId = (first.visitId ?? '').trim();
          final routeId = (first.routeId ?? '').trim();
          final cityId = (first.cityIds ?? '').trim();
          if (visitId.isNotEmpty && routeId.isNotEmpty) {
            final parties = await VisitService.instance
                .fetchAndSaveVisitedParties(
                  visitId: visitId,
                  routeId: routeId,
                  cityId: cityId,
                );
            debugPrint(
              '[LoginTesting] remote visited-parties fetched count=${parties.length}',
            );
          }
        }

        // Reload from local after forced fetch.
        visitPayload = await SessionService.getUserVisitPayload(
          employeeId: employeeId,
        );
        visitedPartiesPayload =
            await SessionService.getUserVisitedPartiesPayload(
              employeeId: employeeId,
            );
        visitMeta = await SessionService.getUserVisitMeta(
          employeeId: employeeId,
        );

        if ((visitPayload == null || visitPayload.trim().isEmpty) &&
            userId != null) {
          visitPayload = await SessionService.getUserVisitPayload(
            employeeId: userId,
          );
        }
        if ((visitedPartiesPayload == null ||
                visitedPartiesPayload.trim().isEmpty) &&
            userId != null) {
          visitedPartiesPayload =
              await SessionService.getUserVisitedPartiesPayload(
                employeeId: userId,
              );
        }
        if (visitMeta.isEmpty && userId != null) {
          visitMeta = await SessionService.getUserVisitMeta(employeeId: userId);
        }

        debugPrint(
          '[LoginTesting] post-fetch local read visitBytes=${visitPayload?.length ?? 0} visitedPartiesBytes=${visitedPartiesPayload?.length ?? 0} metaKeys=${visitMeta.keys.toList()}',
        );
      }

      int visitCount = 0;
      int visitedPartiesCount = 0;
      if (visitPayload != null && visitPayload.trim().isNotEmpty) {
        try {
          final parsed = jsonDecode(visitPayload);
          final rows = <Map<String, String>>[];
          if (parsed is List) {
            visitCount = parsed.length;
            for (final row in parsed.take(5)) {
              if (row is Map) {
                rows.add(_toVisitPreviewRow(Map<String, dynamic>.from(row)));
              }
            }
          } else if (parsed is Map) {
            if (parsed['data'] is List) {
              visitCount = (parsed['data'] as List).length;
              for (final row in (parsed['data'] as List).take(5)) {
                if (row is Map) {
                  rows.add(_toVisitPreviewRow(Map<String, dynamic>.from(row)));
                }
              }
            } else if (parsed['visits'] is List) {
              visitCount = (parsed['visits'] as List).length;
              for (final row in (parsed['visits'] as List).take(5)) {
                if (row is Map) {
                  rows.add(_toVisitPreviewRow(Map<String, dynamic>.from(row)));
                }
              }
            } else {
              visitCount = 1;
              rows.add(_toVisitPreviewRow(Map<String, dynamic>.from(parsed)));
            }
          }
          _visitPreviewRows
            ..clear()
            ..addAll(rows);
          debugPrint(
            '[LoginTesting] visit payload parsed count=$visitCount previewRows=${_visitPreviewRows.length}',
          );
        } catch (_) {}
      }
      if (visitedPartiesPayload != null &&
          visitedPartiesPayload.trim().isNotEmpty) {
        try {
          final parsed = jsonDecode(visitedPartiesPayload);
          if (parsed is List) {
            visitedPartiesCount = parsed.length;
          } else if (parsed is Map) {
            if (parsed['data'] is List) {
              visitedPartiesCount = (parsed['data'] as List).length;
            } else if (parsed['parties'] is List) {
              visitedPartiesCount = (parsed['parties'] as List).length;
            } else if (parsed['visited_parties'] is List) {
              visitedPartiesCount = (parsed['visited_parties'] as List).length;
            } else {
              visitedPartiesCount = 1;
            }
          }
          debugPrint(
            '[LoginTesting] visited parties payload parsed count=$visitedPartiesCount',
          );
        } catch (_) {}
      }

      debugPrint(
        '[LoginTesting] final state visitCount=$visitCount visitedPartiesCount=$visitedPartiesCount selectedVisit=${visitMeta['selected_visit_id']} selectedRoute=${visitMeta['selected_route_id']} selectedCity=${visitMeta['selected_city_id']}',
      );

      if (!mounted) return;

      setState(() {
        _user = user;
        _isLoggedIn = isLoggedIn;
        _savedUsername = savedUsername;
        _savedPassword = savedPassword;
        _userId = userId;
        _employeeId = employeeId;
        _staticIp = staticIp;
        _userAccount = userAccount;
        _userRecId = userRecId;
        _dataUpdateDate = dataUpdateDate;
        _dataUpdateId = dataUpdateId;
        _visitPayload = visitPayload;
        _visitedPartiesPayload = visitedPartiesPayload;
        _visitMeta = visitMeta;
        _visitCount = visitCount;
        _visitedPartiesCount = visitedPartiesCount;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[LoginTesting] load error=$e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to read login/session data: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login Testing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload saved data',
            onPressed: _loadLoginData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildStatusCard(context),
                const SizedBox(height: 12),
                _buildCredentialsCard(context),
                const SizedBox(height: 12),
                _buildUserCard(context),
                const SizedBox(height: 12),
                _buildSessionCard(context),
                const SizedBox(height: 12),
                _buildVisitDataCard(context),
              ],
            ),
    );
  }

  Widget _buildVisitDataCard(BuildContext context) {
    String? clip(String? v) {
      if (v == null || v.trim().isEmpty) return null;
      const maxLen = 400;
      if (v.length <= maxLen) return v;
      return '${v.substring(0, maxLen)}...';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.route_outlined),
                SizedBox(width: 8),
                Text(
                  'Visit Data (Local Profile)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const Divider(height: 20),
            _buildDataRow('Visits Count', _visitCount.toString()),
            _buildDataRow(
              'Visited Parties Count',
              _visitedPartiesCount.toString(),
            ),
            _buildDataRow(
              'Selected Visit ID',
              _visitMeta['selected_visit_id']?.toString(),
            ),
            _buildDataRow(
              'Selected Route ID',
              _visitMeta['selected_route_id']?.toString(),
            ),
            _buildDataRow(
              'Selected City ID',
              _visitMeta['selected_city_id']?.toString(),
            ),
            _buildDataRow('Updated At', _visitMeta['updated_at']?.toString()),
            const SizedBox(height: 8),
            const Text(
              'Visits (Local Parsed):',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            if (_visitPreviewRows.isEmpty)
              const Text('-')
            else
              ..._visitPreviewRows.map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    'Visit: ${row['visit_id']} | Route: ${row['route_id']} | City: ${row['city_id']}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Visit Payload (Preview):',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            SelectableText(clip(_visitPayload) ?? '-'),
            const SizedBox(height: 10),
            const Text(
              'Visited Parties Payload (Preview):',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            SelectableText(clip(_visitedPartiesPayload) ?? '-'),
          ],
        ),
      ),
    );
  }

  Map<String, String> _toVisitPreviewRow(Map<String, dynamic> row) {
    final visitId = row['visit_id']?.toString().trim() ?? '';
    final routeId =
        row['route_id']?.toString().trim() ??
        row['routeid']?.toString().trim() ??
        '';
    final cityId =
        row['city_id']?.toString().trim() ??
        row['cityid']?.toString().trim() ??
        row['cityids']?.toString().trim() ??
        row['cities']?.toString().trim() ??
        '';
    return {
      'visit_id': visitId.isEmpty ? '-' : visitId,
      'route_id': routeId.isEmpty ? '-' : routeId,
      'city_id': cityId.isEmpty ? '-' : cityId,
    };
  }

  Widget _buildStatusCard(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _isLoggedIn ? Colors.green : theme.colorScheme.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              _isLoggedIn ? Icons.verified_user : Icons.warning_amber_rounded,
              color: statusColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _isLoggedIn ? 'Login session found' : 'No active login session',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCredentialsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lock_outline),
                SizedBox(width: 8),
                Text(
                  'Saved Credentials',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const Divider(height: 20),
            _buildDataRow('Username', _savedUsername),
            _buildDataRow('Password', _savedPassword, obscured: !_showPassword),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _showPassword = !_showPassword;
                  });
                },
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                ),
                label: Text(_showPassword ? 'Hide Password' : 'Show Password'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(BuildContext context) {
    final user = _user;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.person_outline),
                SizedBox(width: 8),
                Text(
                  'User Data (saved after login)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const Divider(height: 20),
            if (user == null)
              const Text('No user data found.')
            else ...[
              _buildDataRow('ID', user.id.toString()),
              _buildDataRow('Employee ID', user.employeeid),
              _buildDataRow('Username', user.username),
              _buildDataRow('Email/Code', user.email),
              _buildDataRow('Role', user.role),
              _buildDataRow('Department', user.dept),
              _buildDataRow('Account', user.account),
              _buildDataRow('Store ID', user.storeid),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.settings_suggest_outlined),
                SizedBox(width: 8),
                Text(
                  'Session Values',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const Divider(height: 20),
            _buildDataRow('Legacy User ID', _userId?.toString()),
            _buildDataRow('Legacy Employee ID', _employeeId?.toString()),
            _buildDataRow('Static IP', _staticIp),
            _buildDataRow('User Account', _userAccount),
            _buildDataRow('User Rec ID', _userRecId),
            _buildDataRow('Data Update Date', _dataUpdateDate),
            _buildDataRow('Data Update ID', _dataUpdateId),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String? value, {bool obscured = false}) {
    final safeValue = (value == null || value.trim().isEmpty)
        ? '-'
        : value.trim();
    final shownValue = obscured ? ('*' * safeValue.length) : safeValue;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: SelectableText(
              shownValue,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
