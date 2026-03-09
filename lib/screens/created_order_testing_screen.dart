import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../services/draft_order_service.dart';

class CreatedOrderTestingScreen extends StatefulWidget {
  const CreatedOrderTestingScreen({super.key});

  @override
  State<CreatedOrderTestingScreen> createState() =>
      _CreatedOrderTestingScreenState();
}

class _CreatedOrderTestingScreenState extends State<CreatedOrderTestingScreen>
    with SingleTickerProviderStateMixin {
  static const Color _primary = Color(0xFF2563EB);

  late TabController _tabController;
  late Future<List<DraftOrderWithItems>> _offlineFuture;

  bool _onlineLoading = false;
  String? _onlineError;
  String? _onlineEndpoint;
  String? _onlineRaw;
  List<Map<String, dynamic>> _onlineOrders = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _offlineFuture = DraftOrderService.instance.getFinalizedOrders();
    _fetchOnlineOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _reloadOffline() async {
    setState(() {
      _offlineFuture = DraftOrderService.instance.getFinalizedOrders();
    });
  }

  Future<void> _fetchOnlineOrders() async {
    setState(() {
      _onlineLoading = true;
      _onlineError = null;
    });

    final result = await ApiService.fetchOnlineCreatedOrdersForTesting();
    if (!mounted) return;

    setState(() {
      _onlineLoading = false;
      _onlineEndpoint = result['endpoint']?.toString();
      _onlineRaw = result['raw']?.toString();
      _onlineOrders =
          (result['orders'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      if (result['success'] != true) {
        _onlineError = result['message']?.toString() ?? 'Failed to fetch';
      }
    });
  }

  void _openOfflineDetail(DraftOrderWithItems draft) {
    final order = draft.order;
    final payload = {
      'source': 'offline',
      'order': order.toMap(),
      'items': draft.items.map((e) => e.toMap()).toList(),
      'summary': {
        'gross': draft.grossAmount,
        'discount': draft.totalDiscount,
        'net': draft.netAmount,
      },
    };
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreatedOrderRecordDetailScreen(
          title: 'Offline Order ${order.orderSerialNo ?? order.id}',
          payload: payload,
        ),
      ),
    );
  }

  void _openOnlineDetail(Map<String, dynamic> order) {
    final id =
        order['id']?.toString() ??
        order['order_id']?.toString() ??
        order['local_order_id']?.toString() ??
        '-';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreatedOrderRecordDetailScreen(
          title: 'Online Order $id',
          payload: order,
        ),
      ),
    );
  }

  String _displayOnlineOrderTitle(Map<String, dynamic> m) {
    final party =
        m['party_name']?.toString().trim() ??
        m['PartyName']?.toString().trim() ??
        m['party']?.toString().trim() ??
        '';
    if (party.isNotEmpty) return party;
    return m['order_id']?.toString() ?? m['id']?.toString() ?? 'Online Order';
  }

  String _displayOnlineOrderSubtitle(Map<String, dynamic> m) {
    final id =
        m['order_id']?.toString() ??
        m['id']?.toString() ??
        m['local_order_id']?.toString() ??
        '-';
    final date =
        m['created_at']?.toString() ??
        m['date']?.toString() ??
        m['timestamp']?.toString() ??
        '';
    if (date.isEmpty) return 'ID: $id';
    return 'ID: $id | $date';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _primary,
        title: const Text(
          'Created Order Testing',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          tabs: const [
            Tab(text: 'Offline'),
            Tab(text: 'Online'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () async {
              await _reloadOffline();
              await _fetchOnlineOrders();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          FutureBuilder<List<DraftOrderWithItems>>(
            future: _offlineFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text('Offline load failed: ${snapshot.error}'),
                );
              }
              final orders = snapshot.data ?? const <DraftOrderWithItems>[];
              if (orders.isEmpty) {
                return const Center(child: Text('No offline finalized orders'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: orders.length,
                itemBuilder: (context, index) {
                  final d = orders[index];
                  final o = d.order;
                  final title = (o.partyName ?? '').trim().isEmpty
                      ? 'Order ${o.orderSerialNo ?? o.id}'
                      : o.partyName!.trim();
                  final date = DateTime.tryParse(o.createdAt);
                  final dateText = date == null
                      ? o.createdAt
                      : DateFormat('dd MMM yyyy, hh:mm a').format(date);

                  return Card(
                    child: ListTile(
                      title: Text(title),
                      subtitle: Text(
                        'ID: ${o.orderSerialNo ?? o.id} | $dateText',
                      ),
                      trailing: Text('Rs ${d.netAmount.toStringAsFixed(1)}'),
                      onTap: () => _openOfflineDetail(d),
                    ),
                  );
                },
              );
            },
          ),
          Column(
            children: [
              if (_onlineEndpoint != null)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    'Endpoint: $_onlineEndpoint',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
              if (_onlineError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    _onlineError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              Expanded(
                child: _onlineLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _onlineOrders.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _onlineRaw == null
                                ? 'No online orders found'
                                : 'No online orders parsed. Open details from raw preview if needed.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _onlineOrders.length,
                        itemBuilder: (context, index) {
                          final row = _onlineOrders[index];
                          return Card(
                            child: ListTile(
                              title: Text(_displayOnlineOrderTitle(row)),
                              subtitle: Text(_displayOnlineOrderSubtitle(row)),
                              onTap: () => _openOnlineDetail(row),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CreatedOrderRecordDetailScreen extends StatelessWidget {
  final String title;
  final Map<String, dynamic> payload;

  const CreatedOrderRecordDetailScreen({
    super.key,
    required this.title,
    required this.payload,
  });

  @override
  Widget build(BuildContext context) {
    final pretty = const JsonEncoder.withIndent('  ').convert(payload);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(pretty),
            ),
          ),
        ],
      ),
    );
  }
}
