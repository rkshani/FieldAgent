import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/session_service.dart';

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
        _isLoading = false;
      });
    } catch (e) {
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
              ],
            ),
    );
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
            _buildDataRow(
              'Password',
              _savedPassword,
              obscured: !_showPassword,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _showPassword = !_showPassword;
                  });
                },
                icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
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
    final safeValue = (value == null || value.trim().isEmpty) ? '-' : value.trim();
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
