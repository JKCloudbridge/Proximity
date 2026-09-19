/// Sprint 10 -- mirrors both `GET /v1/home/frequently-bought`'s `products`
/// entries and `GET /v1/order-again/previously-bought`'s rows (routes/
/// home.ts, routes/orderAgain.ts) -- the same underlying "products this
/// buyer has ordered before" shape (lib/repeatPurchases.ts, backend), just
/// fetched at two different repeat-count thresholds. One shared model here
/// (features/catalog, this project's existing home for cross-feature
/// browse-data models, per Sprint 5's own comment on that folder) rather
/// than two near-duplicate classes in `home` and `order_again` -- both
/// features read every field (unlike `ShopProduct`/`RecommendedProduct`,
/// which really do differ in shape).
class RepeatProduct {
  const RepeatProduct({
    required this.variantId,
    required this.productId,
    required this.name,
    this.isVeg,
    required this.unitValue,
    required this.unitLabel,
    required this.price,
    this.mrp,
    this.imageUrl,
    required this.isAvailable,
    required this.shopId,
    required this.shopName,
    this.shopLogoUrl,
    required this.timesOrdered,
    required this.lastOrderedAt,
  });

  final String variantId;
  final String productId;
  final String name;
  final bool? isVeg;
  final String unitValue;
  final String unitLabel;
  final int price;
  final int? mrp;
  final String? imageUrl;
  final bool isAvailable;
  final String shopId;
  final String shopName;
  final String? shopLogoUrl;
  final int timesOrdered;
  final DateTime lastOrderedAt;

  factory RepeatProduct.fromJson(Map<String, dynamic> json) {
    return RepeatProduct(
      variantId: json['variantId'] as String,
      productId: json['productId'] as String,
      name: json['name'] as String,
      isVeg: json['isVeg'] as bool?,
      unitValue: json['unitValue'] as String,
      unitLabel: json['unitLabel'] as String,
      price: json['price'] as int,
      mrp: json['mrp'] as int?,
      imageUrl: json['imageUrl'] as String?,
      isAvailable: json['isAvailable'] as bool,
      shopId: json['shopId'] as String,
      shopName: json['shopName'] as String,
      shopLogoUrl: json['shopLogoUrl'] as String?,
      timesOrdered: json['timesOrdered'] as int,
      lastOrderedAt: DateTime.parse(json['lastOrderedAt'] as String),
    );
  }

  // Sprint 15 -- local cache round-trip (core/cache), not the network.
  Map<String, dynamic> toJson() {
    return {
      'variantId': variantId,
      'productId': productId,
      'name': name,
      'isVeg': isVeg,
      'unitValue': unitValue,
      'unitLabel': unitLabel,
      'price': price,
      'mrp': mrp,
      'imageUrl': imageUrl,
      'isAvailable': isAvailable,
      'shopId': shopId,
      'shopName': shopName,
      'shopLogoUrl': shopLogoUrl,
      'timesOrdered': timesOrdered,
      'lastOrderedAt': lastOrderedAt.toIso8601String(),
    };
  }
}
