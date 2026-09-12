import 'payment_gateway.dart';

/// Sprint 8 -- §1.4/§11's explicit ask: "keep a PayU adapter as a stub."
/// SPRINT_PLANNING.md §13's open-decisions log wanted "current Flutter-SDK-
/// maturity confirmation" before this sprint started; that confirmation
/// never happened (no PayU sandbox credentials exist for this project), so
/// this is a genuinely empty adapter, not a guess at what a real PayU
/// Flutter integration would look like. Never reached in practice this
/// sprint -- `PAYMENT_GATEWAY_DEFAULT` on the backend stays `razorpay`
/// (.env.example), and this class only exists so
/// `payment_gateway_providers.dart`'s registry is real (a genuine second
/// entry) rather than a comment promising one later.
class PayUPaymentGateway implements PaymentGateway {
  @override
  Future<PaymentGatewayResult> pay(PaymentGatewayRequest request) {
    throw UnimplementedError(
      'PayU is not implemented yet -- Razorpay is the only live adapter (Sprint 8). '
      'See proximity_backend/supabase/functions/api/lib/payments/payu.ts for the backend half of this stub.',
    );
  }
}
