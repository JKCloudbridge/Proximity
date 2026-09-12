/// Mirrors one entry of `GET /v1/shops/:shopId/fulfillment-slots`
/// (routes/checkout.ts, Sprint 7) -- §4.6's real slot endpoint, the one
/// Sprints 4/5/6 each deferred here by name.
///
/// Unavailable slots come back in the list rather than being filtered out
/// server-side, carrying the reason with them -- §7.4 asks for exactly that
/// ("disabled slots shown grayed with a reason rather than hidden"), because
/// "6-8 PM is greyed out because the shop shuts at 6" tells a buyer
/// something useful, while a silently missing row just looks broken.
class FulfillmentSlot {
  const FulfillmentSlot({
    required this.slotStart,
    required this.slotEnd,
    required this.label,
    required this.available,
    this.unavailableReason,
  });

  final DateTime slotStart;
  final DateTime slotEnd;

  /// Pre-formatted "HH:MM - HH:MM" in IST, built server-side. Unlike
  /// NextSlotBadge's countdown (§7.2), which has to be computed live on the
  /// device, a slot's own window label never changes once generated -- so
  /// this one genuinely can come down as a string.
  final String label;
  final bool available;
  final String? unavailableReason;

  factory FulfillmentSlot.fromJson(Map<String, dynamic> json) {
    return FulfillmentSlot(
      slotStart: DateTime.parse(json['slotStart'] as String),
      slotEnd: DateTime.parse(json['slotEnd'] as String),
      label: json['label'] as String,
      available: json['available'] as bool,
      unavailableReason: json['unavailableReason'] as String?,
    );
  }
}

/// One day's worth of slots for one shop. `unsupported` is the shop saying
/// it doesn't offer the fulfillment type that was asked about at all (§4.4's
/// `supports_pickup`/`supports_delivery`) -- distinct from "offers it, but
/// has nothing open that day," which is an empty/greyed-out `slots` list.
class FulfillmentSlotDay {
  const FulfillmentSlotDay({required this.date, required this.slots, required this.unsupported});

  final String date;
  final List<FulfillmentSlot> slots;
  final bool unsupported;

  factory FulfillmentSlotDay.fromJson(Map<String, dynamic> json) {
    return FulfillmentSlotDay(
      date: json['date'] as String,
      slots: (json['slots'] as List<dynamic>).map((e) => FulfillmentSlot.fromJson(e as Map<String, dynamic>)).toList(),
      unsupported: json['unsupported'] as bool,
    );
  }
}
