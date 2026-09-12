import 'package:dio/dio.dart';

import 'models/invoice_link.dart';
import 'models/payment_order.dart';
import 'payment_gateway.dart';

/// Sprint 8. Everything here needs a signed-in buyer (routes/payments.ts and
/// routes/invoices.ts both gate their paths behind authMiddleware) -- same
/// convention every own-user-data repository in this project already
/// follows (CartRepository, WishlistRepository, CheckoutRepository).
class PaymentRepository {
  PaymentRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<PaymentOrder> createPaymentOrder(String orderGroupId) async {
    final response = await _dio.post<Map<String, dynamic>>('/v1/order-groups/$orderGroupId/payment-order');
    return PaymentOrder.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  /// Throws on a non-2xx (a signature the backend rejects, or a genuine
  /// server error) -- the checkout screen treats either the same way as a
  /// gateway-side payment failure: the order still exists, unpaid, and the
  /// confirmation screen's own retry affordance covers trying again.
  Future<void> verifyPayment({required String orderGroupId, required PaymentGatewaySuccess success}) async {
    await _dio.post<Map<String, dynamic>>(
      '/v1/order-groups/$orderGroupId/verify-payment',
      data: {
        'gatewayOrderId': success.gatewayOrderId,
        'gatewayPaymentId': success.gatewayPaymentId,
        'gatewaySignature': success.gatewaySignature,
      },
    );
  }

  /// Returns `null` when no invoice exists yet (still-unconfirmed order, or
  /// generation genuinely hasn't happened) -- same "absence isn't an
  /// exceptional condition" convention `getMyProfile()`/`getShop()` already
  /// use elsewhere in this project for a 404.
  Future<InvoiceLink?> getInvoice(String orderId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/v1/orders/$orderId/invoice');
      return InvoiceLink.fromJson(response.data!['data'] as Map<String, dynamic>);
    } on DioException catch (err) {
      if (err.response?.statusCode == 404) return null;
      rethrow;
    }
  }
}
