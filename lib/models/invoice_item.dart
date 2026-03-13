class InvoiceItem {
  final String id;
  final String name;
  final double price;
  int quantity;
  double discountPercent;
  String remarks;
  String directionStore;
  String specialRemarks;
  double specialPrice;
  String subItemId;

  InvoiceItem({
    required this.id,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.discountPercent = 0,
    this.remarks = '',
    this.directionStore = '',
    this.specialRemarks = '',
    this.specialPrice = 0,
    this.subItemId = '',
  });

  double get subtotal => price * quantity;

  double get discountAmount => subtotal * (discountPercent / 100);

  double get total => subtotal - discountAmount;

  InvoiceItem copyWith({
    String? id,
    String? name,
    double? price,
    int? quantity,
    double? discountPercent,
    String? remarks,
    String? directionStore,
    String? specialRemarks,
    double? specialPrice,
    String? subItemId,
  }) {
    return InvoiceItem(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      discountPercent: discountPercent ?? this.discountPercent,
      remarks: remarks ?? this.remarks,
      directionStore: directionStore ?? this.directionStore,
      specialRemarks: specialRemarks ?? this.specialRemarks,
      specialPrice: specialPrice ?? this.specialPrice,
      subItemId: subItemId ?? this.subItemId,
    );
  }
}
