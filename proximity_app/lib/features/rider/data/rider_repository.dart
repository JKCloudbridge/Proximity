import 'package:dio/dio.dart';

import 'models/rider_profile.dart';

class RiderRepository {
  RiderRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  /// Idempotent -- backend upserts (migrations/015), so this doubles as
  /// "create" and "resubmit after a KYC fix" with no separate update call.
  Future<RiderProfile> createOrUpdateProfile({
    required String fullName,
    required String phone,
    String? vehicleType,
    String? vehicleNumber,
    String? kycDocumentPath,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/v1/rider/riders',
      data: {
        'fullName': fullName,
        'phone': phone,
        if (vehicleType != null) 'vehicleType': vehicleType,
        if (vehicleNumber != null) 'vehicleNumber': vehicleNumber,
        if (kycDocumentPath != null) 'kycDocumentUrl': kycDocumentPath,
      },
    );
    return RiderProfile.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  /// Null (not a thrown error) when the caller has no rider profile yet --
  /// callers use this to decide "show the onboarding form" vs. "show
  /// status," so a 404 here is an expected, common case, not a failure.
  Future<RiderProfile?> getMyProfile() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/v1/rider/riders/me');
      return RiderProfile.fromJson(response.data!['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }
}
