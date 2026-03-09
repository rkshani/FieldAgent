import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/local_db_service.dart';
import '../services/order_database_helper.dart';

class OrderTestingScreen extends StatefulWidget {
  const OrderTestingScreen({super.key});

  @override
  State<OrderTestingScreen> createState() => _OrderTestingScreenState();
}

class _OrderTestingScreenState extends State<OrderTestingScreen> {
  static const String _cacheKey = 'local_deliver_points';

  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _cacheRow;
  String _payloadPreview = '-';
  int _payloadLength = 0;

  List<Map<String, dynamic>> _deliveryPoints = [];
  int _parsedCount = 0;
  Map<String, dynamic>? _firstParsedItem;
  List<Map<String, String>> _stores = [];

  String _query = '';

  @override
  void initState() {
    super.initState();
    _runDeliveryPointsTest(refreshFirst: false);
  }

  Future<void> _runDeliveryPointsTest({required bool refreshFirst}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (refreshFirst) {
        debugPrint(
          '[OrderTesting] Refresh started via ApiService.fetchAndSaveLocalData()',
        );
        await ApiService.fetchAndSaveLocalData();
      }

      final cacheRow = await LocalDbService.instance.getCacheRow(_cacheKey);
      final cacheExists = cacheRow != null;
      final payload = cacheRow?['payload']?.toString() ?? '';
      final payloadLength = payload.length;
      final preview = payloadLength > 500 ? payload.substring(0, 500) : payload;

      debugPrint(
        '[OrderTesting] raw cache exists=$cacheExists for key=$_cacheKey',
      );
      debugPrint('[OrderTesting] payload length=$payloadLength');

      final points = await OrderDatabaseHelper.instance.getDeliveryPoints();
      debugPrint('[OrderTesting] parsed count=${points.length}');
      if (points.isNotEmpty) {
        debugPrint('[OrderTesting] first parsed item=${points.first}');
      } else {
        debugPrint('[OrderTesting] first parsed item=<none>');
      }

      final storeData = await OrderDatabaseHelper.instance.getStoreData();
      final stores = _extractStores(storeData);
      debugPrint('[OrderTesting] stores count=${stores.length}');
      if (stores.isNotEmpty) {
        debugPrint('[OrderTesting] first store=${stores.first}');
      } else {
        debugPrint('[OrderTesting] first store=<none>');
      }

      if (!mounted) return;

      setState(() {
        _cacheRow = cacheRow;
        _payloadLength = payloadLength;
        _payloadPreview = preview.isEmpty ? '-' : preview;
        _deliveryPoints = points;
        _parsedCount = points.length;
        _firstParsedItem = points.isNotEmpty ? points.first : null;
        _stores = stores;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to test delivery points: $e';
        _isLoading = false;
      });
    }
  }

  String _valueForKeys(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '-';
  }

  String _pointId(Map<String, dynamic> row) {
    return _valueForKeys(row, [
      'id',
      'store_id',
      'storeid',
      'delivery_point_id',
    ]);
  }

  String _storeId(Map<String, dynamic> row) {
    return _valueForKeys(row, ['storeid', 'store_id', 'id']);
  }

  String _storeName(Map<String, dynamic> row) {
    return _valueForKeys(row, ['storename', 'store_name', 'name']);
  }

  String _displayName(Map<String, dynamic> row) {
    return _valueForKeys(row, ['display_name', 'name', 'store_name']);
  }

  List<Map<String, String>> _extractStores(List<Map<String, dynamic>> rows) {
    final out = <Map<String, String>>[];
    final seen = <String>{};

    void addStore(Map<String, dynamic> map) {
      final storeId = _valueForKeys(map, ['store_id', 'storeid', 'id']);
      final storeName = _valueForKeys(map, ['store_name', 'storename', 'name']);
      if (storeName == '-') return;
      final key = '${storeId.toLowerCase()}|${storeName.toLowerCase()}';
      if (seen.contains(key)) return;
      seen.add(key);
      out.add({'store_id': storeId, 'store_name': storeName});
    }

    for (final row in rows) {
      if (row['stores'] is List) {
        final stores = row['stores'] as List;
        for (final s in stores) {
          if (s is Map) {
            addStore(Map<String, dynamic>.from(s));
          }
        }
      }
      addStore(row);
    }

    out.sort((a, b) {
      final an = a['store_name'] ?? '';
      final bn = b['store_name'] ?? '';
      return an.toLowerCase().compareTo(bn.toLowerCase());
    });
    return out;
  }

  List<Map<String, dynamic>> get _filteredPoints {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _deliveryPoints;

    return _deliveryPoints.where((row) {
      final haystack =
          '${_pointId(row)} ${_storeId(row)} ${_storeName(row)} ${_displayName(row)} ${row.keys.join(' ')} ${row.values.join(' ')}'
              .toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cacheExists = _cacheRow != null;
    final updatedAt = _cacheRow?['updated_at']?.toString() ?? '-';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Testing'),
        actions: [
          IconButton(
            onPressed: () => _runDeliveryPointsTest(refreshFirst: false),
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload Delivery Points',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_errorMessage!, textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              _runDeliveryPointsTest(refreshFirst: false),
                          icon: const Icon(Icons.bug_report_outlined),
                          label: const Text('Test Delivery Points'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              _runDeliveryPointsTest(refreshFirst: true),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh + Test Delivery Points'),
                        ),
                      ),
                    ],
                  ),
                ),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Delivery Points Debug Summary',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        _buildMetaRow(
                          'Cache Row Exists',
                          cacheExists ? 'Yes' : 'No',
                        ),
                        _buildMetaRow('Cache Updated At', updatedAt),
                        _buildMetaRow(
                          'Payload Length',
                          _payloadLength.toString(),
                        ),
                        _buildMetaRow(
                          'Parsed Delivery Points Count',
                          _parsedCount.toString(),
                        ),
                        _buildMetaRow(
                          'First Parsed Item',
                          _firstParsedItem == null
                              ? '-'
                              : _firstParsedItem.toString(),
                        ),
                        _buildMetaRow(
                          'Stores Count',
                          _stores.length.toString(),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Raw Payload Preview (first 500 chars):',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(_payloadPreview),
                      ],
                    ),
                  ),
                ),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'All Stores Names (from local_store_data)',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 150,
                          child: _stores.isEmpty
                              ? const Center(child: Text('No stores found.'))
                              : ListView.builder(
                                  itemCount: _stores.length,
                                  itemBuilder: (context, index) {
                                    final store = _stores[index];
                                    final storeId = store['store_id'] ?? '-';
                                    final storeName =
                                        store['store_name'] ?? '-';
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        '${index + 1}. $storeName (Store ID: $storeId)',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search parsed delivery points...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _query = value;
                      });
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Text(
                        'Parsed Total: ${_deliveryPoints.length}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Filtered: ${_filteredPoints.length}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (_filteredPoints.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text('No parsed delivery points found.'),
                    ),
                  )
                else
                  ..._filteredPoints.asMap().entries.map((entry) {
                    final index = entry.key;
                    final row = entry.value;
                    final id = _pointId(row);
                    final storeId = _storeId(row);
                    final storeName = _storeName(row);
                    final displayName = _displayName(row);

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${index + 1}. $displayName',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('id: $id'),
                            Text('storeid: $storeId'),
                            Text('storename: $storeName'),
                            Text('display_name: $displayName'),
                            Text('keys: ${row.keys.join(', ')}'),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
