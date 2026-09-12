import '../../../home/data/models/nearby_shop.dart';

/// Mirrors `GET /v1/shops/:id` (routes/shops.ts, Sprint 5) -- the shop-detail
/// header's data. Deliberately its own model rather than reusing [NearbyShop]
/// even though the two overlap heavily: this one has no `distanceKm` (the
/// detail route doesn't take a buyer lat/lng at all) and does carry
/// `description`/`pincode`, which Home's card never needed. [NextSlot] is
/// shared as-is -- same shape, same badge.
class ShopDetail {
  const ShopDetail({
    required this.id,
    required this.name,
    this.description,
    this.logoUrl,
    this.coverImageUrl,
    required this.city,
    required this.addressLine,
    required this.pincode,
    required this.serviceRadiusKm,
    required this.supportsPickup,
    required this.supportsDelivery,
    required this.deliveryMode,
    required this.minOrderValue,
    this.nextSlot,
  });

  final String id;
  final String name;
  final String? description;
  final String? logoUrl;
  final String? coverImageUrl;
  final String city;
  final String addressLine;
  final String pincode;
  final double serviceRadiusKm;
  final bool supportsPickup;
  final bool supportsDelivery;
  final String deliveryMode;
  final int minOrderValue;
  final NextSlot? nextSlot;

  factory ShopDetail.fromJson(Map<String, dynamic> json) {
    return ShopDetail(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      logoUrl: json['logoUrl'] as String?,
      coverImageUrl: json['coverImageUrl'] as String?,
      city: json['city'] as String,
      addressLine: json['addressLine'] as String,
      pincode: json['pincode'] as String,
      serviceRadiusKm: (json['serviceRadiusKm'] as num).toDouble(),
      supportsPickup: json['supportsPickup'] as bool,
      supportsDelivery: json['supportsDelivery'] as bool,
      deliveryMode: json['deliveryMode'] as String,
      minOrderValue: json['minOrderValue'] as int,
      nextSlot: json['nextSlot'] != null ? NextSlot.fromJson(json['nextSlot'] as Map<String, dynamic>) : null,
    );
  }
}
