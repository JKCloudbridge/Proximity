/// Mirrors `GET /v1/recommended` (routes/recommendations.ts, Sprint 6) --
/// already camelCase (hand-built server-side, same as NearbyShop). §7.1's
/// "Recommended for you, 2-row horizontal scroll" Home section.
class RecommendedProduct {
  const RecommendedProduct({
    required this.productId,
    required this.name,
    this.isVeg,
    required this.shopId,
    required this.shopName,
    this.shopLogoUrl,
    this.imageUrl,
    required this.minPrice,
    this.variantId,
    required this.distanceKm,
  });

  final String productId;
  final String name;
  final bool? isVeg;
  final String shopId;
  final String shopName;
  final String? shopLogoUrl;
  final String? imageUrl;
  final int minPrice;
  // Sprint 15 feedback: the cheapest active variant's id, matching `minPrice`
  // -- added specifically so the Home Recommended card's own quick-add
  // button (ProductGridTile's shared QuickAddControl) has a real variant to
  // call POST /v1/cart/items with. Nullable since a product can in theory
  // have zero active variants (routes/recommendations.ts's own comment on
  // this), in which case there's nothing valid to quick-add.
  final String? variantId;
  final double distanceKm;

  factory RecommendedProduct.fromJson(Map<String, dynamic> json) {
    return RecommendedProduct(
      productId: json['productId'] as String,
      name: json['name'] as String,
      isVeg: json['isVeg'] as bool?,
      shopId: json['shopId'] as String,
      shopName: json['shopName'] as String,
      shopLogoUrl: json['shopLogoUrl'] as String?,
      imageUrl: json['imageUrl'] as String?,
      minPrice: json['minPrice'] as int,
      variantId: json['variantId'] as String?,
      distanceKm: (json['distanceKm'] as num).toDouble(),
    );
  }

  // Sprint 15 -- local cache round-trip (core/cache), not the network.
  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'name': name,
      'isVeg': isVeg,
      'shopId': shopId,
      'shopName': shopName,
      'shopLogoUrl': shopLogoUrl,
      'imageUrl': imageUrl,
      'minPrice': minPrice,
      'variantId': variantId,
      'distanceKm': distanceKm,
    };
  }
}
