/// Mirrors `GET /v1/order-groups` (routes/checkout.ts) -- a deliberately
/// thin row, not `OrderGroup`'s full per-item nesting. Sprint 9 built this
/// as a minimal, unfiltered "My Orders" list; Sprint 10 extended the same
/// route (and this same model, adding `overallStatus`) into the real Order
/// History screen rather than building a second, parallel list surface --
/// see that route's own header for why "extend in place" was the decision,
/// not "replace" or "build alongside." Tapping a row still pushes
/// `OrderConfirmationScreen`, which re-fetches the full `OrderGroup` via the
/// existing `GET /v1/order-groups/:id` -- unchanged since Sprint 9.
class OrderGroupSummary {
  const OrderGroupSummary({
    required this.id,
    required this.paymentMode,
    required this.paymentStatus,
    required this.total,
    required this.createdAt,
    required this.overallStatus,
    required this.shops,
  });

  final String id;
  final String paymentMode;
  final String paymentStatus;
  final int total;
  final DateTime createdAt;
  /// Derived server-side (routes/checkout.ts's `deriveOverallStatus`) from
  /// every child shop-order's own status -- 'active' | 'completed' |
  /// 'cancelled'. Not a real `order_groups` column (§4.8 never gave that
  /// table its own lifecycle status); see the backend's own comment for the
  /// exact precedence rule.
  final String overallStatus;
  final List<OrderGroupSummaryShop> shops;

  factory OrderGroupSummary.fromJson(Map<String, dynamic> json) {
    return OrderGroupSummary(
      id: json['id'] as String,
      paymentMode: json['paymentMode'] as String,
      paymentStatus: json['paymentStatus'] as String,
      total: json['total'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      overallStatus: json['overallStatus'] as String,
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
