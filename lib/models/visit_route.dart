class AgentApprovedVisit {
  final int? id;
  final String? visitId;
  final String? routes;
  final String? cityIds;
  final String? routeId;

  AgentApprovedVisit({
    this.id,
    this.visitId,
    this.routes,
    this.cityIds,
    this.routeId,
  });

  factory AgentApprovedVisit.fromJson(Map<String, dynamic> json) {
    return AgentApprovedVisit(
      id: json['id'] != null ? int.tryParse(json['id'].toString()) : null,
      visitId: json['visit_id']?.toString(),
      routes: json['routes']?.toString(),
      cityIds: json['cityids']?.toString(),
      routeId: json['routeid']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'visit_id': visitId,
      'routes': routes,
      'cityids': cityIds,
      'routeid': routeId,
    };
  }
}

class VisitRouteData {
  final int? id;
  final String? routeId;
  final String? visitorId;
  final String? dateStart;
  final String? dateEnd;
  final String? routes;
  final String? status;
  final String? voucherSubmitted;
  final String? cities;
  final String? citiesName;
  final String? voucherId;
  final String? year;
  final String? marketingRemarks;

  VisitRouteData({
    this.id,
    this.routeId,
    this.visitorId,
    this.dateStart,
    this.dateEnd,
    this.routes,
    this.status,
    this.voucherSubmitted,
    this.cities,
    this.citiesName,
    this.voucherId,
    this.year,
    this.marketingRemarks,
  });

  factory VisitRouteData.fromJson(Map<String, dynamic> json) {
    return VisitRouteData(
      id: json['id'] != null ? int.tryParse(json['id'].toString()) : null,
      routeId: json['route_id']?.toString(),
      visitorId: json['visitor_id']?.toString(),
      dateStart: json['date_start']?.toString(),
      dateEnd: json['date_end']?.toString(),
      routes: json['routes']?.toString(),
      status: json['status']?.toString(),
      voucherSubmitted: json['voucher_submitted']?.toString(),
      cities: json['cities']?.toString(),
      citiesName: json['citiesname']?.toString(),
      voucherId: json['voucherid']?.toString(),
      year: json['year']?.toString(),
      marketingRemarks: json['marketingremarks']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'route_id': routeId,
      'visitor_id': visitorId,
      'date_start': dateStart,
      'date_end': dateEnd,
      'routes': routes,
      'status': status,
      'voucher_submitted': voucherSubmitted,
      'cities': cities,
      'citiesname': citiesName,
      'voucherid': voucherId,
      'year': year,
      'marketingremarks': marketingRemarks,
    };
  }
}
