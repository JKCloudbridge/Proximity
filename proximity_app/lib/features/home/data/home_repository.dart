import 'package:dio/dio.dart';

import '../../catalog/data/models/repeat_product.dart';
import 'models/category.dart';
import 'models/nearby_shop.dart';
import 'models/recommended_product.dart';

class HomeRepository {
  HomeRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// Unauthenticated -- guests browse Home too (app_router.dart's
  /// `_protectedPaths` comment).
  Future<List<Category>> getCategories() async {
    final response = await _dio.get<Map<String, dynamic>>('/v1/categories');
    final rows = response.data!['data'] as List<dynamic>;
    return rows.map((e) => Category.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `GET /v1/shops/near` (routes/shops.ts, Sprint 4) -- server-side
  /// distance sort + service-radius cut + optional category filter (§7.1's
  /// "category-click filtering"). `categoryId` omitted (not sent at all,
  /// not sent as null) shows every nearby shop, matching this route's own
  /// `.optional()` query schema.
  Future<List<NearbyShop>> getNearbyShops({required double lat, required double lng, String? categoryId}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/v1/shops/near',
      queryParameters: {'lat': lat, 'lng': lng, if (categoryId != null) 'categoryId': categoryId},
    );
    final rows = response.data!['data'] as List<dynamic>;
    return rows.map((e) => NearbyShop.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `GET /v1/recommended` (routes/recommendations.ts, Sprint 6) --
  /// unauthenticated route, but Dio's own interceptor (dio_client.dart)
  /// already attaches a bearer token whenever one exists, so a signed-in
  /// buyer gets the wishlist-personalized ranking for free with no extra
  /// parameter here; a guest gets the plain trending fallback.
  Future<List<RecommendedProduct>> getRecommended({required double lat, required double lng}) async {
    final response = await _dio.get<Map<String, dynamic>>('/v1/recommended', queryParameters: {'lat': lat, 'lng': lng});
    final rows = response.data!['data'] as List<dynamic>;
    return rows.map((e) => RecommendedProduct.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `GET /v1/home/frequently-bought` (routes/home.ts, Sprint 10) -- §7.1's
  /// conditional "Frequently Bought at >=3 patterns" section. Authenticated
  /// only (own-user data); the Home screen simply doesn't call this for a
  /// guest, same "gated at the specific data need" rule buyerLocationProvider
  /// already applies for signed-out browsing.
  Future<({bool qualifies, List<RepeatProduct> products})> getFrequentlyBought() async {
    final response = await _dio.get<Map<String, dynamic>>('/v1/home/frequently-bought');
    final data = response.data!['data'] as Map<String, dynamic>;
    return (
      qualifies: data['qualifies'] as bool,
      products: (data['products'] as List<dynamic>).map((e) => RepeatProduct.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
