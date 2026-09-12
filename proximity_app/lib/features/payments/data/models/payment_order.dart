/// Mirrors `POST /v1/order-groups/:id/payment-order`'s response
/// (routes/payments.ts, Sprint 8) -- everything `PaymentGateway.pay()` needs
/// to open the Checkout sheet for this specific order_group.
class PaymentOrder {
  const PaymentOrder({
    required this.gateway,
    required this.gatewayOrderId,
    required this.amountPaise,
    required this.currency,
    this.keyId,
  });

  final String gateway;
  final String gatewayOrderId;
  final int amountPaise;
  final String currency;
  final String? keyId;

  factory PaymentOrder.fromJson(Map<String, dynamic> json) {
    return PaymentOrder(
      gateway: json['gateway'] as String,
      gatewayOrderId: json['gatewayOrderId'] as String,
      amountPaise: json['amountPaise'] as int,
      currency: json['currency'] as String,
      keyId: json['keyId'] as String?,
    );
  }
}
