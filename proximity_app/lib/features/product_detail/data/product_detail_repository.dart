import 'package:dio/dio.dart';

import 'models/product_detail.dart';

/// Unauthenticated -- same as ShopDetailRepository, guests browse the PDP
/// too (only the wishlist heart and, from Sprint 6, "add to cart" are
/// gated at the specific action).
class ProductDetailRepository {
  ProductDetailRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// Null (not a thrown error) for a 404 -- a deleted/deactivated product or
  /// a stale deep link, same "expected, common case" pattern
  /// ShopDetailRepository.getShop() and RiderRepository.getMyProfile()
  /// already established for their own 404s.
  Future<ProductDetail?> getProduct(String productId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/v1/products/$productId');
      return ProductDetail.fromJson(response.data!['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }
}
