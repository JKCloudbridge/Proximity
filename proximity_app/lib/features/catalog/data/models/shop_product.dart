import 'product_image.dart';
import 'product_variant.dart';

/// Mirrors one row of `GET /v1/shops/:shopId/products` (routes/catalog.ts) --
/// the shop-detail product grid's data (§7.1). Only active variants come
/// back at all (the route filters them server-side, same as before this
/// sprint), so `variants` here is never the product's *full* variant list --
/// see `ProductDetail` (features/product_detail) for the PDP's own, separate
/// model, which additionally carries shop context the grid doesn't need.
class ShopProduct {
  const ShopProduct({
    required this.id,
    required this.shopId,
    this.subCategoryId,
    required this.name,
    this.isVeg,
    required this.images,
    required this.variants,
  });

  final String id;
  final String shopId;
  final String? subCategoryId;
  final String name;
  final bool? isVeg;
  final List<ProductImage> images;
  final List<ProductVariant> variants;

  String? get thumbnailUrl => images.isEmpty ? null : images.first.imageUrl;

  /// The grid tile's price line -- the cheapest active variant's price, in
  /// rupees. `null` when every variant is inactive (an edge case the PDP
  /// itself would refuse to let a buyer complete a purchase from anyway).
  int? get minPricePaise {
    if (variants.isEmpty) return null;
    return variants.map((v) => v.price).reduce((a, b) => a < b ? a : b);
  }

  bool get anyVariantInStock => variants.any((v) => v.inStock);

  factory ShopProduct.fromJson(Map<String, dynamic> json) {
    return ShopProduct(
      id: json['id'] as String,
      shopId: json['shopId'] as String,
      subCategoryId: json['subCategoryId'] as String?,
      name: json['name'] as String,
      isVeg: json['isVeg'] as bool?,
      images: (json['images'] as List<dynamic>).map((e) => ProductImage.fromJson(e as Map<String, dynamic>)).toList(),
      variants: (json['variants'] as List<dynamic>).map((e) => ProductVariant.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
