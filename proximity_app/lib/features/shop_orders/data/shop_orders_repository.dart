import 'package:dio/dio.dart';

import '../../../shared/errors/cancel_order_exception.dart';
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
  /// Sprint 12 -- `force` (default false) also covers "this rider isn't
  /// responding, find someone else" on an order that already has one
  /// assigned (migrations/048's own header names this as the one gap this
  /// project doesn't auto-detect: mid-delivery unreachability). Always sends
  /// an explicit JSON body -- routes/shopOrders.ts's own zValidator now
  /// requires one; an earlier version of this call sent none at all, which
  /// this sprint's own route change would otherwise have silently broken.
  Future<void> assignRider(String shopId, String orderId, {bool force = false}) {
    return _dio.post('/v1/shop/shops/$shopId/orders/$orderId/assign-rider', data: {'force': force});
  }

  /// Sprint 12 -- shop-initiated cancellation (rpc_cancel_order,
  /// migrations/047). Owner/staff only, same tier the manual rider-
  /// assignment retry above already uses. Throws `CancelOrderException`
  /// (checkout_repository.dart) with the backend's own typed error on
  /// failure -- one shared exception type since both cancellation call
  /// sites (buyer here, shop there) map the same rpc_cancel_order error
  /// codes.
  Future<void> cancelOrder(String shopId, String orderId, {String? reason}) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/v1/shop/shops/$shopId/orders/$orderId/cancel',
        data: {if (reason != null && reason.isNotEmpty) 'reason': reason},
      );
    } on DioException catch (err) {
      final data = err.response?.data;
      final code = data is Map ? (data['error']?['code'] as String?) : null;
      final message = data is Map ? (data['error']?['message'] as String?) : null;
      throw CancelOrderException(code ?? 'UNKNOWN', message ?? 'Could not cancel this order');
    }
  }
}
