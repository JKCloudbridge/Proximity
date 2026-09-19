import 'package:dio/dio.dart';

import '../../catalog/data/models/shop_product.dart';

/// Sprint 15 -- the Categories tab's tap-through screen (Sprint planning/
/// Sprint 15.md). Its left rail (nearby shops carrying the tapped category)
/// reuses `HomeRepository.getNearbyShops` directly -- same `GET
/// /v1/shops/near?categoryId=` call Home's own category chips already make,
/// no reason to duplicate it here. This repository only owns the one call
/// that's new this sprint: the right grid's "this shop's products within
/// this category," which isn't a fit for `ShopDetailRepository.getProducts`
/// (that one filters by `subCategoryId`, a different column -- see
/// routes/catalog.ts's own comment on why both exist as independent,
/// optional query params on the same route).
class CategoriesRepository {
  CategoriesRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// Unauthenticated, same as every other buyer-facing catalog read --
  /// guests browse Categories too (app_router.dart's `_protectedPaths`
  /// doesn't gate `/categories/:id`).
  Future<List<ShopProduct>> getShopProductsByCategory(String shopId, String categoryId) async {
    final response = await _dio.get<Map<String, dynamic>>('/v1/shops/$shopId/products', queryParameters: {'categoryId': categoryId});
    final rows = response.data!['data'] as List<dynamic>;
    return rows.map((e) => ShopProduct.fromJson(e as Map<String, dynamic>)).toList();
  }
}
