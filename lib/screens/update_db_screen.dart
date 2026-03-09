import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/order_database_helper.dart';

class UpdateDBScreen extends StatefulWidget {
  const UpdateDBScreen({super.key});

  @override
  State<UpdateDBScreen> createState() => _UpdateDBScreenState();
}

class _UpdateDBScreenState extends State<UpdateDBScreen> {
  static const Color _primaryColor = Color(0xFF2563EB);

  bool _isLoading = false;
  String _status = 'Tap the button to fetch API data and save to SQLite.';
  Map<String, int> _dataStats = {};
  Map<String, int> _localStats = {};
  bool _hasLoadedData = false;

  Future<void> _handleUpdateDb() async {
    setState(() {
      _isLoading = true;
      _status = 'Fetching data from server...';
      _dataStats = {};
    });

    final result = await ApiService.fetchAndSaveLocalData();

    if (!mounted) return;

    final success = result['success'] == true;

    if (success && result['stats'] != null) {
      _dataStats = Map<String, int>.from(result['stats'] as Map);
      await _loadLocalStats();
      _hasLoadedData = true;
    } else {
      await _loadLocalStats();
    }

    setState(() {
      _isLoading = false;
      _status = success
          ? 'Data loaded successfully!'
          : result['message']?.toString() ?? 'Failed to load data';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_status),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );

    final results = result['results'] as List<dynamic>? ?? [];
    if (results.isNotEmpty && mounted) {
      _showResultsDialog(results.cast<Map<String, dynamic>>(), success);
    }
  }

  Future<void> _loadLocalStats() async {
    try {
      final stats = await OrderDatabaseHelper.instance.getAllLocalStats();
      if (!mounted) return;
      setState(() => _localStats = stats);
    } catch (_) {}
  }

  void _showResultsDialog(List<Map<String, dynamic>> results, bool anySuccess) {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(
              anySuccess ? Icons.info_outline : Icons.warning_amber_rounded,
              color: _primaryColor,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Update DB Result',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Kitna data aaya / kis kis ka aaya:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              ...results.map((r) {
                final name = r['name'] as String? ?? 'Unknown';
                final ok = r['success'] == true;
                final count = r['count'] as int?;
                final err = r['error'] as String?;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        ok ? Icons.check_circle : Icons.cancel,
                        size: 22,
                        color: ok ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            if (ok && count != null)
                              Text(
                                '$count item(s) saved',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.hintColor,
                                ),
                              ),
                            if (!ok && err != null)
                              Text(
                                err,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red.shade700,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadLocalStats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Update Database'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: Colors.grey.shade100,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(
                        _hasLoadedData ? Icons.check_circle : Icons.info_outline,
                        size: 48,
                        color: _hasLoadedData ? Colors.green : _primaryColor,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _handleUpdateDb,
                          icon: _isLoading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.cloud_download),
                          label: Text(
                            _isLoading ? 'Loading...' : 'Update Database',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_hasLoadedData && _dataStats.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Last Update Results',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _buildDataStatsCard(),
              ],
              if (_localStats.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Local Database Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _buildLocalStatsCard(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataStatsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatRow(
              'Packages',
              _dataStats['packages'] ?? 0,
              Icons.inventory_2,
            ),
            const Divider(),
            _buildStatRow(
              'Items',
              _dataStats['items'] ?? 0,
              Icons.shopping_cart,
            ),
            const Divider(),
            _buildStatRow(
              'Package Details',
              _dataStats['package_details'] ?? 0,
              Icons.description,
            ),
            const Divider(),
            _buildStatRow(
              'Parties',
              _dataStats['parties'] ?? 0,
              Icons.people,
            ),
            const Divider(),
            _buildStatRow(
              'Delivery Points',
              _dataStats['delivery_points'] ?? 0,
              Icons.location_on,
            ),
            const Divider(),
            _buildStatRow(
              'Goods Agencies',
              _dataStats['goods_agencies'] ?? 0,
              Icons.business,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalStatsCard() {
    final total = _localStats.values.fold<int>(0, (sum, val) => sum + val);

    return Card(
      elevation: 2,
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Records',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  total.toString(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildStatRow(
              'Packages',
              _localStats['packages'] ?? 0,
              Icons.inventory_2,
            ),
            const SizedBox(height: 8),
            _buildStatRow(
              'Items',
              _localStats['items'] ?? 0,
              Icons.shopping_cart,
            ),
            const SizedBox(height: 8),
            _buildStatRow(
              'Package Details',
              _localStats['package_details'] ?? 0,
              Icons.description,
            ),
            const SizedBox(height: 8),
            _buildStatRow(
              'Delivery Points',
              _localStats['delivery_points'] ?? 0,
              Icons.location_on,
            ),
            const SizedBox(height: 8),
            _buildStatRow(
              'Parties',
              _localStats['parties'] ?? 0,
              Icons.people,
            ),
            const SizedBox(height: 8),
            _buildStatRow(
              'Goods Agencies',
              _localStats['goods_agencies'] ?? 0,
              Icons.business,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, int count, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: _primaryColor),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 15),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: count > 0 ? Colors.green : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              color: count > 0 ? Colors.white : Colors.grey.shade600,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
