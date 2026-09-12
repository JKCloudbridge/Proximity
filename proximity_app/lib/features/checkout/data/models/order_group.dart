/// Mirrors `POST /v1/orders` / `GET /v1/order-groups/:id`
/// (routes/checkout.ts, Sprint 7) -- §4.8's one-charge/N-shops shape as the
/// confirmation screen actually consumes it.
///
/// The nesting here is the whole point of §4.8's redesign and §7.4 step 5's
/// instruction: ONE group (what the buyer paid, once) containing N orders
/// (one per shop, each with its own fulfillment type, slot, status and fee
/// line) -- "never a single merged summary line," per that section.
class OrderGroup {
  const OrderGroup({
    required this.id,
    required this.paymentMode,
    required this.paymentStatus,
    required this.subtotal,
    required this.discountValue,
    required this.deliveryFeeTotal,
    required this.total,
    required this.createdAt,
    this.discountCode,
    required this.orders,
  });

  final String id;
  final String paymentMode;
  final String paymentStatus;
  final int subtotal;
  final int discountValue;
  final int deliveryFeeTotal;

  /// The ONE amount charged (§4.8's own comment on this column). Always
  /// equals the sum of every child order's `total` -- rpc_place_order
  /// asserts that invariant rather than trusting it (migrations/032 step 9).
  final int total;
  final DateTime createdAt;
  final String? discountCode;
  final List<OrderGroupOrder> orders;

  bool get isPayAtShop => paymentMode == 'pay_at_shop';

  factory OrderGroup.fromJson(Map<String, dynamic> json) {
    final discount = json['discount'] as Map<String, dynamic>?;
    return OrderGroup(
      id: json['id'] as String,
      paymentMode: json['paymentMode'] as String,
      paymentStatus: json['paymentStatus'] as String,
      subtotal: json['subtotal'] as int,
      discountValue: json['discountValue'] as int,
      deliveryFeeTotal: json['deliveryFeeTotal'] as int,
      total: json['total'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      discountCode: discount?['code'] as String?,
      orders: (json['orders'] as List<dynamic>).map((e) => OrderGroupOrder.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

/// One shop's sub-order inside a checkout.
class OrderGroupOrder {
  const OrderGroupOrder({
    required this.id,
    required this.shopId,
    required this.shopName,
    this.shopLogoUrl,
    required this.fulfillmentType,
    this.deliveryFulfilledBy,
    required this.slotStart,
    required this.slotEnd,
    required this.status,
    required this.subtotal,
    required this.discountValue,
    required this.deliveryFee,
    required this.total,
    this.addressLine,
    required this.items,
  });

  final String id;
  final String shopId;
  final String shopName;
  final String? shopLogoUrl;
  final String fulfillmentType;

  /// `'shop'` or `'platform_rider'` -- NULL for pickup. Worth surfacing to
  /// the buyer, not just storing: "delivered by the shop" and "delivered by
  /// a Proximity rider" are different promises, and only the second one ever
  /// carries a fee (§1.3).
  final String? deliveryFulfilledBy;
  final DateTime slotStart;
  final DateTime slotEnd;
  final String status;
  final int subtotal;
  final int discountValue;
  final int deliveryFee;
  final int total;
  final String? addressLine;
  final List<OrderGroupItem> items;

  bool get isPickup => fulfillmentType == 'pickup';
  bool get isRiderDelivery => deliveryFulfilledBy == 'platform_rider';

  factory OrderGroupOrder.fromJson(Map<String, dynamic> json) {
    final shop = json['shop'] as Map<String, dynamic>?;
    final address = json['address'] as Map<String, dynamic>?;
    return OrderGroupOrder(
      id: json['id'] as String,
      shopId: shop?['id'] as String? ?? '',
      shopName: shop?['name'] as String? ?? 'Shop',
      shopLogoUrl: shop?['logoUrl'] as String?,
      fulfillmentType: json['fulfillmentType'] as String,
      deliveryFulfilledBy: json['deliveryFulfilledBy'] as String?,
      slotStart: DateTime.parse(json['slotStart'] as String),
      slotEnd: DateTime.parse(json['slotEnd'] as String),
      status: json['status'] as String,
      subtotal: json['subtotal'] as int,
      discountValue: json['discountValue'] as int,
      deliveryFee: json['deliveryFee'] as int,
      total: json['total'] as int,
      addressLine: address?['line1'] as String?,
      items: (json['items'] as List<dynamic>).map((e) => OrderGroupItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

/// One line of a sub-order. These are §9's immutable snapshot (name/unit/
/// price copied at order time, migrations/029) -- deliberately NOT joined
/// live from the catalog, so a later rename or reprice can't rewrite what
/// the buyer sees they ordered.
class OrderGroupItem {
  const OrderGroupItem({
    required this.id,
    required this.productName,
    required this.variantName,
    required this.quantity,
    required this.unitPrice,
  });

  final String id;
  final String productName;
  final String variantName;
  final int quantity;
  final int unitPrice;

  int get lineTotal => unitPrice * quantity;

  factory OrderGroupItem.fromJson(Map<String, dynamic> json) {
    return OrderGroupItem(
      id: json['id'] as String,
      productName: json['productName'] as String,
      variantName: json['variantName'] as String,
      quantity: json['quantity'] as int,
      unitPrice: json['unitPrice'] as int,
    );
  }
}
