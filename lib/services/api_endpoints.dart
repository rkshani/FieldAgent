import 'api_config.dart';

class ApiEndpoints {
  ApiEndpoints._();

  static String tclOrderWeb(String path) {
    final normalized = ApiConfig.trimLeadingSlash(path);
    return '${ApiConfig.domain}${ApiConfig.tclApiRoot}$normalized';
  }

  static String login() => ApiConfig.loginUrl;

  static String goodsAgency() =>
      tclOrderWeb('order_web_api_z.php?get_goodsagency=1');

  static String paymentDeals(String partyId) =>
      tclOrderWeb('app_web_api.php?get_payment_deals=1&partyid=$partyId');

  static String alreadyInOrderItems(String userId, {String? orderId}) {
    final base =
        'order_web_api_z.php?get_already_in_order_items=1&userid=$userId';
    final withOptionalOrder = (orderId != null && orderId.isNotEmpty)
        ? '$base&order_id=$orderId'
        : base;
    return tclOrderWeb(withOptionalOrder);
  }

  static String itemsNewTest(String userId) {
    return '${ApiConfig.tclApiBaseNewTest}taj_api.php?getItems=1&userid=$userId';
  }

  static String packagesNewTest(String userId) {
    return '${ApiConfig.tclApiBaseNewTest}taj_api.php?getPackages=1&userid=$userId';
  }

  static String postOrderZNewTest() {
    return '${ApiConfig.tclApiBaseNewTest}taj_api.php?postOrderZ=1';
  }

  static String agentApprovedVisit(String baseUrl, int userId) {
    return ApiConfig.joinBaseAndPath(
      baseUrl,
      '${ApiConfig.tclApiRootNoTrailingSlash}/taj_api.php?getVisits=1&userid=$userId',
    );
  }

  static String visitedParties(
    String baseUrl, {
    required int userId,
    required String visitId,
    required String routeId,
  }) {
    return ApiConfig.joinBaseAndPath(
      baseUrl,
      '${ApiConfig.tclApiRootNoTrailingSlash}/taj_api.php?get_visited_parties=1&user_id=$userId&visitid=$visitId&routeid=$routeId',
    );
  }

  static String syncUploadOrder(String baseUrl) {
    return ApiConfig.joinBaseAndPath(
      baseUrl,
      '${ApiConfig.tclApiRootNoTrailingSlash}/order_web_api_z.php?upload_order=1',
    );
  }

  /// Fetch orders by logged-in employee (legacy order_web_api_z endpoint)
  /// GET /tclorder_apis_new_test/order_web_api_z.php?get_my_orders=1&employeeid={id}
  static String myOrders(String employeeId) =>
      tclOrderWeb('order_web_api_z.php?get_my_orders=1&employeeid=$employeeId');

  /// Fetch orders via taj_api.php (same file that receives postOrderZ uploads)
  /// GET /tclorder_apis_new_test/taj_api.php?getMyOrders=1&userid={id}
  static String myOrdersTajApi(String employeeId) =>
      '${ApiConfig.tclApiBaseNewTest}taj_api.php?getMyOrders=1&userid=$employeeId';
}
