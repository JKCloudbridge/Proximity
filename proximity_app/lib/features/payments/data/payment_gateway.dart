/// Sprint 8 -- SPRINT_PLANNING.md §1.4's Flutter half of the PaymentGateway
/// abstraction (the Edge Function's own half is
/// proximity_backend/supabase/functions/api/lib/payments/types.ts --
/// deliberately not shared code between the two languages, same "each side
/// owns its own types" precedent every route/model pair in this project
/// already follows).
///
/// One method, `pay()`, because that's the only thing this app's checkout
/// screen actually needs from a gateway on-device: hand it what
/// `POST /v1/order-groups/:id/payment-order` returned, get back either a
/// verified success (with the fields `POST .../verify-payment` needs) or a
/// typed failure/cancellation. Order creation and signature verification
/// both happen server-side (the backend's own PaymentGateway, not this one)
/// -- this interface is intentionally thin, matching §1.4's own "a thin
/// Flutter wrapper" wording.
abstract class PaymentGateway {
  Future<PaymentGatewayResult> pay(PaymentGatewayRequest request);
}

class PaymentGatewayRequest {
  const PaymentGatewayRequest({
    required this.gatewayOrderId,
    required this.amountPaise,
    required this.currency,
    required this.keyId,
    this.buyerName,
    this.buyerEmail,
    this.buyerPhone,
  });

  final String gatewayOrderId;
  final int amountPaise;
  final String currency;
  final String keyId;
  final String? buyerName;
  final String? buyerEmail;
  final String? buyerPhone;
}

/// Mirrors what `POST /v1/order-groups/:id/verify-payment` needs verbatim
/// (checkout_repository.dart's verifyPayment) -- no gateway-specific shape
/// leaks past this class.
class PaymentGatewaySuccess {
  const PaymentGatewaySuccess({
    required this.gatewayOrderId,
    required this.gatewayPaymentId,
    required this.gatewaySignature,
  });

  final String gatewayOrderId;
  final String gatewayPaymentId;
  final String gatewaySignature;
}

/// A result, not an exception -- a buyer cancelling the Checkout sheet or a
/// card being declined is an expected, non-exceptional outcome (same
/// "expected input, not a crash" reasoning routes/checkout.ts's own header
/// applies to a bad discount code), not something the checkout screen should
/// have to unwrap from a try/catch alongside genuine network failures.
class PaymentGatewayResult {
  const PaymentGatewayResult._({this.success, this.errorMessage});

  factory PaymentGatewayResult.success(PaymentGatewaySuccess success) =>
      PaymentGatewayResult._(success: success);

  factory PaymentGatewayResult.failure(String message) => PaymentGatewayResult._(errorMessage: message);

  final PaymentGatewaySuccess? success;
  final String? errorMessage;

  bool get isSuccess => success != null;
}
