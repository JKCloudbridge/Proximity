/// Mirrors `GET /v1/checkout/config` (routes/checkout.ts, Sprint 7) -- the
/// admin-controlled numbers the review step needs to show a total before the
/// buyer commits (§1.3: the rider delivery fee is a platform setting, never
/// a per-shop one, so it comes from here rather than off any shop record).
///
/// Read-only preview input. `rpc_place_order` recomputes all of this itself
/// at placement and is the authority on what actually gets charged -- see
/// routes/checkout.ts's header for why the preview is a thin read rather
/// than a second implementation of the placement math.
class CheckoutConfig {
  const CheckoutConfig({
    required this.platformRiderDeliveryFee,
    required this.slotMinutes,
    required this.slotWindowStart,
    required this.slotWindowEnd,
  });

  /// Paise (§1.7's paise-integer money convention), applied once per
  /// shop-group that a Proximity rider is delivering -- never to pickup or
  /// to a shop delivering its own order (§1.3, enforced by orders' own CHECK
  /// constraint in migrations/028).
  final int platformRiderDeliveryFee;
  final int slotMinutes;
  final String slotWindowStart;
  final String slotWindowEnd;

  factory CheckoutConfig.fromJson(Map<String, dynamic> json) {
    return CheckoutConfig(
      platformRiderDeliveryFee: json['platformRiderDeliveryFee'] as int,
      slotMinutes: json['slotMinutes'] as int,
      slotWindowStart: json['slotWindowStart'] as String,
      slotWindowEnd: json['slotWindowEnd'] as String,
    );
  }
}

/// Mirrors `GET /v1/discounts/:code?subtotal=N`. `amount` is already
/// computed server-side against the subtotal that was sent, so the client
/// never implements discount rules of its own.
class DiscountPreview {
  const DiscountPreview({
    required this.code,
    required this.name,
    required this.type,
    required this.amount,
    required this.freeShipping,
  });

  final String code;
  final String name;
  final String type;
  final int amount;

  /// `free_shipping` codes waive every platform-rider delivery fee in the
  /// checkout instead of cutting the subtotal, so `amount` is 0 for them --
  /// the saving shows up on the delivery line, not the discount line.
  final bool freeShipping;

  factory DiscountPreview.fromJson(Map<String, dynamic> json) {
    return DiscountPreview(
      code: json['code'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      amount: json['amount'] as int,
      freeShipping: json['freeShipping'] as bool,
    );
  }
}
