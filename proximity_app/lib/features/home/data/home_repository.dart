import 'package:dio/dio.dart';

import 'models/category.dart';
import 'models/nearby_shop.dart';

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
}
