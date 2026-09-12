/// Mirrors `GET /v1/order-groups` (routes/checkout.ts, Sprint 9) -- a
/// deliberately thin row, not `OrderGroup`'s full per-item nesting. This is
/// what `MyOrdersScreen` lists; tapping a row still pushes
/// `OrderConfirmationScreen`, which re-fetches the full `OrderGroup` via the
/// existing `GET /v1/order-groups/:id`. See that route's own header for why
/// this list exists at all and why it's deliberately NOT §11's Sprint 10
/// "Order history" feature.
class OrderGroupSummary {
  const OrderGroupSummary({
    required this.id,
    required this.paymentMode,
    required this.paymentStatus,
    required this.total,
    required this.createdAt,
    required this.shops,
  });

  final String id;
  final String paymentMode;
  final String paymentStatus;
  final int total;
  final DateTime createdAt;
  final List<OrderGroupSummaryShop> shops;

  factory OrderGroupSummary.fromJson(Map<String, dynamic> json) {
    return OrderGroupSummary(
      id: json['id'] as String,
      paymentMode: json['paymentMode'] as String,
      paymentStatus: json['paymentStatus'] as String,
      total: json['total'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      shops: (json['shops'] as List<dynamic>)
          .map((e) => OrderGroupSummaryShop.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class OrderGroupSummaryShop {
  const OrderGroupSummaryShop({required this.shopId, required this.shopName, required this.status});

  final String shopId;
  final String shopName;
  final String status;

  factory OrderGroupSummaryShop.fromJson(Map<String, dynamic> json) {
    return OrderGroupSummaryShop(
      shopId: json['shopId'] as String,
      shopName: json['shopName'] as String,
      status: json['status'] as String,
    );
  }
}
