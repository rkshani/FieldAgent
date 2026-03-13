import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_endpoints.dart';
import 'local_db_service.dart';

/// Refreshes goods agencies from API and saves to local cache.
class GoodsAgencyService {
  GoodsAgencyService._();

  static final GoodsAgencyService instance = GoodsAgencyService._();

  static const String cacheKey = 'local_goods_agency';
  static const String urlPath = 'order_web_api_z.php?get_goodsagency=1';

  /// Fetches goods agencies from API and saves to LocalDbService.
  /// Returns true on success.
  Future<bool> refreshAndSave() async {
    try {
      final url = ApiEndpoints.goodsAgency();
      final response = await ApiClient.instance.dio.get<String>(url);
      if (response.statusCode == 200 &&
          response.data != null &&
          response.data!.trim().isNotEmpty) {
        await LocalDbService.instance.saveLocalData(
          cacheKey: cacheKey,
          payload: response.data!,
        );
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('GoodsAgencyService.refreshAndSave: $e');
      return false;
    }
  }
}
