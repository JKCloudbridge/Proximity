import 'package:dio/dio.dart';

import 'models/wishlist_item.dart';

/// Every call here needs a signed-in buyer (routes/wishlist.ts's
/// `authMiddleware` on the whole `/wishlist*` group) -- callers are
/// responsible for only reaching this repository from behind
/// app_router.dart's `/wishlist` auth gate or an already-logged-in check
/// (WishlistHeartButton does the latter for the shop-detail/PDP surfaces).
class WishlistRepository {
  WishlistRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<List<WishlistItem>> getWishlist() async {
    final response = await _dio.get<Map<String, dynamic>>('/v1/wishlist');
    final rows = response.data!['data'] as List<dynamic>;
    return rows.map((e) => WishlistItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Idempotent server-side (migrations/021's unique constraint,
  /// `onConflictDoNothing` in routes/wishlist.ts) -- safe to call again on a
  /// product already saved.
  Future<void> add(String productId) async {
    await _dio.post<void>('/v1/wishlist', data: {'productId': productId});
  }

  /// Also idempotent -- removing an id that's already gone isn't an error.
  Future<void> remove(String productId) async {
    await _dio.delete<void>('/v1/wishlist/$productId');
  }
}
