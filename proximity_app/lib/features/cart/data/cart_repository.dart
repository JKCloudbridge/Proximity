import 'package:dio/dio.dart';

import 'models/cart_item.dart';

/// Every call here needs a signed-in buyer (routes/cart.ts's `authMiddleware`
/// on the whole `/cart*` group) -- same "callers stay behind an already-
/// logged-in check" convention WishlistRepository's own header states.
/// Network-only, no local Drift cache -- see routes/cart.ts's header for why
/// this sprint doesn't reuse Baker Ally's offline-first cart architecture.
class CartRepository {
  CartRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<List<CartItem>> getCart() async {
    final response = await _dio.get<Map<String, dynamic>>('/v1/cart');
    final rows = response.data!['data'] as List<dynamic>;
    return rows.map((e) => CartItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Upsert-and-increment server-side (rpc_add_to_cart, migrations/024) --
  /// safe to call again on a variant already in the cart, same idempotent-
  /// resubmit convention WishlistRepository.add() already follows.
  Future<void> addItem(String variantId, {int quantity = 1}) async {
    await _dio.post<void>('/v1/cart/items', data: {'variantId': variantId, 'quantity': quantity});
  }

  /// Absolute set, not increment -- the cart screen's own +/- stepper always
  /// knows and sends the new total quantity.
  Future<void> updateQuantity(String itemId, int quantity) async {
    await _dio.patch<void>('/v1/cart/items/$itemId', data: {'quantity': quantity});
  }

  Future<void> removeItem(String itemId) async {
    await _dio.delete<void>('/v1/cart/items/$itemId');
  }

  /// §7.3's section-level "Remove all from this shop" action.
  Future<void> removeShop(String shopId) async {
    await _dio.delete<void>('/v1/cart/shops/$shopId');
  }
}
