/// Mirrors proximity_backend's `riders` row (routes/riders.ts). Field
/// lookups check both camelCase and snake_case keys the way
/// features/addresses/data/models/address.dart's `isDefault`/`is_default`
/// fallback does -- POST /rider/riders now always responds camelCase
/// (routes/riders.ts re-selects via Drizzle after the RPC call rather than
/// returning the raw RPC row, see that file's comment), but this model
/// stays defensive rather than assuming every future caller will too.
class RiderProfile {
  const RiderProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    this.vehicleType,
    this.vehicleNumber,
    this.kycDocumentPath,
    required this.status,
    required this.isVerified,
  });

  final String id;
  final String fullName;
  final String phone;
  final String? vehicleType;
  final String? vehicleNumber;
  final String? kycDocumentPath;
  final String status; // offline | available | on_delivery
  final bool isVerified;

  factory RiderProfile.fromJson(Map<String, dynamic> json) {
    T? pick<T>(String camel, String snake) => (json[camel] ?? json[snake]) as T?;

    return RiderProfile(
      id: json['id'] as String,
      fullName: pick<String>('fullName', 'full_name') ?? '',
      phone: json['phone'] as String? ?? '',
      vehicleType: pick<String>('vehicleType', 'vehicle_type'),
      vehicleNumber: pick<String>('vehicleNumber', 'vehicle_number'),
      kycDocumentPath: pick<String>('kycDocumentUrl', 'kyc_document_url'),
      status: json['status'] as String? ?? 'offline',
      isVerified: pick<bool>('isVerified', 'is_verified') ?? false,
    );
  }
}
