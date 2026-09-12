import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/payment_gateway.dart';
import 'providers/payment_providers.dart';

/// Sprint 8 -- one shared "try to collect an online payment for this
/// order_group" flow, used by both the checkout screen (immediately after
/// placement) and the confirmation screen's "Complete payment" retry for a
/// group that's still `pending`. One implementation so the two call sites
/// can't drift into different create-order/pay/verify sequencing.
///
/// Never throws, and never reports success/failure directly -- a gateway or
/// network failure, a declined card, and a buyer dismissing the Checkout
/// sheet are all just "didn't get paid this attempt," and in every case the
/// order_group's own `paymentStatus` (re-fetched by the caller, typically by
/// invalidating `orderGroupProvider`) is the one honest source of truth for
/// what actually happened -- not a value this function invents on top of it.
Future<void> attemptOnlinePayment(WidgetRef ref, String orderGroupId) async {
  final repo = ref.read(paymentRepositoryProvider);
  try {
    final paymentOrder = await repo.createPaymentOrder(orderGroupId);
    final gateway = paymentGatewayFor(paymentOrder.gateway);
    final result = await gateway.pay(PaymentGatewayRequest(
      gatewayOrderId: paymentOrder.gatewayOrderId,
      amountPaise: paymentOrder.amountPaise,
      currency: paymentOrder.currency,
      keyId: paymentOrder.keyId ?? '',
    ));
    if (result.isSuccess) {
      await repo.verifyPayment(orderGroupId: orderGroupId, success: result.success!);
    }
  } catch (_) {
    // Deliberately swallowed -- see this function's own doc comment. The
    // confirmation screen's "still pending, complete payment" state is the
    // visible signal, not a snackbar that a buyer already mid-navigation
    // (checkout_screen.dart's call site) may never even see.
  }
}
