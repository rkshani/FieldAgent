import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/invoice_item.dart';
import 'simple_card.dart';

class AddItemSection extends StatefulWidget {
  final Function(InvoiceItem) onAddItem;

  const AddItemSection({super.key, required this.onAddItem});

  @override
  State<AddItemSection> createState() => _AddItemSectionState();
}

class _AddItemSectionState extends State<AddItemSection>
    with SingleTickerProviderStateMixin {
  final List<String> _availableItems = [
    'Item A - ₹100',
    'Item B - ₹150',
    'Item C - ₹200',
    'Item D - ₹250',
  ];

  String? _selectedItem;
  int _quantity = 1;
  late AnimationController _addButtonController;

  @override
  void initState() {
    super.initState();
    _addButtonController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _addButtonController.dispose();
    super.dispose();
  }

  void _addItem() {
    if (_selectedItem == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select an item')));
      return;
    }

    final parts = _selectedItem!.split(' - ₹');
    final name = parts[0];
    final price = double.parse(parts[1]);

    final newItem = InvoiceItem(
      id: const Uuid().v4(),
      name: name,
      price: price,
      quantity: _quantity,
    );

    _addButtonController.forward().then((_) {
      _addButtonController.reverse();
    });

    widget.onAddItem(newItem);

    setState(() {
      _selectedItem = null;
      _quantity = 1;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name added (×$_quantity)'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return SimpleCard(
      padding: const EdgeInsets.all(16),
      child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add Item',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        _buildItemDropdown(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildQuantityInput()),
            const SizedBox(width: 12),
            _buildAddButton(),
          ],
        ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        Expanded(flex: 2, child: _buildItemDropdown()),
        const SizedBox(width: 12),
        Expanded(child: _buildQuantityInput()),
        const SizedBox(width: 12),
        _buildAddButton(),
      ],
    );
  }

  Widget _buildItemDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Item',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[900]
                : Colors.grey[50],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[800]!
                  : Colors.grey[200]!,
            ),
          ),
          child: DropdownButton<String>(
            value: _selectedItem,
            items: _availableItems
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: (val) => setState(() => _selectedItem = val),
            isExpanded: true,
            underline: const SizedBox(),
            hint: const Text('Select item...'),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildQuantityInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Qty',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: Colors.grey[600]),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[900]
                : Colors.grey[50],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[800]!
                  : Colors.grey[200]!,
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () =>
                    setState(() => _quantity = (_quantity - 1).clamp(1, 999)),
                icon: const Icon(Icons.remove),
                constraints: const BoxConstraints(minWidth: 40),
              ),
              Expanded(
                child: TextFormField(
                  initialValue: _quantity.toString(),
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(border: InputBorder.none),
                  onChanged: (val) =>
                      setState(() => _quantity = int.tryParse(val) ?? 1),
                ),
              ),
              IconButton(
                onPressed: () =>
                    setState(() => _quantity = (_quantity + 1).clamp(1, 999)),
                icon: const Icon(Icons.add),
                constraints: const BoxConstraints(minWidth: 40),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAddButton() {
    return ScaleTransition(
      scale: Tween<double>(begin: 1, end: 1.1).animate(
        CurvedAnimation(parent: _addButtonController, curve: Curves.easeInOut),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: FilledButton.icon(
          onPressed: _addItem,
          icon: const Icon(Icons.add_shopping_cart, size: 20),
          label: const Text('Add'),
        ),
      ),
    );
  }
}
