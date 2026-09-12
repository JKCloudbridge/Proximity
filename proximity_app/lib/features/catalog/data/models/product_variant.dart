/// Mirrors `product_variants` rows as returned by both `GET
/// /v1/shops/:shopId/products` and `GET /v1/products/:id` (routes/catalog.ts)
/// -- §7's PDP spec: "variant selection (price/unit/stock_status per
/// variant)." Both routes reach these rows through Drizzle's schema-mapped
/// `.select()`, so this is already camelCase (contrast NearbyShop's
/// `GET /shops/near`, which hand-builds its response instead -- see that
/// file's header for why).
///
/// `unitValue` comes back as a JSON *string*, not a number -- Postgres
/// `numeric` columns round-trip through Drizzle as strings by default
/// (schema.ts's own header comment on `productVariants` says so, and
/// proximity_web's `types.ts` makes the identical note for
/// `serviceRadiusKm`/`platformCommissionPct`). Parsed to a `double` here so
/// the variant selector can format "500 g" / "1 kg" without every call site
/// re-parsing it.
class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.productId,
    required this.unitValue,
    required this.unitLabel,
    this.sku,
    required this.price,
    this.mrp,
    required this.stockQty,
    required this.stockStatus,
    required this.isActive,
  });

  final String id;
  final String productId;
  final double unitValue;
  final String unitLabel;
  final String? sku;
  final int price;
  final int? mrp;
  final int stockQty;
  final String stockStatus;
  final bool isActive;

  bool get inStock => stockStatus != 'out_of_stock';

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: json['id'] as String,
      productId: json['productId'] as String,
      unitValue: double.parse(json['unitValue'] as String),
      unitLabel: json['unitLabel'] as String,
      sku: json['sku'] as String?,
      price: json['price'] as int,
      mrp: json['mrp'] as int?,
      stockQty: json['stockQty'] as int,
      stockStatus: json['stockStatus'] as String,
      isActive: json['isActive'] as bool,
    );
  }
}
