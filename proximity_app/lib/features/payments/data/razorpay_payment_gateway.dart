import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'payment_gateway.dart';

/// Sprint 8 -- the real adapter (§1.4/§11). `razorpay_flutter`'s actual API
/// surface was checked live against its current pub.dev listing before
/// writing this (1.4.6, verified real -- not assumed from training-data
/// memory, per this project's standing rule): a single `Razorpay` class,
/// `open(Map<String, dynamic> options)` to launch the native Checkout sheet,
/// `on(eventName, listener)` to subscribe to `EVENT_PAYMENT_SUCCESS` /
/// `EVENT_PAYMENT_ERROR` / `EVENT_EXTERNAL_WALLET`, and `clear()` to remove
/// listeners. There is no `Future`-returning `open()` -- this class's whole
/// job is turning that event-callback shape into the one `Future<
/// PaymentGatewayResult>` `PaymentGateway.pay()` promises, via a
/// `Completer` that only ever completes once (a Checkout sheet firing a
/// stray second event after the first would otherwise throw on the
/// already-completed Completer).
///
/// A fresh `Razorpay()` instance per `pay()` call, not a shared/reused one --
/// cheap to construct, and it removes any question of a listener from a
/// previous, already-finished checkout firing again on a later one.
class RazorpayPaymentGateway implements PaymentGateway {
  @override
  Future<PaymentGatewayResult> pay(PaymentGatewayRequest request) {
    final completer = Completer<PaymentGatewayResult>();
    final razorpay = Razorpay();

    void complete(PaymentGatewayResult result) {
      if (completer.isCompleted) return;
      completer.complete(result);
      razorpay.clear();
    }

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) {
      // orderId/paymentId/signature -- exactly the three fields
      // routes/payments.ts's verify-payment route needs (§5.4's client-side
      // half of "verifies the gateway signature": the backend does the
      // actual HMAC check, this app just carries the three values there).
      final orderId = response.orderId;
      final paymentId = response.paymentId;
      final signature = response.signature;
      if (orderId == null || paymentId == null || signature == null) {
        complete(PaymentGatewayResult.failure('Payment completed but the gateway response was incomplete.'));
        return;
      }
      complete(PaymentGatewayResult.success(
        PaymentGatewaySuccess(gatewayOrderId: orderId, gatewayPaymentId: paymentId, gatewaySignature: signature),
      ));
    });

    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
      // Covers both a real failure (declined card, ...) and the buyer
      // dismissing the Checkout sheet -- razorpay_flutter surfaces a
      // cancellation through this same event, not a separate one.
      complete(PaymentGatewayResult.failure(response.message ?? 'Payment was not completed.'));
    });

    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse response) {
      // A buyer picked a wallet Razorpay hands off to externally (e.g.
      // Paytm) rather than completing inside the Checkout sheet itself --
      // this project doesn't have a follow-up flow for that path, so it's
      // treated as "didn't complete here," same as a cancellation.
      complete(PaymentGatewayResult.failure('Completed outside the app (${response.walletName ?? "external wallet"}) -- not confirmed here.'));
    });

    razorpay.open({
      'key': request.keyId,
      'amount': request.amountPaise,
      'currency': request.currency,
      'order_id': request.gatewayOrderId,
      'name': 'Proximity',
      if (request.buyerName != null || request.buyerEmail != null || request.buyerPhone != null)
        'prefill': {
          if (request.buyerName != null) 'name': request.buyerName,
          if (request.buyerEmail != null) 'email': request.buyerEmail,
          if (request.buyerPhone != null) 'contact': request.buyerPhone,
        },
    });

    return completer.future;
  }
}
