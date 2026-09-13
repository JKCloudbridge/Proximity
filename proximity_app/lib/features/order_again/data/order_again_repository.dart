import 'package:dio/dio.dart';

import '../../catalog/data/models/repeat_product.dart';
import 'models/frequently_bought_group.dart';

/// Own-user data (§5.2), same authenticated-only shape as
/// WishlistRepository/CartRepository -- every call here needs a signed-in
/// buyer (routes/orderAgain.ts's `authMiddleware` on the whole
/// `/order-again/*` group).
class OrderAgainRepository {
  OrderAgainRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<List<FrequentlyBoughtGroup>> getFrequentlyBought() async {
    final response = await _dio.get<Map<String, dynamic>>('/v1/order-again/frequently-bought');
    final rows = response.data!['data'] as List<dynamic>;
    return rows.map((e) => FrequentlyBoughtGroup.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `hasMore` (in the response envelope, not derived client-side) is what
  /// drives §6's infinite scroll -- the caller doesn't need to guess from a
  /// short page whether more exist.
  Future<({List<RepeatProduct> items, bool hasMore})> getPreviouslyBought({
    required int limit,
    required int offset,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/v1/order-again/previously-bought',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    final rows = response.data!['data'] as List<dynamic>;
    return (
      items: rows.map((e) => RepeatProduct.fromJson(e as Map<String, dynamic>)).toList(),
      hasMore: response.data!['hasMore'] as bool,
    );
  }

  /// §4/§5's "Add All to Cart" / "Add Selected Items to Cart" -- `POST
  /// /v1/cart/items/batch` (routes/cart.ts, Sprint 10), best-effort per
  /// item. Returns which variant ids actually landed and which didn't
  /// (with why), so the calling widget can show an honest "N items added,
  /// 1 unavailable" rather than a blind success toast.
  Future<({List<String> added, List<String> failedVariantIds})> addItemsBatch(
    List<({String variantId, int quantity})> items,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/v1/cart/items/batch',
      data: {
        'items': [for (final item in items) {'variantId': item.variantId, 'quantity': item.quantity}],
      },
    );
    final data = response.data!['data'] as Map<String, dynamic>;
    return (
      added: (data['added'] as List<dynamic>).cast<String>(),
      failedVariantIds: (data['failed'] as List<dynamic>).map((e) => (e as Map<String, dynamic>)['variantId'] as String).toList(),
    );
  }
}
