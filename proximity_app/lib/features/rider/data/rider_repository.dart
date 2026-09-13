import 'package:dio/dio.dart';

import 'models/rider_order.dart';
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

  /// Sprint 9 -- online/offline toggle (§8.5). 'on_delivery' is never sent
  /// from here -- only rpc_assign_rider/rpc_rider_update_status set it,
  /// system-side (routes/riders.ts's own zod enum already refuses anything
  /// else at the HTTP layer; this method's own signature does too, one
  /// layer earlier).
  Future<RiderProfile> setStatus(String status) async {
    assert(status == 'offline' || status == 'available');
    final response = await _dio.patch<Map<String, dynamic>>('/v1/rider/riders/me/status', data: {'status': status});
    return RiderProfile.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  /// Sprint 9 -- periodic pings while on_delivery (§8.5), feeding
  /// rpc_assign_rider's nearest-rider search. Fire-and-forget from the
  /// caller's point of view (RiderLocationPinger swallows failures rather
  /// than surfacing a transient network blip as a rider-facing error).
  Future<void> updateLocation({required double lat, required double lng}) {
    return _dio.patch('/v1/rider/riders/me/location', data: {'lat': lat, 'lng': lng});
  }

  /// The rider's own active (not completed/cancelled) assigned orders --
  /// what RiderHomeScreen renders, and what a Realtime assignment ping
  /// (rider_assignment_channel.dart) triggers a re-fetch of.
  Future<List<RiderOrder>> getMyOrders() async {
    final response = await _dio.get<Map<String, dynamic>>('/v1/rider/riders/me/orders');
    return (response.data!['data'] as List)
        .map((e) => RiderOrder.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// §8.5's "Accept" step (rpc_rider_accept_order, migrations/041) -- a real
  /// gate, not just a UI affordance: rpc_rider_update_status refuses
  /// 'picked_up' for an order with no matching accept record yet.
  Future<void> acceptOrder(String orderId) {
    return _dio.post('/v1/rider/riders/me/orders/$orderId/accept');
  }

  /// The status ladder (rpc_rider_update_status, migrations/042):
  /// picked_up -> out_for_delivery -> delivered. See that migration's own
  /// header for exactly how each step maps onto orders.status.
  Future<void> updateOrderStatus(String orderId, String status) {
    assert(status == 'picked_up' || status == 'out_for_delivery' || status == 'delivered');
    return _dio.post('/v1/rider/riders/me/orders/$orderId/status', data: {'status': status});
  }

  /// Sprint 12 -- the other half of §8.5's "Accept," made real
  /// (rpc_rider_decline_order, migrations/048). Only legal before Accept --
  /// see that migration's own header for the full design and why a
  /// post-accept "I can't do this" goes through the shop instead. Always
  /// sends an explicit JSON body (even empty) -- routes/riders.ts's own
  /// zValidator on this route requires one.
  Future<void> declineOrder(String orderId, {String? reason}) {
    return _dio.post(
      '/v1/rider/riders/me/orders/$orderId/decline',
      data: {if (reason != null && reason.isNotEmpty) 'reason': reason},
    );
  }
}
