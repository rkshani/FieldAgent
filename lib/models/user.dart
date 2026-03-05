class User {
  final int id;
  final String username;
  final String email;
  final String role;
  final String usermlevel;
  final String businessunit;
  final String dept;
  final String employeeid;
  final String storeid;
  final String passdate;
  final String roles;
  final String emLocationId;
  final String emLocationName;
  final String allowAllUsers;
  final String allowedStoreInvoices;
  final String allowedStoreOrders;
  final String allowAllInvoices;
  final String orderFinances;
  final String allowSalaryFinances;
  final String allowedOffices;
  final String ordersPage;
  final String account;
  final String pinverification;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    required this.usermlevel,
    required this.businessunit,
    required this.dept,
    required this.employeeid,
    required this.storeid,
    required this.passdate,
    required this.roles,
    required this.emLocationId,
    required this.emLocationName,
    required this.allowAllUsers,
    required this.allowedStoreInvoices,
    required this.allowedStoreOrders,
    required this.allowAllInvoices,
    required this.orderFinances,
    required this.allowSalaryFinances,
    required this.allowedOffices,
    required this.ordersPage,
    required this.account,
    required this.pinverification,
  });

  /// From API response (Android: obj.getJSONObject("data")). Supports both API key names.
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: int.tryParse(json['id']?.toString() ?? json['employeeid']?.toString() ?? '0') ?? 0,
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? json['code']?.toString() ?? '',
      role: json['role']?.toString() ?? json['Type1']?.toString() ?? '',
      usermlevel: json['usermlevel']?.toString() ?? '',
      businessunit: json['businessunit']?.toString() ?? '',
      dept: json['dept']?.toString() ?? '',
      employeeid: json['employeeid']?.toString() ?? '',
      storeid: json['storeid']?.toString() ?? '',
      passdate: json['passdate']?.toString() ?? json['PasswordDate']?.toString() ?? '',
      roles: json['roles']?.toString() ?? json['role_id']?.toString() ?? '',
      emLocationId: json['em_location_id']?.toString() ?? '',
      emLocationName: json['em_location_name']?.toString() ?? '',
      allowAllUsers: json['allow_all_users']?.toString() ?? '',
      allowedStoreInvoices: json['allowed_store_invoices']?.toString() ?? '',
      allowedStoreOrders: json['allowed_store_orders']?.toString() ?? '',
      allowAllInvoices: json['allow_all_invoices']?.toString() ?? '',
      orderFinances: json['order_finances']?.toString() ?? '',
      allowSalaryFinances: json['allow_salary_finances']?.toString() ?? '',
      allowedOffices: json['allowed_offices']?.toString() ?? json['allowed_parties']?.toString() ?? '',
      ordersPage: json['orders_page']?.toString() ?? '',
      account: json['account']?.toString() ?? '',
      pinverification: json['pinverification']?.toString() ?? '0',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'role': role,
      'usermlevel': usermlevel,
      'businessunit': businessunit,
      'dept': dept,
      'employeeid': employeeid,
      'storeid': storeid,
      'passdate': passdate,
      'roles': roles,
      'em_location_id': emLocationId,
      'em_location_name': emLocationName,
      'allow_all_users': allowAllUsers,
      'allowed_store_invoices': allowedStoreInvoices,
      'allowed_store_orders': allowedStoreOrders,
      'allow_all_invoices': allowAllInvoices,
      'order_finances': orderFinances,
      'allow_salary_finances': allowSalaryFinances,
      'allowed_offices': allowedOffices,
      'orders_page': ordersPage,
      'account': account,
      'pinverification': pinverification,
    };
  }
}
