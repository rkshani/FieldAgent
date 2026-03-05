import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/invoice_provider.dart';
import '../widgets/add_item_section.dart';
import '../widgets/items_list_section.dart';
import '../widgets/order_info_card.dart';
import '../widgets/summary_section.dart';
import 'orders_screen.dart';

class InvoiceScreen extends StatefulWidget {
  const InvoiceScreen({super.key});

  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen>
    with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _fabController;
  bool _showFab = true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _fabController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _fabController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    // Simplified scroll handling
    if (_scrollController.offset > 100 && _showFab) {
      _showFab = false;
      _fabController.reverse();
    } else if (_scrollController.offset <= 100 && !_showFab) {
      _showFab = true;
      _fabController.forward();
    }
  }

  void _showFinalizationDialog(BuildContext context) {
    final provider = context.read<InvoiceProvider>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalize Invoice'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to finalize this invoice?'),
            const SizedBox(height: 16),
            Text(
              'Net Amount: â‚¹${provider.netAmount.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final success = provider.finalize();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? 'Invoice finalized successfully!'
                        : 'Cannot finalize an empty order. Add items first.',
                  ),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Finalize'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice / POS'),
        actions: [
          IconButton(
            tooltip: 'All Orders',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const OrdersScreen())),
            icon: const Icon(Icons.list_alt),
          ),
        ],
        centerTitle: true,
        elevation: 2,
      ),
      body: Consumer<InvoiceProvider>(
        builder: (ctx, provider, _) {
          return Stack(
            children: [
              SingleChildScrollView(
                controller: _scrollController,
                padding: EdgeInsets.only(
                  left: isMobile ? 16 : 24,
                  right: isMobile ? 16 : 24,
                  top: 16,
                  bottom: 140,
                ),
                child: Column(
                  children: [
                    // Order Info Card
                    OrderInfoCard(
                      visitNumber: provider.invoice.visitNumber,
                      partyName: provider.invoice.partyName,
                      goodsAgency: provider.invoice.goodsAgency,
                      deliveryAddress: provider.invoice.deliveryAddress,
                      date: provider.invoice.date,
                      onUpdate: (party, agency, address) {
                        provider.updateInvoiceInfo(
                          partyName: party,
                          goodsAgency: agency,
                          deliveryAddress: address,
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    // Add Item Section
                    AddItemSection(onAddItem: (item) => provider.addItem(item)),
                    const SizedBox(height: 20),
                    // Items List
                    ItemsListSection(
                      items: provider.items,
                      onRemoveItem: (id) => provider.removeItem(id),
                      onUpdateItem: (id, item) => provider.updateItem(id, item),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              // Summary Section (Fixed Bottom)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SummarySection(
                  grossAmount: provider.grossAmount,
                  discount: provider.totalDiscount,
                  netAmount: provider.netAmount,
                ),
              ),
              // Bottom Action Buttons
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => provider.reset(),
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: provider.items.isEmpty
                              ? null
                              : () => _showFinalizationDialog(context),
                          icon: const Icon(Icons.check_circle),
                          label: const Text('Finalize'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

