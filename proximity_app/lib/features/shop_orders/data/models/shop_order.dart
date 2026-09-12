/// Mirrors `GET /v1/shop/shops/:shopId/orders` (routes/shopOrders.ts,
/// Sprint 9) -- always camelCase, hand-built by that route the same way
/// every route in this codebase has since Sprint 2's "re-select via
/// Drizzle" fix.
class ShopOrder {
  const ShopOrder({
    required this.id,
    required this.status,
    required this.fulfillmentType,
    this.deliveryFulfilledBy,
    this.riderId,
    required this.slotStart,
    required this.slotEnd,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.itemCount,
    required this.createdAt,
  });

  final String id;
  final String status;
  final String fulfillmentType; // pickup | delivery
  final String? deliveryFulfilledBy; // shop | platform_rider | null
  final String? riderId;
  final DateTime slotStart;
  final DateTime slotEnd;
  final int subtotal;
  final int deliveryFee;
  final int total;
  final int itemCount;
  final DateTime createdAt;

  bool get isPlatformRiderDelivery => deliveryFulfilledBy == 'platform_rider';

  factory ShopOrder.fromJson(Map<String, dynamic> json) {
    return ShopOrder(
      id: json['id'] as String,
      status: json['status'] as String,
      fulfillmentType: json['fulfillmentType'] as String,
      deliveryFulfilledBy: json['deliveryFulfilledBy'] as String?,
      riderId: json['riderId'] as String?,
      slotStart: DateTime.parse(json['slotStart'] as String),
      slotEnd: DateTime.parse(json['slotEnd'] as String),
      subtotal: json['subtotal'] as int,
      deliveryFee: json['deliveryFee'] as int,
      total: json['total'] as int,
      itemCount: json['itemCount'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
