/// A minimal slice of `GET /v1/shop/shops/mine`'s response (routes/shops.ts,
/// Sprint 2) -- that route returns full `shops` rows; this only picks out
/// what ShopOrdersScreen's own shop-picker needs (id + name), rather than a
/// second full shop model duplicating shop_detail.dart's buyer-facing one.
class MyShop {
  const MyShop({required this.id, required this.name});

  final String id;
  final String name;

  factory MyShop.fromJson(Map<String, dynamic> json) {
    return MyShop(id: json['id'] as String, name: json['name'] as String);
  }
}
