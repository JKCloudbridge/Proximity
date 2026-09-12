import 'package:dio/dio.dart';

import '../../catalog/data/models/shop_product.dart';
import 'models/shop_detail.dart';
import 'models/shop_sub_category.dart';

/// Unauthenticated, same as HomeRepository -- guests browse shop detail too
/// (app_router.dart's `_protectedPaths` doesn't gate `/shop/:id`).
class ShopDetailRepository {
  ShopDetailRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// Null (not a thrown error) for a 404 -- a shop that's since been
  /// suspended, or a stale deep link -- same "expected, common case" pattern
  /// RiderRepository.getMyProfile() established for its own 404.
  Future<ShopDetail?> getShop(String shopId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/v1/shops/$shopId');
      return ShopDetail.fromJson(response.data!['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<ShopSubCategory>> getSubCategories(String shopId) async {
    final response = await _dio.get<Map<String, dynamic>>('/v1/shops/$shopId/sub-categories');
    final rows = response.data!['data'] as List<dynamic>;
    return rows.map((e) => ShopSubCategory.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// `subCategoryId` omitted (not sent as null) returns the shop's full
  /// catalog -- the rail's own "All" state, same convention Home's category
  /// chips established for `selectedCategoryIdProvider`.
  Future<List<ShopProduct>> getProducts(String shopId, {String? subCategoryId}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/v1/shops/$shopId/products',
      queryParameters: {if (subCategoryId != null) 'subCategoryId': subCategoryId},
    );
    final rows = response.data!['data'] as List<dynamic>;
    return rows.map((e) => ShopProduct.fromJson(e as Map<String, dynamic>)).toList();
  }
}
