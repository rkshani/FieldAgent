import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/invoice_item.dart';
import 'simple_card.dart';

class ItemsListSection extends StatelessWidget {
  final List<InvoiceItem> items;
  final Function(String) onRemoveItem;
  final Function(String, InvoiceItem) onUpdateItem;

  const ItemsListSection({
    super.key,
    required this.items,
    required this.onRemoveItem,
    required this.onUpdateItem,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return SimpleCard(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.shopping_cart_outlined,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 12),
              Text(
                'No items added',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (ctx, index) => ItemCard(
        item: items[index],
        onRemove: () => onRemoveItem(items[index].id),
        onUpdate: (updatedItem) => onUpdateItem(items[index].id, updatedItem),
      ),
    );
  }
}

class ItemCard extends StatelessWidget {
  final InvoiceItem item;
  final VoidCallback onRemove;
  final Function(InvoiceItem) onUpdate;

  const ItemCard({
    super.key,
    required this.item,
    required this.onRemove,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat('#,##0.00');

    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.red[500],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: SimpleCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '₹${currencyFormatter.format(item.total)}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildDetailColumn(
                  context,
                  'Price',
                  '₹${currencyFormatter.format(item.price)}',
                ),
                const SizedBox(width: 12),
                _buildDetailColumn(
                  context,
                  'Qty',
                  '${item.quantity}',
                  editable: true,
                  onEdit: () => _showQuantityEditor(context),
                ),
                const SizedBox(width: 12),
                _buildDetailColumn(
                  context,
                  'Discount',
                  '${item.discountPercent.toStringAsFixed(1)}%',
                  editable: true,
                  onEdit: () => _showDiscountEditor(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailColumn(
    BuildContext context,
    String label,
    String value, {
    bool editable = false,
    VoidCallback? onEdit,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: editable ? onEdit : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (editable) ...[
              const SizedBox(height: 4),
              Icon(Icons.edit, size: 14, color: Colors.grey[500]),
            ],
          ],
        ),
      ),
    );
  }

  void _showQuantityEditor(BuildContext context) {
    final controller = TextEditingController(text: item.quantity.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Quantity'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Enter quantity',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final qty = int.tryParse(controller.text) ?? 1;
              onUpdate(item.copyWith(quantity: qty));
              Navigator.pop(ctx);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showDiscountEditor(BuildContext context) {
    final controller = TextEditingController(
      text: item.discountPercent.toString(),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Discount %'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Enter discount %',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final discount = double.tryParse(controller.text) ?? 0;
              onUpdate(item.copyWith(discountPercent: discount));
              Navigator.pop(ctx);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }
}
