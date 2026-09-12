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
      distanceKm: (json['distanceKm'] as num).toDouble(),
    );
  }
}
