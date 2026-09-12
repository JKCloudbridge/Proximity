import 'package:dio/dio.dart';

import 'models/checkout_config.dart';
import 'models/fulfillment_slot.dart';
import 'models/order_group.dart';

/// Sprint 7 (§7.4). Everything except the slot read needs a signed-in buyer
/// (routes/checkout.ts gates `/checkout/*`, `/orders*`, `/order-groups/*`
/// and `/discounts/*` behind authMiddleware); the slot endpoint is public,
/// same as the rest of the shop-browsing surface.
class CheckoutRepository {
  CheckoutRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<CheckoutConfig> getConfig() async {
    final response = await _dio.get<Map<String, dynamic>>('/v1/checkout/config');
    return CheckoutConfig.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  /// `date` is an IST calendar date ("YYYY-MM-DD"), not an instant -- every
  /// date in the slot path is a wall-clock day (lib/slots.ts's header
  /// explains the single-country assumption behind that).
  Future<FulfillmentSlotDay> getSlots({
    required String shopId,
    required String date,
    required String type,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/v1/shops/$shopId/fulfillment-slots',
      queryParameters: {'date': date, 'type': type},
    );
    return FulfillmentSlotDay.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  /// Returns `null` when the code isn't usable -- the backend answers 404/400
  /// with a typed error code, and "this code doesn't work" isn't an
  /// exceptional condition worth throwing over at the call site (the
  /// checkout screen just shows the message inline). Any other failure still
  /// propagates.
  Future<DiscountPreview?> previewDiscount({required String code, required int subtotal}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/v1/discounts/$code',
        queryParameters: {'subtotal': subtotal},
      );
      return DiscountPreview.fromJson(response.data!['data'] as Map<String, dynamic>);
    } on DioException catch (err) {
      final status = err.response?.statusCode;
      if (status == 404 || status == 400) return null;
      rethrow;
    }
  }

  /// The one write in this whole flow -- everything it touches lands
  /// atomically via rpc_place_order (migrations/032) or not at all.
  Future<OrderGroup> placeOrder({
    required List<Map<String, dynamic>> fulfillment,
    String? addressId,
    required String paymentMode,
    String? discountCode,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/v1/orders',
      data: {
        'fulfillment': fulfillment,
        if (addressId != null) 'addressId': addressId,
        'paymentMode': paymentMode,
        if (discountCode != null && discountCode.isNotEmpty) 'discountCode': discountCode,
      },
    );
    return OrderGroup.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  Future<OrderGroup?> getOrderGroup(String id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/v1/order-groups/$id');
      return OrderGroup.fromJson(response.data!['data'] as Map<String, dynamic>);
    } on DioException catch (err) {
      if (err.response?.statusCode == 404) return null;
      rethrow;
    }
  }
}
