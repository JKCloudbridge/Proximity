/// Mirrors one row of `GET /v1/cart` (routes/cart.ts) -- hand-built
/// server-side (not a raw Drizzle passthrough), same "already camelCase"
/// shape as WishlistItem. Unlike WishlistItem's `product`, `variant`/
/// `product`/`shop` here are never actually null in practice: cart_items.
/// variant_id is `ON DELETE CASCADE` (migrations/023), so a deleted variant
/// takes its cart row down with it -- there's no "row survives, joined data
/// gone" case for a cart item the way a wishlisted-then-deleted *product*
/// can happen (wishlists has no such cascade). `isAvailable` instead
/// captures the "still exists, but deactivated/out-of-stock/shop-suspended"
/// case -- the one way a cart row can go stale without disappearing.
class CartItem {
  const CartItem({
    required this.id,
    required this.quantity,
    required this.addedAt,
    required this.isAvailable,
    required this.variant,
    required this.product,
    required this.shop,
  });

  final String id;
  final int quantity;
  final DateTime addedAt;
  final bool isAvailable;
  final CartItemVariant variant;
  final CartItemProduct product;
  final CartItemShop shop;

  int get lineTotalPaise => variant.price * quantity;

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'] as String,
      quantity: json['quantity'] as int,
      addedAt: DateTime.parse(json['addedAt'] as String),
      isAvailable: json['isAvailable'] as bool,
      variant: CartItemVariant.fromJson(json['variant'] as Map<String, dynamic>),
      product: CartItemProduct.fromJson(json['product'] as Map<String, dynamic>),
      shop: CartItemShop.fromJson(json['shop'] as Map<String, dynamic>),
    );
  }
}

/// A trimmed-down sibling of ProductVariant (features/catalog) -- the cart
/// row only ever needs unit/price/stock, not the full variant shape (no
/// productId/isActive/sku here, since isAvailable above already answers
/// "can this still be checked out").
class CartItemVariant {
  const CartItemVariant({
    required this.id,
    required this.unitValue,
    required this.unitLabel,
    required this.price,
    this.mrp,
    required this.stockStatus,
  });

  final String id;
  final double unitValue;
  final String unitLabel;
  final int price;
  final int? mrp;
  final String stockStatus;

  bool get inStock => stockStatus != 'out_of_stock';

  factory CartItemVariant.fromJson(Map<String, dynamic> json) {
    return CartItemVariant(
      id: json['id'] as String,
      // Same Postgres-numeric-as-string round trip ProductVariant's own
      // header documents.
      unitValue: double.parse(json['unitValue'] as String),
      unitLabel: json['unitLabel'] as String,
      price: json['price'] as int,
      mrp: json['mrp'] as int?,
      stockStatus: json['stockStatus'] as String,
    );
  }
}

class CartItemProduct {
  const CartItemProduct({required this.id, required this.name, this.isVeg, this.imageUrl});

  final String id;
  final String name;
  final bool? isVeg;
  final String? imageUrl;

  factory CartItemProduct.fromJson(Map<String, dynamic> json) {
    return CartItemProduct(
      id: json['id'] as String,
      name: json['name'] as String,
      isVeg: json['isVeg'] as bool?,
      imageUrl: json['imageUrl'] as String?,
    );
  }
}

/// The cart screen only needs id/name/logo to render a section header --
/// the fulfillment fields below exist for checkout (§7.4 step 1), which has
/// to know which options each shop actually offers before it can ask the
/// buyer to choose one. They ride along on `GET /v1/cart` rather than
/// costing a per-shop request on the checkout screen; see routes/cart.ts's
/// own comment on that select.
class CartItemShop {
  const CartItemShop({
    required this.id,
    required this.name,
    this.logoUrl,
    required this.supportsPickup,
    required this.supportsDelivery,
    required this.deliveryMode,
    required this.minOrderValue,
  });

  final String id;
  final String name;
  final String? logoUrl;
  final bool supportsPickup;
  final bool supportsDelivery;

  /// §1.3: `self` (the shop delivers, never a fee), `platform` (always a
  /// Proximity rider, fee applies), or `both` (the buyer picks per order).
  final String deliveryMode;
  final int minOrderValue;

  /// True only when §1.3 leaves a real choice to make -- otherwise the
  /// delivery fulfiller is determined by the shop's own mode and the
  /// checkout screen shouldn't be asking.
  bool get deliveryFulfillerIsChoosable => deliveryMode == 'both';

  /// The one legal fulfiller when there's no choice; null when there is one.
  String? get fixedDeliveryFulfilledBy => switch (deliveryMode) {
        'self' => 'shop',
        'platform' => 'platform_rider',
        _ => null,
      };

  factory CartItemShop.fromJson(Map<String, dynamic> json) {
    return CartItemShop(
      id: json['id'] as String,
      name: json['name'] as String,
      logoUrl: json['logoUrl'] as String?,
      // Defaulted rather than required-from-JSON: these were added to the
      // cart response in Sprint 7, and a cached/older response shape
      // shouldn't hard-crash the cart screen, which doesn't use them at all.
      supportsPickup: json['supportsPickup'] as bool? ?? true,
      supportsDelivery: json['supportsDelivery'] as bool? ?? true,
      deliveryMode: json['deliveryMode'] as String? ?? 'self',
      minOrderValue: json['minOrderValue'] as int? ?? 0,
    );
  }
}
