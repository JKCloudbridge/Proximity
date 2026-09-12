import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../data/payment_gateway.dart';
import '../../data/payment_repository.dart';
import '../../data/payu_payment_gateway.dart';
import '../../data/razorpay_payment_gateway.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return PaymentRepository(dio: ref.watch(dioProvider));
});

/// §1.4's "swapping ... becomes a config flag, not a rewrite" on the Flutter
/// side: the checkout screen never imports RazorpayPaymentGateway or
/// PayUPaymentGateway directly, it asks this function for "the gateway
/// matching what the backend just told us to use" (the `gateway` field
/// `POST /order-groups/:id/payment-order` returns) -- a plain function, not
/// a provider, since it takes a runtime argument the backend decides, not a
/// build-time constant Riverpod would cache.
PaymentGateway paymentGatewayFor(String gatewayId) {
  switch (gatewayId) {
    case 'razorpay':
      return RazorpayPaymentGateway();
    case 'payu':
      return PayUPaymentGateway();
    default:
      throw UnimplementedError('Unknown payment gateway: $gatewayId');
  }
}
