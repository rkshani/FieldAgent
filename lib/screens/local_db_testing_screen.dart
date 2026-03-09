import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/local_db_service.dart';

class LocalDbTestingScreen extends StatefulWidget {
  const LocalDbTestingScreen({super.key});

  @override
  State<LocalDbTestingScreen> createState() => _LocalDbTestingScreenState();
}

class _LocalDbTestingScreenState extends State<LocalDbTestingScreen> {
  Map<String, List<Map<String, dynamic>>> _dbData = {};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAllDbData();
  }

  Future<void> _loadAllDbData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final db = await LocalDbService.instance.database;

      // Avoid reading full payload blobs in testing view to prevent CursorWindow overflow.
      final localApiCache = await db.rawQuery('''
        SELECT
          cache_key,
          LENGTH(payload) AS payload_size,
          SUBSTR(payload, 1, 400) AS payload_preview,
          updated_at
        FROM local_api_cache
        ORDER BY updated_at DESC
      ''');
      final draftOrders = await db.query('draft_orders');
      final draftOrderItems = await db.query('draft_order_items');

      setState(() {
        _dbData = {
          'local_api_cache': localApiCache,
          'draft_orders': draftOrders,
          'draft_order_items': draftOrderItems,
        };
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading database: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Local DB Testing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllDbData,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadAllDbData,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDatabaseSummary(theme),
                  const SizedBox(height: 20),
                  _buildTableSection(
                    theme,
                    'Local API Cache',
                    'local_api_cache',
                    Icons.cached,
                    Colors.blue,
                  ),
                  const SizedBox(height: 16),
                  _buildTableSection(
                    theme,
                    'Draft Orders',
                    'draft_orders',
                    Icons.shopping_cart,
                    Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  _buildTableSection(
                    theme,
                    'Draft Order Items',
                    'draft_order_items',
                    Icons.list,
                    Colors.green,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDatabaseSummary(ThemeData theme) {
    int totalRecords = 0;
    _dbData.forEach((table, records) {
      totalRecords += records.length;
    });

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Database Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            _buildSummaryRow('Total Tables', '${_dbData.keys.length}', theme),
            _buildSummaryRow('Total Records', '$totalRecords', theme),
            const SizedBox(height: 8),
            ...(_dbData.entries.map(
              (entry) => _buildSummaryRow(
                entry.key,
                '${entry.value.length} records',
                theme,
                isIndented: true,
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value,
    ThemeData theme, {
    bool isIndented = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: isIndented ? 16 : 0, top: 4, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isIndented ? 13 : 14,
              color: isIndented
                  ? theme.colorScheme.onSurface.withOpacity(0.7)
                  : theme.colorScheme.onSurface,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isIndented ? 13 : 14,
              fontWeight: isIndented ? FontWeight.normal : FontWeight.w600,
              color: isIndented
                  ? theme.colorScheme.onSurface.withOpacity(0.7)
                  : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableSection(
    ThemeData theme,
    String title,
    String tableName,
    IconData icon,
    Color color,
  ) {
    final records = _dbData[tableName] ?? [];

    return Card(
      elevation: 2,
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        subtitle: Text('${records.length} records'),
        children: [
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No data available',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            )
          else
            ...records.asMap().entries.map((entry) {
              final index = entry.key;
              final record = entry.value;
              return _buildRecordCard(theme, record, index + 1, tableName);
            }),
        ],
      ),
    );
  }

  Widget _buildRecordCard(
    ThemeData theme,
    Map<String, dynamic> record,
    int index,
    String tableName,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 1,
      child: ExpansionTile(
        title: Text(
          'Record #$index',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          _getRecordPreview(record, tableName),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...record.entries.map((entry) {
                  return _buildFieldRow(theme, entry.key, entry.value);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getRecordPreview(Map<String, dynamic> record, String tableName) {
    switch (tableName) {
      case 'local_api_cache':
        final key = record['cache_key']?.toString() ?? 'N/A';
        final bytes = record['payload_size']?.toString() ?? '0';
        return '$key ($bytes chars)';
      case 'draft_orders':
        return record['party_name']?.toString() ??
            record['local_order_id']?.toString() ??
            'Order #${record['id']}';
      case 'draft_order_items':
        return record['item_name']?.toString() ??
            'Item (Order #${record['draft_order_id']})';
      default:
        return 'Record #${record['id'] ?? '?'}';
    }
  }

  Widget _buildFieldRow(ThemeData theme, String key, dynamic value) {
    String displayValue;

    // Pretty-print JSON only when full payload is actually present.
    if (key == 'payload' && value is String) {
      try {
        final decoded = jsonDecode(value);
        displayValue = const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (e) {
        displayValue = value.toString();
      }
    } else {
      displayValue = value?.toString() ?? 'null';
    }

    // Truncate long values
    bool isLong = displayValue.length > 100;
    String previewValue = isLong
        ? '${displayValue.substring(0, 100)}...'
        : displayValue;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            key,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            previewValue,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (isLong)
            TextButton(
              onPressed: () {
                _showFullValueDialog(context, key, displayValue);
              },
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 30),
              ),
              child: const Text(
                'View Full Value',
                style: TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  void _showFullValueDialog(BuildContext context, String key, String value) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(key),
        content: SingleChildScrollView(
          child: SelectableText(
            value,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
