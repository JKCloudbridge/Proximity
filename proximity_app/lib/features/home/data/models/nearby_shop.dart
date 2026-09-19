/// Mirrors `GET /v1/shops/near` (routes/shops.ts, Sprint 4) -- already
/// camelCase and already sorted by distance server-side, so nothing here
/// re-sorts or re-derives distance.
class NearbyShop {
  const NearbyShop({
    required this.id,
    required this.name,
    this.description,
    this.logoUrl,
    this.coverImageUrl,
    required this.city,
    required this.addressLine,
    required this.serviceRadiusKm,
    required this.supportsPickup,
    required this.supportsDelivery,
    required this.deliveryMode,
    required this.minOrderValue,
    required this.distanceKm,
    this.nextSlot,
  });

  final String id;
  final String name;
  final String? description;
  final String? logoUrl;
  final String? coverImageUrl;
  final String city;
  final String addressLine;
  final double serviceRadiusKm;
  final bool supportsPickup;
  final bool supportsDelivery;
  final String deliveryMode;
  final int minOrderValue;
  final double distanceKm;
  final NextSlot? nextSlot;

  factory NearbyShop.fromJson(Map<String, dynamic> json) {
    return NearbyShop(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      logoUrl: json['logoUrl'] as String?,
      coverImageUrl: json['coverImageUrl'] as String?,
      city: json['city'] as String,
      addressLine: json['addressLine'] as String,
      serviceRadiusKm: (json['serviceRadiusKm'] as num).toDouble(),
      supportsPickup: json['supportsPickup'] as bool,
      supportsDelivery: json['supportsDelivery'] as bool,
      deliveryMode: json['deliveryMode'] as String,
      minOrderValue: json['minOrderValue'] as int,
      distanceKm: (json['distanceKm'] as num).toDouble(),
      nextSlot: json['nextSlot'] != null ? NextSlot.fromJson(json['nextSlot'] as Map<String, dynamic>) : null,
    );
  }

  // Sprint 15 -- local cache round-trip (core/cache), not the network.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'logoUrl': logoUrl,
      'coverImageUrl': coverImageUrl,
      'city': city,
      'addressLine': addressLine,
      'serviceRadiusKm': serviceRadiusKm,
      'supportsPickup': supportsPickup,
      'supportsDelivery': supportsDelivery,
      'deliveryMode': deliveryMode,
      'minOrderValue': minOrderValue,
      'distanceKm': distanceKm,
      'nextSlot': nextSlot?.toJson(),
    };
  }
}

/// §7.2's live countdown badge data -- just the boundary timestamps.
/// [NextSlotBadge] decides "now vs. upcoming" and formats the countdown
/// itself, tick by tick, off the device's own clock -- baking a rendered
/// string like "40 min" into the response would go stale the instant a
/// minute passed, since this list isn't re-fetched every second.
class NextSlot {
  const NextSlot({required this.slotStart, required this.slotEnd});

  final DateTime slotStart;
  final DateTime slotEnd;

  factory NextSlot.fromJson(Map<String, dynamic> json) {
    return NextSlot(
      slotStart: DateTime.parse(json['slotStart'] as String),
      slotEnd: DateTime.parse(json['slotEnd'] as String),
    );
  }

  Map<String, dynamic> toJson() => {'slotStart': slotStart.toIso8601String(), 'slotEnd': slotEnd.toIso8601String()};
}
