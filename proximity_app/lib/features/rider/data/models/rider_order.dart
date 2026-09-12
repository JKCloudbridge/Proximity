/// Mirrors `GET /v1/rider/riders/me/orders`'s row shape (routes/riders.ts,
/// Sprint 9) -- always camelCase (that route builds its response by hand,
/// same discipline every route in this codebase has followed since Sprint
/// 2's "re-select via Drizzle, never the raw RPC row" fix), so no
/// snake_case fallback is needed here unlike RiderProfile's own defensive
/// `pick`.
class RiderOrder {
  const RiderOrder({
    required this.id,
    required this.status,
    required this.riderLadderStep,
    required this.slotStart,
    required this.slotEnd,
    required this.shopName,
    required this.shopAddressLine,
    required this.shopCity,
    required this.createdAt,
  });

  final String id;
  final String status; // orders.status -- confirmed/preparing/ready_for_pickup/out_for_delivery/completed
  // The most recent of THIS rider's own ladder words logged for this order
  // (rider_accepted/picked_up/out_for_delivery/delivered), or null before
  // Accept. Needed because `status` alone can't distinguish "picked up" from
  // "out for delivery re-ping" -- both leave orders.status at
  // 'out_for_delivery' (migrations/042's own header explains why). This is
  // what RiderOrderCard uses to decide which single ladder button to show
  // next, not `status`.
  final String? riderLadderStep;
  final DateTime slotStart;
  final DateTime slotEnd;
  final String shopName;
  final String shopAddressLine;
  final String shopCity;
  final DateTime createdAt;

  factory RiderOrder.fromJson(Map<String, dynamic> json) {
    return RiderOrder(
      id: json['id'] as String,
      status: json['status'] as String,
      riderLadderStep: json['riderLadderStep'] as String?,
      slotStart: DateTime.parse(json['slotStart'] as String),
      slotEnd: DateTime.parse(json['slotEnd'] as String),
      shopName: json['shopName'] as String,
      shopAddressLine: json['shopAddressLine'] as String,
      shopCity: json['shopCity'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
