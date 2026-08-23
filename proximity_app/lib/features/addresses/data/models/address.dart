/// Mirrors proximity_backend's GET/POST /v1/addresses shape
/// (routes/addresses.ts). `lat`/`lng` are sent to and returned from the
/// server as a flat `location: {lat, lng}` object -- the backend converts
/// that to/from the `GEOGRAPHY(Point,4326)` column itself (see that
/// route's file header for why it's a raw SQL fragment rather than a
/// Drizzle column type).
class Address {
  const Address({
    required this.id,
    this.label,
    required this.line1,
    this.line2,
    required this.city,
    required this.state,
    required this.pincode,
    required this.lat,
    required this.lng,
    required this.isDefault,
  });

  final String id;
  final String? label;
  final String line1;
  final String? line2;
  final String city;
  final String state;
  final String pincode;
  final double lat;
  final double lng;
  final bool isDefault;

  String get shortLine => label?.isNotEmpty == true ? '$label · $line1' : line1;

  factory Address.fromJson(Map<String, dynamic> json) {
    // The server's `location` column round-trips as GeoJSON
    // ({"type":"Point","coordinates":[lng,lat]}) via postgres.js/PostGIS's
    // default text representation, hence [lng, lat] order (GeoJSON's, not
    // the {lat,lng} shape POST accepts) -- accounted for explicitly here
    // rather than assumed, since getting geo coordinate order backwards is
    // a classic, silent bug (valid-looking numbers, wrong location).
    final location = json['location'] as Map<String, dynamic>?;
    final coords = location?['coordinates'] as List<dynamic>?;

    return Address(
      id: json['id'] as String,
      label: json['label'] as String?,
      line1: json['line1'] as String,
      line2: json['line2'] as String?,
      city: json['city'] as String,
      state: json['state'] as String,
      pincode: json['pincode'] as String,
      lng: coords != null ? (coords[0] as num).toDouble() : 0,
      lat: coords != null ? (coords[1] as num).toDouble() : 0,
      isDefault: json['isDefault'] as bool? ?? json['is_default'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toCreateJson() => {
        if (label != null) 'label': label,
        'line1': line1,
        if (line2 != null) 'line2': line2,
        'city': city,
        'state': state,
        'pincode': pincode,
        'location': {'lat': lat, 'lng': lng},
      };
}
