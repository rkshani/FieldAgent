class PackageDetails1 {
  final int? id;
  final String? packageId;
  final String? itemId;
  final String? discount;
  final String? groupId;
  final String? price;
  final String? percentage;
  final String? minQty;
  final String? maxQty;
  final String? startDate;
  final String? endDate;
  final String? bazar;
  final String? discountType;
  final String? minAmt;
  final String? maxAmt;
  final String? groupwiseBookIds;
  final String? groupwiseDiscountType;
  final String? groupwiseMinQty;
  final String? groupwiseMaxQty;
  final String? groupwiseMinAmt;
  final String? groupwiseMaxAmt;
  final String? groupwiseItemPackageGroupId;
  final String? defaultPrice;

  PackageDetails1({
    this.id,
    this.packageId,
    this.itemId,
    this.discount,
    this.groupId,
    this.price,
    this.percentage,
    this.minQty,
    this.maxQty,
    this.startDate,
    this.endDate,
    this.bazar,
    this.discountType,
    this.minAmt,
    this.maxAmt,
    this.groupwiseBookIds,
    this.groupwiseDiscountType,
    this.groupwiseMinQty,
    this.groupwiseMaxQty,
    this.groupwiseMinAmt,
    this.groupwiseMaxAmt,
    this.groupwiseItemPackageGroupId,
    this.defaultPrice,
  });

  factory PackageDetails1.fromJson(Map<String, dynamic> json) {
    return PackageDetails1(
      id: json['id'] != null ? int.tryParse(json['id'].toString()) : null,
      packageId: json['package_id']?.toString(),
      itemId: json['item_id']?.toString(),
      discount: json['discount']?.toString(),
      groupId: json['group_id']?.toString(),
      price: json['price']?.toString(),
      percentage: json['percentage']?.toString(),
      minQty: json['minqty']?.toString(),
      maxQty: json['maxqty']?.toString(),
      startDate: json['startdate']?.toString(),
      endDate: json['enddate']?.toString(),
      bazar: json['bazar']?.toString(),
      discountType: json['discount_type']?.toString(),
      minAmt: json['minamt']?.toString(),
      maxAmt: json['maxamt']?.toString(),
      groupwiseBookIds: json['groupwise_bookids']?.toString(),
      groupwiseDiscountType: json['groupwise_discount_type']?.toString(),
      groupwiseMinQty: json['groupwise_minqty']?.toString(),
      groupwiseMaxQty: json['groupwise_maxqty']?.toString(),
      groupwiseMinAmt: json['groupwise_minamt']?.toString(),
      groupwiseMaxAmt: json['groupwise_maxamt']?.toString(),
      groupwiseItemPackageGroupId: json['groupwise_item_package_group_id']
          ?.toString(),
      defaultPrice: json['default_price']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'package_id': packageId,
      'item_id': itemId,
      'discount': discount,
      'group_id': groupId,
      'price': price,
      'percentage': percentage,
      'minqty': minQty,
      'maxqty': maxQty,
      'startdate': startDate,
      'enddate': endDate,
      'bazar': bazar,
      'discount_type': discountType,
      'minamt': minAmt,
      'maxamt': maxAmt,
      'groupwise_bookids': groupwiseBookIds,
      'groupwise_discount_type': groupwiseDiscountType,
      'groupwise_minqty': groupwiseMinQty,
      'groupwise_maxqty': groupwiseMaxQty,
      'groupwise_minamt': groupwiseMinAmt,
      'groupwise_maxamt': groupwiseMaxAmt,
      'groupwise_item_package_group_id': groupwiseItemPackageGroupId,
      'default_price': defaultPrice,
    };
  }
}

class PackageDetails2 {
  final int? id;
  final String? packageId;
  final String? groupId;
  final String? items;
  final String? percentage;

  PackageDetails2({
    this.id,
    this.packageId,
    this.groupId,
    this.items,
    this.percentage,
  });

  factory PackageDetails2.fromJson(Map<String, dynamic> json) {
    return PackageDetails2(
      id: json['id'] != null ? int.tryParse(json['id'].toString()) : null,
      packageId: json['package_id']?.toString(),
      groupId: json['group_id']?.toString(),
      items: json['items']?.toString(),
      percentage: json['percentage']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'package_id': packageId,
      'group_id': groupId,
      'items': items,
      'percentage': percentage,
    };
  }
}
