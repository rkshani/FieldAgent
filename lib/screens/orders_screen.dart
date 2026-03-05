import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../providers/invoice_provider.dart';
import '../models/invoice.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InvoiceProvider>();
    final invoices = provider.savedInvoices.reversed
        .toList(); // show latest first
    final currency = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(title: const Text('All Orders')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: invoices.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.receipt_long, size: 56, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('No orders yet', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
            : ListView.separated(
                itemCount: invoices.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (ctx, i) {
                  final inv = invoices[i];
                  return Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      title: Text(
                        inv.partyName.isEmpty ? inv.visitNumber : inv.partyName,
                      ),
                      subtitle: Text(
                        DateFormat('dd MMM yyyy, hh:mm a').format(inv.date),
                      ),
                      trailing: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'â‚¹${currency.format(inv.netAmount)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          _statusChip(inv.status),
                        ],
                      ),
                      onTap: () {
                        // Optionally show order details
                        showDialog(
                          context: context,
                          builder: (dialogCtx) => AlertDialog(
                            title: Text('Order ${inv.visitNumber}'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: inv.items
                                  .map(
                                    (it) => Text(
                                      '${it.name} Ã—${it.quantity} = â‚¹${it.total.toStringAsFixed(2)}',
                                    ),
                                  )
                                  .toList(),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogCtx),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _statusChip(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.finalized:
        return Chip(
          label: const Text('Finalized'),
          backgroundColor: Colors.green[100],
        );
      case InvoiceStatus.delivered:
        return Chip(
          label: const Text('Delivered'),
          backgroundColor: Colors.blue[100],
        );
      case InvoiceStatus.cancelled:
        return Chip(
          label: const Text('Cancelled'),
          backgroundColor: Colors.red[100],
        );
      default:
        return Chip(
          label: const Text('Draft'),
          backgroundColor: Colors.grey[200],
        );
    }
  }
}

