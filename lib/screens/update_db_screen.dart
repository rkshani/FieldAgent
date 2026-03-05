import 'package:flutter/material.dart';

import '../services/api_service.dart';

class UpdateDBScreen extends StatefulWidget {
  const UpdateDBScreen({super.key});

  @override
  State<UpdateDBScreen> createState() => _UpdateDBScreenState();
}

class _UpdateDBScreenState extends State<UpdateDBScreen> {
  static const Color _primaryColor = Color(0xFF2563EB);

  bool _isLoading = false;
  String _status = 'Tap the button to load data from API and save to device.';

  Future<void> _handleUpdateDb() async {
    setState(() {
      _isLoading = true;
      _status = 'Loading data from API...';
    });

    final result = await ApiService.fetchAndSaveLocalData();

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _status = result['message']?.toString() ?? 'Done.';
    });

    final success = result['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_status),
        backgroundColor: success ? Colors.green : Colors.orange,
      ),
    );

    final results = result['results'] as List<dynamic>? ?? [];
    if (results.isNotEmpty && mounted) {
      _showResultsDialog(results.cast<Map<String, dynamic>>(), success);
    }
  }

  void _showResultsDialog(List<Map<String, dynamic>> results, bool anySuccess) {
    final theme = Theme.of(context);
    showDialog(
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Update Database'),
        backgroundColor: _primaryColor,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _status,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _handleUpdateDb,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.download),
                label: Text(_isLoading ? 'Please wait...' : 'Update DB'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
