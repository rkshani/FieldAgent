import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/invoice.dart';
import '../models/invoice_item.dart';

class InvoiceProvider extends ChangeNotifier {
  late Invoice _invoice;
  final List<Invoice> _savedInvoices = [];

  InvoiceProvider() {
    _initializeInvoice();
  }

  void _initializeInvoice() {
    _invoice = Invoice(
      id: const Uuid().v4(),
      visitNumber: 'V-${DateTime.now().millisecondsSinceEpoch}',
      partyName: 'Select Party',
      goodsAgency: 'Agency 1',
      deliveryAddress: 'Enter Address',
      date: DateTime.now(),
    );
  }

  Invoice get invoice => _invoice;

  List<Invoice> get savedInvoices => List.unmodifiable(_savedInvoices);

  List<InvoiceItem> get items => _invoice.items;

  double get grossAmount => _invoice.grossAmount;

  double get totalDiscount => _invoice.totalDiscount;

  double get netAmount => _invoice.netAmount;

  void updateInvoiceInfo({
    String? partyName,
    String? goodsAgency,
    String? deliveryAddress,
  }) {
    _invoice = _invoice.copyWith(
      partyName: partyName ?? _invoice.partyName,
      goodsAgency: goodsAgency ?? _invoice.goodsAgency,
      deliveryAddress: deliveryAddress ?? _invoice.deliveryAddress,
    );
    notifyListeners();
  }

  void addItem(InvoiceItem item) {
    final updatedItems = [..._invoice.items, item];
    _invoice = _invoice.copyWith(items: updatedItems);
    notifyListeners();
  }

  void updateItem(String itemId, InvoiceItem updatedItem) {
    final index = _invoice.items.indexWhere((item) => item.id == itemId);
    if (index != -1) {
      final updatedItems = [..._invoice.items];
      updatedItems[index] = updatedItem;
      _invoice = _invoice.copyWith(items: updatedItems);
      notifyListeners();
    }
  }

  void removeItem(String itemId) {
    final updatedItems = _invoice.items
        .where((item) => item.id != itemId)
        .toList();
    _invoice = _invoice.copyWith(items: updatedItems);
    notifyListeners();
  }

  void reset() {
    _initializeInvoice();
    notifyListeners();
  }

  /// Finalize the current invoice. Returns true when finalized, false otherwise.
  bool finalize() {
    // Do not finalize empty invoices
    if (_invoice.items.isEmpty) return false;

    // Save current invoice as finalized and reset current invoice
    final finalized = _invoice.copyWith(
      status: InvoiceStatus.finalized,
      date: DateTime.now(),
    );
    _savedInvoices.add(finalized);
    _initializeInvoice();
    notifyListeners();
    return true;
  }
}

