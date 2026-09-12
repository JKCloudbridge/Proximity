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

class CartItemShop {
  const CartItemShop({required this.id, required this.name, this.logoUrl});

  final String id;
  final String name;
  final String? logoUrl;

  factory CartItemShop.fromJson(Map<String, dynamic> json) {
    return CartItemShop(id: json['id'] as String, name: json['name'] as String, logoUrl: json['logoUrl'] as String?);
  }
}
