/// Mirrors `GET /v1/shops/:shopId/sub-categories` (routes/catalog.ts, Sprint
/// 3's first route for this table, first *consumer* this sprint) -- §4.3's
/// shop-owned rail entries, §7.1's "vertical category rail w/ icon-on-select,
/// scoped to that shop's own shop_sub_categories."
class ShopSubCategory {
  const ShopSubCategory({required this.id, required this.shopId, required this.categoryId, required this.name, this.iconUrl, required this.sortOrder});

  final String id;
  final String shopId;
  final String categoryId;
  final String name;
  final String? iconUrl;
  final int sortOrder;

  // routes/catalog.ts's sub-categories route responds via Drizzle's
  // schema-mapped `.select()`, not a raw `db.execute(sql...)` -- already
  // camelCase, no snake_case fallback needed (contrast NearbyShop's
  // neighbor, `GET /shops/near`, which hand-builds its response for exactly
  // the opposite reason -- see that file's header).
  factory ShopSubCategory.fromJson(Map<String, dynamic> json) {
    return ShopSubCategory(
      id: json['id'] as String,
      shopId: json['shopId'] as String,
      categoryId: json['categoryId'] as String,
      name: json['name'] as String,
      iconUrl: json['iconUrl'] as String?,
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }

  // Sprint 15 -- local cache round-trip (core/cache), not the network.
  Map<String, dynamic> toJson() {
    return {'id': id, 'shopId': shopId, 'categoryId': categoryId, 'name': name, 'iconUrl': iconUrl, 'sortOrder': sortOrder};
  }
}
