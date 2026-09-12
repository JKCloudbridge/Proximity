import { Hono } from "npm:hono";
import { zValidator } from "npm:@hono/zod-validator";
import { z } from "npm:zod";
import { and, eq } from "npm:drizzle-orm";

import { authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { db } from "../lib/db.ts";
import { orderGroups } from "../db/schema.ts";
import { confirmPaymentAndGenerateInvoices, loadOrderGroup } from "../lib/orderConfirmation.ts";
import { GatewayNotImplementedError, getPaymentGateway, PaymentGatewayNotConfiguredError, type GatewayId } from "../lib/payments/index.ts";

// Sprint 8 -- §1.4/§5.4's PaymentGateway wiring: creating a gateway order,
// verifying a completed payment, and receiving the gateway's own webhook.
// `routes/checkout.ts` still owns *placing* an order (rpc_place_order,
// Sprint 7) -- this file only ever runs against an order_group that already
// exists and is `payment_mode='online'`.
//
// Two ways an online payment gets confirmed, both landing on the same
// rpc_confirm_payment (036) via confirmPaymentAndGenerateInvoices
// (lib/orderConfirmation.ts) -- deliberately, not redundantly:
//   * POST /order-groups/:id/verify-payment -- the buyer's own app, right
//     after Razorpay Checkout's success callback fires client-side. Fast:
//     the buyer sees "paid" without waiting on a webhook round trip.
//   * POST /webhooks/razorpay -- Razorpay's own server calling back. Slower
//     but authoritative: it fires even if the buyer's app crashes, loses
//     network, or is force-closed the instant Checkout succeeds, which the
//     client-verify path alone would miss entirely.
// rpc_confirm_payment's own idempotency guard (a SELECT ... FOR UPDATE plus
// a payment_status check, migrations/036) is what makes calling both safe
// regardless of which one lands first.
export const paymentsRoute = new Hono<AuthEnv>();

paymentsRoute.use("/order-groups/*", authMiddleware);

// ---------------------------------------------------------------------------
// Create (or reuse) the gateway order for an existing, unpaid order_group.
// ---------------------------------------------------------------------------

paymentsRoute.post("/order-groups/:id/payment-order", async (c) => {
  const authUser = c.get("user");
  const groupId = c.req.param("id");

  const [group] = await db
    .select()
    .from(orderGroups)
    .where(and(eq(orderGroups.id, groupId), eq(orderGroups.userId, authUser.id)))
    .limit(1);
  if (!group) return c.json({ error: { code: "ORDER_NOT_FOUND", message: "Order not found" } }, 404);
  if (group.paymentMode !== "online") {
    return c.json({ error: { code: "NOT_ONLINE_PAYMENT", message: "This order doesn't use online payment" } }, 400);
  }
  if (group.paymentStatus !== "pending" && group.paymentStatus !== "failed") {
    return c.json({ error: { code: "ALREADY_RESOLVED", message: "This order has already been resolved" } }, 409);
  }

  let gateway;
  try {
    gateway = getPaymentGateway();
  } catch (err) {
    if (err instanceof PaymentGatewayNotConfiguredError) {
      return c.json({ error: { code: err.message, message: "Online payment isn't available right now" } }, 503);
    }
    throw err;
  }

  // Reuse an existing gateway order rather than minting a new one on every
  // retry -- a buyer backgrounding the app mid-Checkout and reopening it
  // shouldn't orphan a prior Razorpay order (Razorpay orders don't expire on
  // their own and a stray one is harmless, but there's no reason to create
  // extras).
  let gatewayOrderId = group.gatewayOrderId;
  if (!gatewayOrderId) {
    try {
      const created = await gateway.createOrder({
        amountPaise: group.total,
        currency: "INR",
        orderGroupId: group.id,
        // UUID is 36 chars, under Razorpay's 40-char receipt limit
        // (verified live against razorpay.com/docs/api/orders/create) --
        // no truncation needed, but this is the only string in this
        // request that could ever approach that limit, so it's named
        // explicitly rather than assumed forever.
        receipt: group.id,
      });
      gatewayOrderId = created.gatewayOrderId;
      await db.update(orderGroups).set({ paymentGateway: gateway.id, gatewayOrderId }).where(eq(orderGroups.id, group.id));
    } catch (err) {
      if (err instanceof GatewayNotImplementedError) {
        return c.json({ error: { code: err.message, message: `${gateway.id} isn't available yet` } }, 501);
      }
      console.error("Gateway order creation failed", err);
      return c.json({ error: { code: "GATEWAY_ORDER_FAILED", message: "Could not start payment -- please try again" } }, 502);
    }
  }

  return c.json({
    data: {
      gateway: gateway.id,
      gatewayOrderId,
      amountPaise: group.total,
      currency: "INR",
      // Safe to hand back: this is the public half of the key pair, same
      // "client-safe by design" reasoning as SUPABASE_ANON_KEY
      // (.env.example's own comment). razorpay_flutter's Checkout needs it
      // to open at all.
      keyId: gateway.id === "razorpay" ? Deno.env.get("RAZORPAY_KEY_ID") ?? null : null,
    },
  });
});

// ---------------------------------------------------------------------------
// The fast, client-triggered confirmation path -- see this file's own header
// for why the webhook below is still needed alongside this, not instead of.
// ---------------------------------------------------------------------------

const verifyPaymentSchema = z.object({
  gatewayOrderId: z.string().min(1),
  gatewayPaymentId: z.string().min(1),
  gatewaySignature: z.string().min(1),
});

paymentsRoute.post("/order-groups/:id/verify-payment", zValidator("json", verifyPaymentSchema), async (c) => {
  const authUser = c.get("user");
  const groupId = c.req.param("id");
  const body = c.req.valid("json");

  const [group] = await db
    .select()
    .from(orderGroups)
    .where(and(eq(orderGroups.id, groupId), eq(orderGroups.userId, authUser.id)))
    .limit(1);
  if (!group) return c.json({ error: { code: "ORDER_NOT_FOUND", message: "Order not found" } }, 404);
  if (group.paymentMode !== "online") {
    return c.json({ error: { code: "NOT_ONLINE_PAYMENT", message: "This order doesn't use online payment" } }, 400);
  }
  if (group.gatewayOrderId !== body.gatewayOrderId) {
    return c.json({ error: { code: "GATEWAY_ORDER_MISMATCH", message: "This payment doesn't match this order" } }, 400);
  }

  let gateway;
  try {
    gateway = getPaymentGateway((group.paymentGateway as GatewayId | null) ?? undefined);
  } catch (err) {
    if (err instanceof PaymentGatewayNotConfiguredError) {
      return c.json({ error: { code: err.message, message: "Online payment isn't available right now" } }, 503);
    }
    throw err;
  }

  const valid = await gateway.verifyPaymentSignature({
    gatewayOrderId: body.gatewayOrderId,
    gatewayPaymentId: body.gatewayPaymentId,
    signature: body.gatewaySignature,
  });
  if (!valid) {
    // Deliberately vague: this is either a forged signature or a genuine
    // gateway-side hiccup, and the buyer-facing message shouldn't help
    // distinguish which to anyone probing the endpoint.
    return c.json({ error: { code: "SIGNATURE_INVALID", message: "Could not verify this payment" } }, 400);
  }

  await confirmPaymentAndGenerateInvoices({
    groupId: group.id,
    gateway: gateway.id,
    gatewayOrderId: body.gatewayOrderId,
    gatewayPaymentId: body.gatewayPaymentId,
  });

  const data = await loadOrderGroup(group.id, authUser.id);
  return c.json({ data });
});

// ---------------------------------------------------------------------------
// The authoritative path: Razorpay's own server calling back. No
// authMiddleware -- Razorpay never has a Supabase bearer token, and isn't
// meant to; the HMAC signature check below IS this route's authentication,
// same "a different trust boundary for a different kind of caller" shape
// §5.1 already draws between authMiddleware (a human's JWT) and
// SECURITY DEFINER + REVOKE (an RPC's one intended caller).
// ---------------------------------------------------------------------------

export const paymentsWebhookRoute = new Hono();

paymentsWebhookRoute.post("/webhooks/razorpay", async (c) => {
  // MUST be the raw text, read before any JSON parsing -- see
  // lib/payments/types.ts's PaymentGateway.verifyAndParseWebhook doc comment
  // for why a re-serialized body would silently break the signature check.
  const rawBody = await c.req.text();
  const signature = c.req.header("X-Razorpay-Signature");

  let gateway;
  try {
    gateway = getPaymentGateway("razorpay");
  } catch {
    // A misconfigured webhook is this project's fault, not the caller's --
    // still a 503, not a 200, so Razorpay's dashboard shows the delivery as
    // failing rather than silently succeeding into nothing.
    return c.json({ error: { code: "PAYMENT_GATEWAY_NOT_CONFIGURED", message: "Webhook not configured" } }, 503);
  }

  const event = await gateway.verifyAndParseWebhook(rawBody, signature);
  if (!event) {
    return c.json({ error: { code: "WEBHOOK_SIGNATURE_INVALID", message: "Invalid signature" } }, 400);
  }

  if (event.kind === "payment_captured" && event.orderGroupId && event.gatewayPaymentId) {
    try {
      await confirmPaymentAndGenerateInvoices({
        groupId: event.orderGroupId,
        gateway: gateway.id,
        gatewayOrderId: event.gatewayOrderId,
        gatewayPaymentId: event.gatewayPaymentId,
      });
    } catch (err) {
      console.error("rpc_confirm_payment failed from webhook", err);
      // A non-2xx response makes Razorpay retry the delivery later (its own
      // documented webhook retry behavior) -- the right response for what's
      // almost certainly a transient DB error, unlike the signature-invalid
      // case above which should never be retried into eventually succeeding.
      return c.json({ error: { code: "CONFIRM_PAYMENT_FAILED", message: "Could not confirm payment" } }, 500);
    }
  }
  // `payment_failed` / `unhandled` events: acknowledged, nothing to do. A
  // failed payment leaves order_groups.payment_status at 'pending' -- this
  // project's checkout screen already surfaces a Checkout-SDK-level failure
  // independently (EVENT_PAYMENT_ERROR, the Flutter gateway wrapper), and
  // the buyer can retry payment-order creation for the same, still-unpaid
  // group at any time.

  return c.json({ data: { received: true } });
});
