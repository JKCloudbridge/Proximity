import '../../../catalog/data/models/product_image.dart';
import '../../../catalog/data/models/product_variant.dart';

/// Mirrors `GET /v1/products/:id` (routes/catalog.ts) -- the PDP's full
/// data, including every currently-active variant (§7's "variant selection
/// (price/unit/stock_status per variant)") and the light `shop` join this
/// sprint added specifically so the PDP has shop context even when reached
/// from somewhere other than the shop-detail screen (the wishlist grid, in
/// particular -- see that route's own comment).
class ProductDetail {
  const ProductDetail({
    required this.id,
    required this.shopId,
    required this.name,
    this.description,
    this.isVeg,
    this.infoMessage,
    required this.images,
    required this.variants,
    required this.shopName,
    this.shopLogoUrl,
  });

  final String id;
  final String shopId;
  final String name;
  final String? description;
  final bool? isVeg;
  final String? infoMessage;
  final List<ProductImage> images;
  final List<ProductVariant> variants;
  final String shopName;
  final String? shopLogoUrl;

  factory ProductDetail.fromJson(Map<String, dynamic> json) {
    final shop = json['shop'] as Map<String, dynamic>;
    return ProductDetail(
      id: json['id'] as String,
      shopId: json['shopId'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      isVeg: json['isVeg'] as bool?,
      infoMessage: json['infoMessage'] as String?,
      images: (json['images'] as List<dynamic>).map((e) => ProductImage.fromJson(e as Map<String, dynamic>)).toList(),
      variants: (json['variants'] as List<dynamic>).map((e) => ProductVariant.fromJson(e as Map<String, dynamic>)).toList(),
      shopName: shop['name'] as String,
      shopLogoUrl: shop['logoUrl'] as String?,
    );
  }
}
