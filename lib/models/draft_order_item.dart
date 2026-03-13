/// A line item on a draft order (from DB).
class DraftOrderItem {
  final int id;
  final int draftOrderId;
  final String? itemId;
  final String itemName;
  final int quantity;
  final double unitPrice;
  final double discountPercent;
  final String? remarks;
  final String? directionStore;
  final String? specialRemarks;
  final double specialPrice;
  final String? subItemId;
  final int sortOrder;
  final String createdAt;

  const DraftOrderItem({
    required this.id,
    required this.draftOrderId,
    this.itemId,
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    this.discountPercent = 0,
    this.remarks,
    this.directionStore,
    this.specialRemarks,
    this.specialPrice = 0,
    this.subItemId,
    this.sortOrder = 0,
    required this.createdAt,
  });

  double get subtotal => unitPrice * quantity;
  double get discountAmount => subtotal * (discountPercent / 100);
  double get total => subtotal - discountAmount;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'draft_order_id': draftOrderId,
      'item_id': itemId,
      'item_name': itemName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'discount_percent': discountPercent,
      'remarks': remarks,
      'direction_store': directionStore,
      'special_remarks': specialRemarks,
      'special_price': specialPrice,
      'subitem_id': subItemId,
      'sort_order': sortOrder,
      'created_at': createdAt,
    };
  }

  static DraftOrderItem fromMap(Map<String, dynamic> map) {
    return DraftOrderItem(
      id: map['id'] as int,
      draftOrderId: map['draft_order_id'] as int,
      itemId: map['item_id'] as String?,
      itemName: map['item_name'] as String? ?? '',
      quantity: map['quantity'] as int? ?? 1,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
      discountPercent: (map['discount_percent'] as num?)?.toDouble() ?? 0,
      remarks: map['remarks'] as String?,
      directionStore: map['direction_store'] as String?,
      specialRemarks: map['special_remarks'] as String?,
      specialPrice: (map['special_price'] as num?)?.toDouble() ?? 0,
      subItemId: map['subitem_id'] as String?,
      sortOrder: map['sort_order'] as int? ?? 0,
      createdAt: map['created_at'] as String? ?? '',
    );
  }
}
