import 'package:dio/dio.dart';

import 'models/my_shop.dart';
import 'models/shop_order.dart';

/// Sprint 9 -- §2's "lightweight in-app views for shop-order-notifications
/// (shopkeepers/staff)" on proximity_app (not proximity_web, which stays out
/// of scope this sprint, same as every sprint since Sprint 3). Backs
/// ShopOrdersScreen.
class ShopOrdersRepository {
  ShopOrdersRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// Reuses `GET /v1/shop/shops/mine` (Sprint 2) -- an empty list means "not
  /// on any shop's team," which is how account_screen.dart decides whether
  /// to show the "Shop Orders" tile at all.
  Future<List<MyShop>> getMyShops() async {
    final response = await _dio.get<Map<String, dynamic>>('/v1/shop/shops/mine');
    return (response.data!['data'] as List).map((e) => MyShop.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ShopOrder>> getOrders(String shopId) async {
    final response = await _dio.get<Map<String, dynamic>>('/v1/shop/shops/$shopId/orders');
    return (response.data!['data'] as List).map((e) => ShopOrder.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> advanceStatus(String shopId, String orderId, String status) {
    return _dio.post('/v1/shop/shops/$shopId/orders/$orderId/advance-status', data: {'status': status});
  }

  /// The documented manual-retry fallback for "no rider was available at
  /// confirmation time" (migrations/039's own header) -- owner/staff only,
  /// enforced again by the backend regardless of what this screen shows.
  Future<void> assignRider(String shopId, String orderId) {
    return _dio.post('/v1/shop/shops/$shopId/orders/$orderId/assign-rider');
  }
}
