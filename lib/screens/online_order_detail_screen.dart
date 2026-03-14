import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class OnlineOrderDetailScreen extends StatelessWidget {
  final Map<String, dynamic> order;

  const OnlineOrderDetailScreen({super.key, required this.order});

  String _safe(dynamic v) {
    if (v == null) return '-';
    final s = v.toString().trim();
    return s.isEmpty ? '-' : s;
  }

  String _pick(
    Map<String, dynamic> src,
    List<String> keys, {
    String fallback = '-',
  }) {
    for (final key in keys) {
      final v = src[key];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return fallback;
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim()) ?? 0;
  }

  String get _orderId =>
      order['order_id']?.toString() ?? order['id']?.toString() ?? '-';

  String get _date {
    final raw =
        order['invdate']?.toString() ??
        order['created_at']?.toString() ??
        order['date']?.toString() ??
        '';
    if (raw.isEmpty) return '-';
    try {
      final dt = DateTime.parse(raw);
      return DateFormat('yyyy-MM-dd').format(dt);
    } catch (_) {
      if (raw.contains(' ')) return raw.split(' ').first;
      return raw;
    }
  }

  String get _party => order['party_name']?.toString().trim().isNotEmpty == true
      ? order['party_name'].toString().trim()
      : order['PartyName']?.toString().trim().isNotEmpty == true
      ? order['PartyName'].toString().trim()
      : order['party']?.toString().trim().isNotEmpty == true
      ? order['party'].toString().trim()
      : '-';

  String get _status => order['status']?.toString().trim().isNotEmpty == true
      ? _mapBookingStatus(order['status'].toString().trim())
      : order['order_status']?.toString().trim().isNotEmpty == true
      ? _mapBookingStatus(order['order_status'].toString().trim())
      : order['booking_status']?.toString().trim().isNotEmpty == true
      ? _mapBookingStatus(order['booking_status'].toString().trim())
      : 'Outstanding';

  String _mapBookingStatus(String raw) {
    switch (raw.trim()) {
      case '1':
        return 'Outstanding';
      case '2':
        return 'Pending';
      case '3':
        return 'Cancelled';
      case '5':
        return 'Approved';
      case '6':
        return 'Reorder';
      case '7':
        return 'Items Picked';
      case '8':
        return 'Items Checked';
      case '9':
        return 'Items Packed';
      case '10':
        return 'Packets Info Added';
      case '11':
        return 'Loaded to Truck';
      case '12':
        return 'Completed';
      default:
        return raw;
    }
  }

  List<Map<String, dynamic>> get _items {
    for (final key in const [
      'items',
      'booking_items',
      'order_items',
      'details',
    ]) {
      final v = order[key];
      if (v is List && v.isNotEmpty) {
        return v
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final scheme = Theme.of(context).colorScheme;

    final packageName = _pick(order, const [
      'package_name',
      'packageid',
      'package_id',
      'PackageName',
    ]);
    final deliveryPoint = _pick(order, const [
      'delivery_point',
      'deliverypoint',
      'delivery_point_name',
      'deliver_point',
      'store_name',
    ]);
    final deliveryParty = _pick(order, const [
      'delivery_party_name',
      'deliveryparty',
      'delivery_party',
      'party_delivery',
    ]);
    final remarks = _pick(order, const [
      'order_remarks',
      'remarks',
      'remark',
      'special_remarks',
    ]);
    final orderBy = _pick(order, const [
      'order_by',
      'username',
      'created_by',
      'employeeid',
      'employee_id',
    ]);

    final gross = _toDouble(
      order['gross_total'] ?? order['gross'] ?? order['amount'],
    );
    final discount = _toDouble(order['discount'] ?? order['discount_amount']);
    final net = _toDouble(
      order['net_total'] ?? order['net'] ?? order['total'] ?? order['amount'],
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.primary,
        iconTheme: IconThemeData(color: scheme.onPrimary),
        title: Text(
          'Order #$_orderId',
          style: TextStyle(
            color: scheme.onPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(
                child: _headerCell(
                  context,
                  label: 'DATE AND TIME :',
                  value: _date,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _headerCell(context, label: 'ID :', value: _orderId),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _detailRow('Party Name', _party),
          _detailRow('Package Name', packageName),
          _detailRow('Delivery Point', deliveryPoint),
          _detailRow('Delivery Party', deliveryParty),
          _detailRow('Order Remarks', remarks),
          _detailRow('Order By', orderBy),
          _detailRow('Status', _status),

          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Text(
              items.isEmpty
                  ? 'No item rows received in this API response'
                  : 'Items',
              style: TextStyle(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      'ITEM CODE',
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'PRICE',
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      'QTY',
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '%AGE',
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'TOTAL',
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
            ...items.map((item) {
              final name =
                  item['item_name']?.toString() ??
                  item['name']?.toString() ??
                  item['itemname']?.toString() ??
                  item['item_code']?.toString() ??
                  item['itemid']?.toString() ??
                  '-';
              final price =
                  item['rate']?.toString() ??
                  item['unit_price']?.toString() ??
                  item['price']?.toString() ??
                  '-';
              final qty =
                  item['qty']?.toString() ??
                  item['quantity']?.toString() ??
                  '-';
              final total =
                  item['total']?.toString() ??
                  item['amount']?.toString() ??
                  item['subtotal']?.toString() ??
                  '-';
              final percent =
                  item['percent']?.toString() ??
                  item['discount_percent']?.toString() ??
                  item['discount']?.toString() ??
                  '0';

              return Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.primary.withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(name, style: const TextStyle(fontSize: 12)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        price,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        qty,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        percent,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        total,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],

          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Gross Amount',
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Discount',
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Net Amount',
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Theme.of(context).cardColor,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    gross.toStringAsFixed(1),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '-${discount.toStringAsFixed(1)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    net.toStringAsFixed(1),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.only(bottom: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x33000000))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Text(
                _safe(value),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
