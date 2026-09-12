// Sprint 8 -- SPRINT_PLANNING.md §1.4's recommendation, built as stated: "a
// small PaymentGateway interface (both in the Edge Function backend and as a
// thin Flutter wrapper) with createOrder()/verifyPayment()/handleWebhook()
// methods, implement the Razorpay adapter first for MVP, keep a PayU adapter
// stub. Swapping or running both becomes a config flag, not a rewrite."
//
// This file is that interface's TypeScript shape (Flutter's own thin wrapper
// is proximity_app/lib/features/payments/data/payment_gateway.dart -- same
// three-method shape, deliberately not a shared codegen artifact between two
// different languages, same "each side owns its own types" precedent every
// route/model pair in this project already follows).

export type GatewayId = "razorpay" | "payu";

export interface CreateGatewayOrderParams {
  /** Paise -- this project's one money unit throughout (§1.7). */
  amountPaise: number;
  currency: "INR";
  /** Our own order_groups.id, threaded through so a webhook event can be
   *  matched back to the right group without a second lookup table. */
  orderGroupId: string;
  /** Max 40 chars per Razorpay's own Orders API (verified live against
   *  razorpay.com/docs/api/orders/create -- see Sprint 8.md). */
  receipt: string;
}

export interface CreateGatewayOrderResult {
  gatewayOrderId: string;
  amountPaise: number;
  currency: string;
}

export interface VerifyPaymentSignatureParams {
  gatewayOrderId: string;
  gatewayPaymentId: string;
  signature: string;
}

/** What a webhook event resolves to, once verified and parsed -- the two
 *  gateway-specific shapes (Razorpay's `event`/`payload.payment.entity`
 *  nesting, whatever PayU's eventually turns out to be) collapse to this one
 *  shape before routes/payments.ts ever sees them. */
export interface PaymentWebhookEvent {
  kind: "payment_captured" | "payment_failed" | "unhandled";
  gatewayOrderId: string | null;
  gatewayPaymentId: string | null;
  /** Read back out of the gateway order's own notes (see
   *  CreateGatewayOrderParams.orderGroupId) -- null only if the event predates
   *  this project ever setting that note, which shouldn't happen in
   *  practice but is handled rather than assumed. */
  orderGroupId: string | null;
}

/**
 * One adapter per gateway. Every method that touches real money or a real
 * signature is async -- even where an implementation (PayU's stub) doesn't
 * need to be, so routes/payments.ts never has to know which adapter it's
 * holding.
 */
export interface PaymentGateway {
  readonly id: GatewayId;

  createOrder(params: CreateGatewayOrderParams): Promise<CreateGatewayOrderResult>;

  /** True/false, never throws on a bad signature -- a forged or mismatched
   *  signature is an expected, non-exceptional input (a client lying, or a
   *  replayed request), not a system failure. */
  verifyPaymentSignature(params: VerifyPaymentSignatureParams): Promise<boolean>;

  /** Verifies the raw webhook body against `signatureHeader` and, only if
   *  valid, parses it into a PaymentWebhookEvent. Returns `null` on a bad
   *  signature -- same "expected input, not an exception" reasoning as
   *  verifyPaymentSignature. `rawBody` MUST be the exact bytes/text Hono
   *  read off the request, never a re-serialized JSON.stringify of a parsed
   *  object (razorpay.com/docs/webhooks/validate-test's own warning: the
   *  raw body is what's signed, and re-parsing-then-re-stringifying can
   *  reorder keys and break the signature even when the event is genuine).
   */
  verifyAndParseWebhook(rawBody: string, signatureHeader: string | undefined): Promise<PaymentWebhookEvent | null>;
}
