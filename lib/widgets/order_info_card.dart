import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'simple_card.dart';

class OrderInfoCard extends StatelessWidget {
  final String visitNumber;
  final String partyName;
  final String goodsAgency;
  final String deliveryAddress;
  final DateTime date;
  final Function(String, String, String) onUpdate;

  const OrderInfoCard({
    super.key,
    required this.visitNumber,
    required this.partyName,
    required this.goodsAgency,
    required this.deliveryAddress,
    required this.date,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return SimpleCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Visit #',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      visitNumber,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Date',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('dd MMM yyyy').format(date),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoField(
            label: 'Party Name',
            value: partyName,
            onTap: () =>
                _showEditDialog(context, 'Party Name', partyName, (val) {
                  onUpdate(val, goodsAgency, deliveryAddress);
                }),
          ),
          const SizedBox(height: 12),
          _DropdownField(
            label: 'Goods Agency',
            value: goodsAgency,
            items: ['Agency 1', 'Agency 2', 'Agency 3'],
            onChanged: (val) {
              onUpdate(partyName, val, deliveryAddress);
            },
          ),
          const SizedBox(height: 12),
          _InfoField(
            label: 'Delivery Address',
            value: deliveryAddress,
            maxLines: 2,
            onTap: () => _showEditDialog(
              context,
              'Delivery Address',
              deliveryAddress,
              (val) {
                onUpdate(partyName, goodsAgency, val);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    String title,
    String initial,
    Function(String) onSave,
  ) {
    final controller = TextEditingController(text: initial);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit $title'),
        content: TextField(
          controller: controller,
          maxLines: title == 'Delivery Address' ? 3 : 1,
          decoration: InputDecoration(
            hintText: 'Enter $title',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              onSave(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _InfoField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final int maxLines;

  const _InfoField({
    required this.label,
    required this.value,
    required this.onTap,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.edit, size: 16, color: Colors.grey[500]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final Function(String) onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: DropdownButton<String>(
            value: value,
            items: items
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: (val) => onChanged(val ?? value),
            isExpanded: true,
            underline: const SizedBox(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
      ],
    );
  }
}
