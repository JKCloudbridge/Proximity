/// Mirrors one row of `GET /v1/wishlist` (routes/wishlist.ts, Sprint 5) --
/// hand-built server-side (not a raw Drizzle passthrough), so already
/// camelCase throughout, nested `product` included.
class WishlistItem {
  const WishlistItem({required this.productId, required this.addedAt, required this.isAvailable, this.product});

  final String productId;
  final DateTime addedAt;
  // False once the product's been deleted, deactivated, or its shop
  // suspended after being wishlisted -- routes/wishlist.ts's own comment on
  // why the row still appears instead of silently disappearing.
  final bool isAvailable;
  final WishlistProduct? product;

  factory WishlistItem.fromJson(Map<String, dynamic> json) {
    return WishlistItem(
      productId: json['productId'] as String,
      addedAt: DateTime.parse(json['addedAt'] as String),
      isAvailable: json['isAvailable'] as bool,
      product: json['product'] != null ? WishlistProduct.fromJson(json['product'] as Map<String, dynamic>) : null,
    );
  }
}

class WishlistProduct {
  const WishlistProduct({
    required this.id,
    required this.name,
    this.isVeg,
    required this.shopId,
    this.shopName,
    this.imageUrl,
    this.minPrice,
  });

  final String id;
  final String name;
  final bool? isVeg;
  final String shopId;
  final String? shopName;
  final String? imageUrl;
  final int? minPrice;

  factory WishlistProduct.fromJson(Map<String, dynamic> json) {
    return WishlistProduct(
      id: json['id'] as String,
      name: json['name'] as String,
      isVeg: json['isVeg'] as bool?,
      shopId: json['shopId'] as String,
      shopName: json['shopName'] as String?,
      imageUrl: json['imageUrl'] as String?,
      minPrice: json['minPrice'] as int?,
    );
  }
}
