import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/invoice_provider.dart';
import '../models/invoice_item.dart';
import '../services/session_service.dart';

class OrderAddScreen extends StatefulWidget {
  const OrderAddScreen({super.key});

  @override
  State<OrderAddScreen> createState() => _OrderAddScreenState();
}

class _OrderAddScreenState extends State<OrderAddScreen> {
  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _specialRemarksController = TextEditingController();
  final TextEditingController _specialPriceController = TextEditingController();
  final TextEditingController _deliveryAddressController = TextEditingController();
  
  String? _selectedItem;
  String? _selectedVisit;
  String _selectedParty = 'AL SHAMS BOOK CENTRE DARGAI';
  String _selectedAgency = 'select agency';
  String _selectedPackage = 'Regular Package';
  String _selectedDeliveryPoint = 'Select Via Delivery Point';
  int _paymentDeal = 0;
  String _userId = '1013_zeeshanjaved';
  int _orderId = 2;

  @override
  void initState() {
    super.initState();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final userId = await SessionService.getUserId();
    if (userId != null) {
      setState(() {
        _userId = '${userId}_user';
      });
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _specialRemarksController.dispose();
    _specialPriceController.dispose();
    _deliveryAddressController.dispose();
    super.dispose();
  }

  void _addItem() {
    if (_selectedItem == null || _qtyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select item and enter quantity')),
      );
      return;
    }

    final provider = context.read<InvoiceProvider>();
    // Mock item data - replace with actual item lookup
    final item = InvoiceItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _selectedItem!,
      price: 95.0,
      quantity: int.tryParse(_qtyController.text) ?? 1,
      discountPercent: 10.0,
    );

    provider.addItem(item);
    _qtyController.clear();
    setState(() {
      _selectedItem = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8F5E9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B7B4C),
        elevation: 0,
        title: const Text(
          'Add New Order',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildTopSection(),
            _buildItemEntrySection(),
            _buildOrderDetailsSection(),
            _buildItemsListSection(),
            _buildSummarySection(),
            _buildBottomActionsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSection() {
    return Container(
      color: const Color(0xFF2E7D32),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildFieldRow(
            'Visit:',
            DropdownButton<String>(
              value: _selectedVisit,
              hint: const Text(
                'Select Visit',
                style: TextStyle(color: Colors.white),
              ),
              isExpanded: true,
              dropdownColor: const Color(0xFF1B7B4C),
              style: const TextStyle(color: Colors.white),
              underline: Container(),
              items: ['Visit 1', 'Visit 2', 'Visit 3']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (val) => setState(() => _selectedVisit = val),
            ),
          ),
          const SizedBox(height: 8),
          _buildFieldRow(
            'Party :',
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _selectedParty,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildFieldRow(
            'Goods\nAgency :',
            DropdownButton<String>(
              value: _selectedAgency,
              isExpanded: true,
              dropdownColor: const Color(0xFF1B7B4C),
              style: const TextStyle(color: Colors.white),
              underline: Container(),
              items: ['select agency', 'Agency 1', 'Agency 2']
                  .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                  .toList(),
              onChanged: (val) => setState(() => _selectedAgency = val!),
            ),
          ),
          const SizedBox(height: 8),
          _buildFieldRow(
            'Delivery\nAddress:',
            TextField(
              controller: _deliveryAddressController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white70),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildFieldRow(
            'Package :',
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _selectedPackage,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildFieldRow(
            'Payment\nDeal :',
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _paymentDeal.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldRow(String label, Widget field) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: field),
      ],
    );
  }

  Widget _buildItemEntrySection() {
    return Container(
      color: const Color(0xFFC5E1A5),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedItem,
                    hint: const Text('Search Item'),
                    isExpanded: true,
                    underline: Container(),
                    items: [
                      '46_Majmua e Wazaif (Translation Urdu)@_47_3',
                      '131_Kamil Nimaz(Farsi)@_42_3',
                      'Item 3',
                      'Item 4',
                    ]
                        .map((i) => DropdownMenuItem(value: i, child: Text(i)))
                        .toList(),
                    onChanged: (val) => setState(() => _selectedItem = val),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _qtyController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: 'QTY',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                      borderRadius: BorderRadius.zero,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addItem,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B7B4C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                child: const Text(
                  'ADD',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _specialRemarksController,
                  decoration: InputDecoration(
                    hintText: 'Special Remarks',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                      borderRadius: BorderRadius.zero,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),
              Container(
                width: 2,
                height: 48,
                color: Colors.grey,
              ),
              Expanded(
                child: TextField(
                  controller: _specialPriceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Special Price',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                      borderRadius: BorderRadius.zero,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderDetailsSection() {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);

    return Container(
      color: const Color(0xFFC5E1A5),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1B7B4C),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Date : $dateStr',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1B7B4C),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'ID : $_orderId',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsListSection() {
    return Consumer<InvoiceProvider>(
      builder: (context, provider, child) {
        if (provider.items.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(32),
            child: const Text(
              'No items added yet',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF1B7B4C), width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            children: [
              Container(
                color: const Color(0xFF1B7B4C),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        'ITEM NAME',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'PRICE',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'QTY',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '%age',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'TOTAL',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
              ...provider.items.map((item) => Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC5E1A5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF1B7B4C)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            item.name,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            item.price.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            item.quantity.toString(),
                            style: const TextStyle(fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            item.discountPercent.toStringAsFixed(0),
                            style: const TextStyle(fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                item.subtotal.toStringAsFixed(0),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '(_${item.discountAmount.toStringAsFixed(0)})',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummarySection() {
    return Consumer<InvoiceProvider>(
      builder: (context, provider, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B7B4C),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Gross Amount',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Discount',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Net Amount',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFF1B7B4C)),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      provider.grossAmount.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '-${provider.totalDiscount.toStringAsFixed(1)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    Text(
                      provider.netAmount.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomActionsSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    _userId,
                    style: const TextStyle(fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    // Add remarks dialog
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(12),
                    side: const BorderSide(color: Colors.grey),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text(
                    'Want to add Remarks?',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Delivery:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedDeliveryPoint,
                    isExpanded: true,
                    underline: Container(),
                    items: [
                      'Select Via Delivery Point',
                      'Point 1',
                      'Point 2',
                    ]
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedDeliveryPoint = val!),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    context.read<InvoiceProvider>().reset();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Order reset')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B7B4C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text(
                    'RESET',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    final provider = context.read<InvoiceProvider>();
                    if (provider.items.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please add items before finalizing'),
                        ),
                      );
                      return;
                    }
                    provider.finalize();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Order finalized successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B7B4C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text(
                    'FINALIZE',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
