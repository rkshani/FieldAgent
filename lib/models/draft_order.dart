/// Represents the current draft order header (from DB).
class DraftOrder {
  final int id;
  final String? localOrderId;
  final int? orderSerialNo;
  final String? billToPartyId;
  final String? partyName;
  final String? shipToPartyId;
  final String? deliveryPartyName;
  final String? deliveryPointId;
  final String? deliveryPointName;
  final String? goodsAgencyId;
  final String? goodsAgencyName;
  final String? visitId;
  final String? routeId;
  final String? packageId;
  final String? packageName;
  final String? paymentDealId;
  final String? deliveryAddress;
  final String? orderRemarks;
  final String status;
  final String finalizeFlag;
  final String uploaded;
  final String? uploadedAt;
  final String? finalizedAt;
  final String createdAt;
  final String updatedAt;
  final String? employeeId;

  const DraftOrder({
    required this.id,
    this.localOrderId,
    this.orderSerialNo,
    this.billToPartyId,
    this.partyName,
    this.shipToPartyId,
    this.deliveryPartyName,
    this.deliveryPointId,
    this.deliveryPointName,
    this.goodsAgencyId,
    this.goodsAgencyName,
    this.visitId,
    this.routeId,
    this.packageId,
    this.packageName,
    this.paymentDealId,
    this.deliveryAddress,
    this.orderRemarks,
    this.status = 'draft',
    this.finalizeFlag = '0',
    this.uploaded = 'NO',
    this.uploadedAt,
    this.finalizedAt,
    required this.createdAt,
    required this.updatedAt,
    this.employeeId,
  });

  bool get isFinalized => status == 'finalized';
  bool get isPendingUpload => finalizeFlag == '1' && uploaded != 'YES';
  bool get isUploaded => finalizeFlag == '2' || uploaded == 'YES';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'local_order_id': localOrderId,
      'order_serial_no': orderSerialNo,
      'bill_to_party_id': billToPartyId,
      'party_name': partyName,
      'ship_to_party_id': shipToPartyId,
      'delivery_party_name': deliveryPartyName,
      'delivery_point_id': deliveryPointId,
      'delivery_point_name': deliveryPointName,
      'goods_agency_id': goodsAgencyId,
      'goods_agency_name': goodsAgencyName,
      'visit_id': visitId,
      'route_id': routeId,
      'package_id': packageId,
      'package_name': packageName,
      'payment_deal_id': paymentDealId,
      'delivery_address': deliveryAddress,
      'order_remarks': orderRemarks,
      'status': status,
      'finalize_flag': finalizeFlag,
      'uploaded': uploaded,
      'uploaded_at': uploadedAt,
      'finalized_at': finalizedAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'employee_id': employeeId,
    };
  }

  static DraftOrder fromMap(Map<String, dynamic> map) {
    final serialRaw = map['order_serial_no'];
    int? serialNo;
    if (serialRaw is int) {
      serialNo = serialRaw;
    } else if (serialRaw is num) {
      serialNo = serialRaw.toInt();
    } else if (serialRaw != null) {
      serialNo = int.tryParse(serialRaw.toString());
    }

    return DraftOrder(
      id: map['id'] as int,
      localOrderId: map['local_order_id'] as String?,
      orderSerialNo: serialNo,
      billToPartyId: map['bill_to_party_id'] as String?,
      partyName: map['party_name'] as String?,
      shipToPartyId: map['ship_to_party_id'] as String?,
      deliveryPartyName: map['delivery_party_name'] as String?,
      deliveryPointId: map['delivery_point_id'] as String?,
      deliveryPointName: map['delivery_point_name'] as String?,
      goodsAgencyId: map['goods_agency_id'] as String?,
      goodsAgencyName: map['goods_agency_name'] as String?,
      visitId: map['visit_id'] as String?,
      routeId: map['route_id'] as String?,
      packageId: map['package_id'] as String?,
      packageName: map['package_name'] as String?,
      paymentDealId: map['payment_deal_id'] as String?,
      deliveryAddress: map['delivery_address'] as String?,
      orderRemarks: map['order_remarks'] as String?,
      status: map['status'] as String? ?? 'draft',
      finalizeFlag: map['finalize_flag'] as String? ?? '0',
      uploaded: map['uploaded'] as String? ?? 'NO',
      uploadedAt: map['uploaded_at'] as String?,
      finalizedAt: map['finalized_at'] as String?,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
      employeeId: map['employee_id'] as String?,
    );
  }
}
