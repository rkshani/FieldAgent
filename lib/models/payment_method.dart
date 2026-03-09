class PaymentMethod {
  final int? id;
  final int? partyId;
  final int? amount;
  final String? remarks;
  final String? createdDate;
  final int? userId;
  final String? status;

  PaymentMethod({
    this.id,
    this.partyId,
    this.amount,
    this.remarks,
    this.createdDate,
    this.userId,
    this.status,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id'] != null ? int.tryParse(json['id'].toString()) : null,
      partyId: json['partyid'] != null
          ? int.tryParse(json['partyid'].toString())
          : null,
      amount: json['amount'] != null
          ? int.tryParse(json['amount'].toString())
          : null,
      remarks: json['remarks']?.toString(),
      createdDate: json['created_date']?.toString(),
      userId: json['userid'] != null
          ? int.tryParse(json['userid'].toString())
          : null,
      status: json['status']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'partyid': partyId,
      'amount': amount,
      'remarks': remarks,
      'created_date': createdDate,
      'userid': userId,
      'status': status,
    };
  }
}
