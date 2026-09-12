import { hmacSha256Hex, timingSafeEqual } from "./crypto.ts";
import type {
  CreateGatewayOrderParams,
  CreateGatewayOrderResult,
  PaymentGateway,
  PaymentWebhookEvent,
  VerifyPaymentSignatureParams,
} from "./types.ts";

// Sprint 8 -- the real Razorpay adapter (§1.4/§11). Everything below was
// checked live against Razorpay's current published docs before writing it,
// per this project's standing rule for third-party integrations -- not
// reconstructed from training-data memory:
//   * Orders API shape (POST /v1/orders, amount/currency required,
//     receipt <=40 chars, response has id/amount/currency/status) --
//     razorpay.com/docs/api/orders/create
//   * Payment-signature verification (checkout success handler) --
//     generated_signature = hmac_sha256(order_id + "|" + payment_id, key_secret),
//     compared against razorpay_signature -- confirmed via Razorpay's own
//     razorpay-node paymentVerification.md and multiple current docs pages
//     (Sprint 8.md records the exact sources)
//   * Webhook signature verification -- HMAC-SHA256 of the raw request body,
//     keyed with a SEPARATE webhook secret (not key_secret), compared
//     against the `X-Razorpay-Signature` header --
//     razorpay.com/docs/webhooks/validate-test
//
// No `npm:razorpay` SDK dependency: everything this project actually needs
// (create one order, verify two kinds of HMAC signature) is two REST calls
// and one crypto primitive, all directly expressible with Deno's built-in
// `fetch` and Web Crypto -- pulling in a full SDK for that would be more
// surface area to audit for less code saved than this file already is. If a
// future sprint needs more of Razorpay's API (refunds, Route splits, …),
// revisit that trade then.

const RAZORPAY_API_BASE = "https://api.razorpay.com/v1";

export interface RazorpayConfig {
  keyId: string;
  keySecret: string;
  webhookSecret: string;
}

export function readRazorpayConfigFromEnv(): RazorpayConfig | null {
  const keyId = Deno.env.get("RAZORPAY_KEY_ID");
  const keySecret = Deno.env.get("RAZORPAY_KEY_SECRET");
  const webhookSecret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET");
  if (!keyId || !keySecret || !webhookSecret) return null;
  return { keyId, keySecret, webhookSecret };
}

export class RazorpayGateway implements PaymentGateway {
  readonly id = "razorpay" as const;

  constructor(private readonly config: RazorpayConfig) {}

  async createOrder(params: CreateGatewayOrderParams): Promise<CreateGatewayOrderResult> {
    const auth = btoa(`${this.config.keyId}:${this.config.keySecret}`);
    const response = await fetch(`${RAZORPAY_API_BASE}/orders`, {
      method: "POST",
      headers: {
        Authorization: `Basic ${auth}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        amount: params.amountPaise,
        currency: params.currency,
        receipt: params.receipt,
        // Threaded through so the webhook handler can recover our own
        // order_groups.id from the gateway's own event payload without a
        // second DB lookup keyed on gateway_order_id alone.
        notes: { order_group_id: params.orderGroupId },
      }),
    });

    if (!response.ok) {
      const body = await response.text().catch(() => "");
      throw new Error(`RAZORPAY_CREATE_ORDER_FAILED ${response.status} ${body}`);
    }

    const data = (await response.json()) as { id: string; amount: number; currency: string };
    return { gatewayOrderId: data.id, amountPaise: data.amount, currency: data.currency };
  }

  async verifyPaymentSignature(params: VerifyPaymentSignatureParams): Promise<boolean> {
    const expected = await hmacSha256Hex(
      `${params.gatewayOrderId}|${params.gatewayPaymentId}`,
      this.config.keySecret,
    );
    return timingSafeEqual(expected, params.signature);
  }

  async verifyAndParseWebhook(rawBody: string, signatureHeader: string | undefined): Promise<PaymentWebhookEvent | null> {
    if (!signatureHeader) return null;

    const expected = await hmacSha256Hex(rawBody, this.config.webhookSecret);
    if (!timingSafeEqual(expected, signatureHeader)) return null;

    // Only parsed AFTER the raw-body signature check above -- see
    // types.ts's own warning on why the raw text, not a re-stringified
    // object, is what gets signed and verified.
    let payload: RazorpayWebhookPayload;
    try {
      payload = JSON.parse(rawBody) as RazorpayWebhookPayload;
    } catch {
      return null;
    }

    const paymentEntity = payload.payload?.payment?.entity;

    // Subscribed event is `order.paid`, NOT `payment.captured` -- a real
    // thing checked live against Razorpay's own webhook payload docs
    // (razorpay.com/docs/webhooks/payloads/payments/ vs .../orders/) rather
    // than assumed, and worth recording precisely because it reversed this
    // file's first draft: `payment.captured`'s own documented sample payload
    // contains ONLY `payload.payment.entity` -- no order entity at all -- and
    // that payment entity's own `notes` are a SEPARATE field from the
    // order's notes (Razorpay orders and payments are independent objects;
    // creating an order with `notes: {order_group_id}` does not copy that
    // onto the payment made against it). `order.paid`, by contrast, is
    // explicitly documented to include BOTH `payload.order.entity` (which
    // DOES carry the notes this project set at order-creation time,
    // razorpay.ts's own createOrder call) and `payload.payment.entity` (the
    // payment id) in one payload -- the only event that reliably lets this
    // function recover its own order_group_id. **The Razorpay Dashboard's
    // webhook configuration must subscribe to `order.paid`, not
    // `payment.captured`** -- see Sprint 8.md and .env.example's own note.
    if (payload.event === "order.paid") {
      const orderEntity = payload.payload?.order?.entity;
      return {
        kind: "payment_captured",
        gatewayOrderId: orderEntity?.id ?? paymentEntity?.order_id ?? null,
        gatewayPaymentId: paymentEntity?.id ?? null,
        orderGroupId: orderEntity?.notes?.order_group_id ?? null,
      };
    }
    if (payload.event === "payment.failed") {
      // No order entity on this event (see above) -- orderGroupId is
      // genuinely unrecoverable here. Harmless in this project today:
      // routes/payments.ts's webhook handler does nothing with a
      // `payment_failed` event beyond acknowledging it (the buyer's own app
      // already surfaces a Checkout-level failure independently).
      return {
        kind: "payment_failed",
        gatewayOrderId: paymentEntity?.order_id ?? null,
        gatewayPaymentId: paymentEntity?.id ?? null,
        orderGroupId: null,
      };
    }
    return {
      kind: "unhandled",
      gatewayOrderId: paymentEntity?.order_id ?? null,
      gatewayPaymentId: paymentEntity?.id ?? null,
      orderGroupId: null,
    };
  }
}

// Minimal shape of what this project actually reads out of a Razorpay
// webhook payload -- not the full documented event schema (dozens of event
// types this project never subscribes to). Extend if a future sprint
// subscribes to more events (refunds, disputes, ...).
interface RazorpayWebhookPayload {
  event: string;
  payload?: {
    payment?: {
      entity?: {
        id?: string;
        order_id?: string;
      };
    };
    order?: {
      entity?: {
        id?: string;
        notes?: { order_group_id?: string };
      };
    };
  };
}
