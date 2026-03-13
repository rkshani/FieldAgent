import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../services/draft_order_service.dart';
import '../services/sync_service.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  static const Color _primary = Color(0xFF2563EB);

  late TabController _tabController;
  late Future<List<DraftOrderWithItems>> _offlineFuture;

  bool _onlineLoading = false;
  bool _uploading = false;
  String? _onlineError;
  String? _onlineEndpoint;
  List<Map<String, dynamic>> _onlineOrders = [];
  int _pendingUploadCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _offlineFuture = DraftOrderService.instance.getFinalizedOrders();
    _refreshAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshOffline() async {
    setState(() {
      _offlineFuture = DraftOrderService.instance.getFinalizedOrders();
    });
  }

  Future<void> _refreshPendingCount() async {
    final count = await DraftOrderService.instance.getPendingBookingsCount();
    if (!mounted) return;
    setState(() => _pendingUploadCount = count);
  }

  Future<void> _fetchOnlineOrders() async {
    setState(() {
      _onlineLoading = true;
      _onlineError = null;
    });

    final result = await ApiService.fetchMyOrders();
    if (!mounted) return;

    setState(() {
      _onlineLoading = false;
      _onlineEndpoint = result['endpoint']?.toString();
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

  Future<void> _refreshAll() async {
    await _refreshOffline();
    await _refreshPendingCount();
    await _fetchOnlineOrders();
  }

  Future<void> _uploadPendingOrders(List<Map<String, dynamic>> pending) async {
    if (_uploading) return;
    if (pending.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pending offline orders to upload.')),
      );
      return;
    }

    setState(() => _uploading = true);

    var success = 0;
    var failed = 0;
    final outputs = <Map<String, dynamic>>[];

    for (final booking in pending) {
      final bookingId = booking['id'] as int?;
      if (bookingId == null) {
        failed++;
        continue;
      }

      final result = await SyncService.instance.uploadBookingWithResult(
        bookingId,
      );
      outputs.add(result.toMap());

      final ok = result.success;
      if (ok) {
        await DraftOrderService.instance.markBookingUploaded(bookingId);
        final draftIdRaw = booking['draft_order_id'];
        int? draftId;
        if (draftIdRaw is int) {
          draftId = draftIdRaw;
        } else if (draftIdRaw is num) {
          draftId = draftIdRaw.toInt();
        } else if (draftIdRaw != null) {
          draftId = int.tryParse(draftIdRaw.toString());
        }

        if (draftId != null) {
          await DraftOrderService.instance.markUploadSuccess(
            draftId,
            clearItems: true,
          );
        }
        success++;
      } else {
        failed++;
      }
    }

    if (!mounted) return;
    setState(() => _uploading = false);

    await _refreshAll();

    final msg = failed == 0
        ? 'Uploaded $success order(s) successfully.'
        : 'Uploaded $success, failed $failed order(s).';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: failed == 0 ? Colors.green : Colors.orange,
      ),
    );

    if (!mounted) return;
    await _showUploadOutputDialog(outputs, success: success, failed: failed);
  }

  Future<void> _showUploadOutputDialog(
    List<Map<String, dynamic>> outputs, {
    required int success,
    required int failed,
  }) async {
    final jsonText = const JsonEncoder.withIndent('  ').convert({
      'summary': {
        'success': success,
        'failed': failed,
        'total': success + failed,
      },
      'final_output': outputs,
    });

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Upload Final Output'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(child: SelectableText(jsonText)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showUploadPreviewAndConfirm() async {
    if (_uploading) return;

    final pending = await DraftOrderService.instance.getPendingBookings();
    if (pending.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pending offline orders to upload.')),
      );
      return;
    }

    final previews = <Map<String, dynamic>>[];
    for (final booking in pending) {
      final bookingId = booking['id'] as int?;
      if (bookingId == null) continue;
      final preview = await SyncService.instance.getUploadPreviewForBooking(
        bookingId,
      );
      if (preview != null) {
        previews.add(preview);
      }
    }

    if (!mounted) return;

    final previewJson = const JsonEncoder.withIndent(
      '  ',
    ).convert({'pending_count': pending.length, 'uploads': previews});

    final shouldUpload =
        await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: const Text('Upload Preview'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: SelectableText(previewJson),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  icon: const Icon(Icons.cloud_upload),
                  label: Text('Upload (${pending.length})'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!shouldUpload) return;
    await _uploadPendingOrders(pending);
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
    final amount =
        m['net_total']?.toString() ??
        m['total']?.toString() ??
        m['amount']?.toString() ??
        '';
    final amountText = amount.isNotEmpty ? ' | Rs $amount' : '';
    if (date.isEmpty) return 'ID: $id$amountText';
    return 'ID: $id | $date$amountText';
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'My Orders',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
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
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh',
          ),
          TextButton.icon(
            onPressed: _uploading ? null : _showUploadPreviewAndConfirm,
            icon: _uploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload, color: Colors.white, size: 18),
            label: Text(
              'Upload ($_pendingUploadCount)',
              style: const TextStyle(color: Colors.white),
            ),
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

              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: orders.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final d = orders[i];
                  final order = d.order;
                  final title = (order.partyName ?? '').trim().isEmpty
                      ? 'Order ${order.orderSerialNo ?? order.id}'
                      : order.partyName!.trim();
                  final createdAt = DateTime.tryParse(order.createdAt);
                  final dateText = createdAt == null
                      ? order.createdAt
                      : DateFormat('dd MMM yyyy, hh:mm a').format(createdAt);

                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: [_primary.withOpacity(0.10), Colors.white],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: _primary.withOpacity(0.20)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      title: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'ID: ${order.orderSerialNo ?? order.id} | $dateText\nItems: ${d.items.length}',
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Rs ${currency.format(d.netAmount)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: order.isUploaded
                                  ? Colors.green.withOpacity(0.15)
                                  : Colors.orange.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              order.isUploaded ? 'UPLOADED' : 'OFFLINE',
                              style: TextStyle(
                                color: order.isUploaded
                                    ? Colors.green
                                    : Colors.orange.shade800,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => OrderDetailScreen(draft: d),
                          ),
                        );
                      },
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
                    ? const Center(child: Text('No online orders found'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _onlineOrders.length,
                        itemBuilder: (context, index) {
                          final row = _onlineOrders[index];
                          return Card(
                            child: ListTile(
                              title: Text(_displayOnlineOrderTitle(row)),
                              subtitle: Text(_displayOnlineOrderSubtitle(row)),
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
