import 'invoice_item.dart';

enum InvoiceStatus { draft, finalized, delivered, cancelled }

class Invoice {
  final String id;
  final String visitNumber;
  final String partyName;
  final String goodsAgency;
  final String deliveryAddress;
  final DateTime date;
  final List<InvoiceItem> items;
  final InvoiceStatus status;

  Invoice({
    required this.id,
    required this.visitNumber,
    required this.partyName,
    required this.goodsAgency,
    required this.deliveryAddress,
    required this.date,
    this.items = const [],
    this.status = InvoiceStatus.draft,
  });

  double get grossAmount => items.fold(0, (sum, item) => sum + item.subtotal);

  double get totalDiscount =>
      items.fold(0, (sum, item) => sum + item.discountAmount);

  double get netAmount => grossAmount - totalDiscount;

  Invoice copyWith({
    String? id,
    String? visitNumber,
    String? partyName,
    String? goodsAgency,
    String? deliveryAddress,
    DateTime? date,
    List<InvoiceItem>? items,
    InvoiceStatus? status,
  }) {
    return Invoice(
      id: id ?? this.id,
      visitNumber: visitNumber ?? this.visitNumber,
      partyName: partyName ?? this.partyName,
      goodsAgency: goodsAgency ?? this.goodsAgency,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      date: date ?? this.date,
      items: items ?? this.items,
      status: status ?? this.status,
    );
  }
}

