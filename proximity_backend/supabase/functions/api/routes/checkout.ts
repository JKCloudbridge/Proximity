import { Hono } from "npm:hono";
import { zValidator } from "npm:@hono/zod-validator";
import { z } from "npm:zod";
import { and, desc, eq, inArray, sql } from "npm:drizzle-orm";

import { authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { db } from "../lib/db.ts";
import { discounts, orderGroups, orders, platformSettings, shopBlackoutDates, shopBusinessHours, shops } from "../db/schema.ts";
import {
  DEFAULT_SLOT_WINDOW,
  generateSlots,
  istDateString,
  istWeekdayForDate,
  type SlotWindow,
} from "../lib/slots.ts";
import { confirmPaymentAndGenerateInvoices, loadOrderGroup } from "../lib/orderConfirmation.ts";

// Sprint 7 (§7.4's checkout flow, §4.6's slot endpoint, §5.4's
// rpc_place_order). Everything that actually *writes* an order goes through
// the RPC -- this file validates, reads, and shapes responses, but never
// composes an order out of separate statements (§5.1).
//
// One honest note on the money, since it's the part worth being careful
// about: **rpc_place_order is the only authority on what a checkout costs.**
// The two read routes below (`/checkout/config`, `/discounts/:code`) exist
// so the review step (§7.4 step 4) can show a total before the buyer
// commits, and each returns a server-computed figure rather than letting
// the client invent rules -- but the client still does the final summation
// for display. If the two ever disagreed, the RPC's numbers are what get
// stored and charged, and the confirmation screen renders those, not the
// preview. Keeping the preview a thin read rather than a second
// implementation of the placement transaction is the deliberate trade;
// see Sprint 7.md for the alternative (a dry-run mode on the RPC) and why
// it wasn't taken this sprint.
export const checkoutRoute = new Hono<AuthEnv>();

checkoutRoute.use("/checkout/*", authMiddleware);
checkoutRoute.use("/orders", authMiddleware);
checkoutRoute.use("/orders/*", authMiddleware);
// Sprint 9's new GET /order-groups (list, no trailing segment) needs its
// own exact-path registration alongside the existing /order-groups/*
// wildcard -- same "a bare `/*` doesn't match the collection route itself"
// gap this file's own /orders + /orders/* pair already existed to close
// (Sprint 7), not a new discovery this sprint made independently.
checkoutRoute.use("/order-groups", authMiddleware);
checkoutRoute.use("/order-groups/*", authMiddleware);
checkoutRoute.use("/discounts/*", authMiddleware);

async function readSlotWindow(): Promise<SlotWindow> {
  const [row] = await db.select().from(platformSettings).where(eq(platformSettings.key, "slot_window")).limit(1);
  return (row?.value as SlotWindow | undefined) ?? DEFAULT_SLOT_WINDOW;
}

async function readRiderFee(): Promise<number> {
  const [row] = await db
    .select()
    .from(platformSettings)
    .where(eq(platformSettings.key, "platform_rider_delivery_fee"))
    .limit(1);
  const value = row?.value as { amount_paise?: number } | undefined;
  return value?.amount_paise ?? 0;
}

// ---------------------------------------------------------------------------
// Checkout config -- the admin-controlled numbers the review step needs
// (§1.3: the delivery fee is a platform setting, never a per-shop one).
// ---------------------------------------------------------------------------

checkoutRoute.get("/checkout/config", async (c) => {
  const [slotWindow, riderFee] = await Promise.all([readSlotWindow(), readRiderFee()]);
  return c.json({
    data: {
      platformRiderDeliveryFee: riderFee,
      slotMinutes: slotWindow.slot_minutes,
      slotWindowStart: slotWindow.start,
      slotWindowEnd: slotWindow.end,
    },
  });
});

// ---------------------------------------------------------------------------
// Discount code validation (§11's "discounts engine wired"). Preview only --
// rpc_place_order re-validates every one of these rules itself at placement
// (migrations/032 step 6) and is what actually decides. The duplication is
// deliberate and bounded: this route exists so a buyer finds out their code
// is expired while typing it, not after tapping Pay.
// ---------------------------------------------------------------------------

const discountQuerySchema = z.object({ subtotal: z.coerce.number().int().min(0) });

checkoutRoute.get("/discounts/:code", zValidator("query", discountQuerySchema), async (c) => {
  const code = c.req.param("code").trim().toUpperCase();
  const { subtotal } = c.req.valid("query");

  const [discount] = await db.select().from(discounts).where(eq(discounts.code, code)).limit(1);
  const now = new Date();

  const invalid =
    !discount ||
    !discount.isActive ||
    (discount.startsAt && discount.startsAt > now) ||
    (discount.expiresAt && discount.expiresAt < now) ||
    (discount.maxUses !== null && discount.usesCount >= discount.maxUses);

  if (invalid) {
    return c.json({ error: { code: "DISCOUNT_INVALID", message: "This code isn't valid" } }, 404);
  }
  if (subtotal < discount.minOrderValue) {
    return c.json(
      {
        error: {
          code: "DISCOUNT_MIN_ORDER_NOT_MET",
          message: `Spend at least ${discount.minOrderValue} paise to use this code`,
        },
      },
      400,
    );
  }

  // Same three rules as migrations/032 step 6, in the same order.
  let amount = 0;
  let freeShipping = false;
  if (discount.type === "percent") {
    amount = Math.round((subtotal * discount.value) / 100);
  } else if (discount.type === "flat") {
    amount = Math.min(discount.value, subtotal);
  } else if (discount.type === "free_shipping") {
    freeShipping = true;
  }
  amount = Math.min(amount, subtotal);

  return c.json({
    data: { code: discount.code, name: discount.name, type: discount.type, amount, freeShipping },
  });
});

// ---------------------------------------------------------------------------
// §4.6's fulfillment-slots endpoint, finally built -- Sprints 4/5/6 each
// deferred it here by name. Public (no /checkout/ prefix, so the
// authMiddleware above doesn't apply): the slot picker is part of browsing a
// shop as much as checking out, same public/authed split shops.ts and
// catalog.ts already use.
// ---------------------------------------------------------------------------

const slotsQuerySchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  type: z.enum(["pickup", "delivery"]).optional(),
});

checkoutRoute.get("/shops/:shopId/fulfillment-slots", zValidator("query", slotsQuerySchema), async (c) => {
  const shopId = c.req.param("shopId");
  const { date, type } = c.req.valid("query");
  const now = new Date();
  const dateStr = date ?? istDateString(now);

  const [shop] = await db
    .select({
      id: shops.id,
      supportsPickup: shops.supportsPickup,
      supportsDelivery: shops.supportsDelivery,
      deliveryMode: shops.deliveryMode,
    })
    .from(shops)
    .where(and(eq(shops.id, shopId), eq(shops.status, "approved")))
    .limit(1);
  if (!shop) return c.json({ error: { code: "SHOP_NOT_FOUND", message: "Shop not found" } }, 404);

  // §4.6's `type` parameter earns its place here: both fulfillment types
  // share one slot mechanism (§1.6 unified them deliberately), so the type
  // doesn't change the grid -- but a shop that doesn't offer the type being
  // asked about has no slots to give for it at all.
  if (type === "pickup" && !shop.supportsPickup) {
    return c.json({ data: { date: dateStr, slots: [], unsupported: true } });
  }
  if (type === "delivery" && !shop.supportsDelivery) {
    return c.json({ data: { date: dateStr, slots: [], unsupported: true } });
  }

  const slotWindow = await readSlotWindow();
  const weekday = istWeekdayForDate(dateStr);

  const [hours] = await db
    .select()
    .from(shopBusinessHours)
    .where(and(eq(shopBusinessHours.shopId, shopId), eq(shopBusinessHours.weekday, weekday)))
    .limit(1);

  const [blackout] = await db
    .select({ id: shopBlackoutDates.id })
    .from(shopBlackoutDates)
    .where(and(eq(shopBlackoutDates.shopId, shopId), eq(shopBlackoutDates.date, dateStr)))
    .limit(1);

  const slots = generateSlots(dateStr, now, slotWindow, hours ?? null, Boolean(blackout));
  return c.json({ data: { date: dateStr, slots, unsupported: false } });
});

// ---------------------------------------------------------------------------
// Place the order (§5.4's rpc_place_order). Every rule this route could
// check, the RPC checks too -- this handler's only jobs are shaping the
// request and turning the RPC's raised error codes into typed responses
// (§9's checkout_repository pattern, extended with the new codes).
// ---------------------------------------------------------------------------

const fulfillmentEntrySchema = z.object({
  shopId: z.string().uuid(),
  fulfillmentType: z.enum(["pickup", "delivery"]),
  deliveryFulfilledBy: z.enum(["shop", "platform_rider"]).nullable().optional(),
  slotStart: z.string().datetime(),
  slotEnd: z.string().datetime(),
});

const placeOrderSchema = z.object({
  fulfillment: z.array(fulfillmentEntrySchema).min(1),
  addressId: z.string().uuid().nullable().optional(),
  paymentMode: z.enum(["online", "pay_at_shop"]),
  discountCode: z.string().max(50).nullable().optional(),
});

// RPC error code -> (HTTP status, buyer-facing message). Anything not listed
// falls through to index.ts's catch-all 500, same as every other route.
const PLACE_ORDER_ERRORS: Record<string, { status: 400 | 404 | 409; message: string }> = {
  CART_EMPTY: { status: 400, message: "Your cart is empty" },
  CART_HAS_UNAVAILABLE_ITEMS: { status: 409, message: "Some items are no longer available -- review your cart" },
  SHOP_GROUP_MISMATCH: { status: 400, message: "Choose a fulfillment option for every shop in your cart" },
  PAY_AT_SHOP_NOT_ALLOWED: { status: 400, message: "Pay at shop isn't available when a Proximity rider is delivering" },
  SHOP_NOT_AVAILABLE: { status: 409, message: "One of these shops is no longer taking orders" },
  INVALID_FULFILLMENT_TYPE: { status: 400, message: "Invalid fulfillment choice" },
  FULFILLMENT_NOT_SUPPORTED: { status: 400, message: "This shop doesn't offer that fulfillment option" },
  DELIVERY_MODE_MISMATCH: { status: 400, message: "This shop doesn't offer that delivery option" },
  ADDRESS_REQUIRED: { status: 400, message: "Pick a delivery address" },
  ADDRESS_NOT_OWNED: { status: 400, message: "Pick a delivery address" },
  SLOT_IN_PAST: { status: 409, message: "That time slot has already passed -- pick another" },
  SLOT_BLACKED_OUT: { status: 409, message: "The shop is closed on that date -- pick another slot" },
  SLOT_OUTSIDE_HOURS: { status: 409, message: "That slot is outside the shop's hours -- pick another" },
  SLOT_INVALID: { status: 400, message: "Pick a valid time slot" },
  MIN_ORDER_NOT_MET: { status: 400, message: "One shop's items are below its minimum order value" },
  DISCOUNT_INVALID: { status: 400, message: "This code isn't valid" },
  DISCOUNT_MIN_ORDER_NOT_MET: { status: 400, message: "Your order is below this code's minimum" },
  INVALID_PAYMENT_MODE: { status: 400, message: "Invalid payment mode" },
  ORDER_TOTAL_MISMATCH: { status: 409, message: "Could not complete checkout -- please try again" },
};

checkoutRoute.post("/orders", zValidator("json", placeOrderSchema), async (c) => {
  const authUser = c.get("user");
  const body = c.req.valid("json");

  // Re-keyed to the snake_case shape migrations/032 reads out of the JSONB.
  const fulfillmentPayload = body.fulfillment.map((f) => ({
    shop_id: f.shopId,
    fulfillment_type: f.fulfillmentType,
    delivery_fulfilled_by: f.fulfillmentType === "delivery" ? f.deliveryFulfilledBy ?? null : null,
    slot_start: f.slotStart,
    slot_end: f.slotEnd,
  }));

  let groupId: string;
  try {
    const rows = (await db.execute(sql`
      SELECT public.rpc_place_order(
        ${authUser.id}::uuid,
        ${JSON.stringify(fulfillmentPayload)}::jsonb,
        ${body.addressId ?? null}::uuid,
        ${body.paymentMode},
        ${body.discountCode ?? null}
      ) AS order_group_id
    `)) as unknown as { order_group_id: string }[];
    groupId = rows[0].order_group_id;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    for (const [code, mapped] of Object.entries(PLACE_ORDER_ERRORS)) {
      if (message.includes(code)) {
        return c.json({ error: { code, message: mapped.message } }, mapped.status);
      }
    }
    throw err;
  }

  // Sprint 8: pay_at_shop has no gateway event to wait for at all (§1.4) --
  // migrations/036's own header records the decision in full: this is the
  // one and only trigger point for a pay_at_shop group, chosen specifically
  // because no shop-side order-status-advance surface exists anywhere in
  // this codebase yet to gate on instead. `online` groups are deliberately
  // left at 'pending' here -- routes/payments.ts's verify-payment/webhook
  // handlers are what confirm those, once a real gateway payment exists.
  if (body.paymentMode === "pay_at_shop") {
    try {
      await confirmPaymentAndGenerateInvoices({ groupId });
    } catch (err) {
      // The order itself was placed successfully (rpc_place_order already
      // committed) -- a failure here shouldn't read as "checkout failed" to
      // the buyer. Logged, not thrown; the confirmation screen shows
      // whatever payment_status actually landed as, which is honest either
      // way.
      console.error(`confirmPaymentAndGenerateInvoices failed for pay_at_shop group ${groupId}`, err);
    }
  }

  const data = await loadOrderGroup(groupId, authUser.id);
  return c.json({ data }, 201);
});

// ---------------------------------------------------------------------------
// Confirmation / order-group read (§7.4 step 5: "one card per shop-group,
// each showing its own fulfillment type, slot, and delivery-fee line --
// never a single merged summary"). The full order *history* list is still
// Sprint 10's job (§11); this is the single-group read the checkout flow
// itself needs to land on. Moved to lib/orderConfirmation.ts in Sprint 8 --
// see that file's header for why (routes/payments.ts needs it too).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Sprint 9 -- a minimal list, deliberately NOT §11's own Sprint 10 "Order
// history / Order Again" feature (that's reorder, filtering, pagination
// against real usage patterns -- none of that is this sprint's job). This
// exists for one narrow, load-bearing reason: §7.5's new live-tracking view
// (the confirmation screen, now Realtime-driven) was, through Sprint 7/8,
// reachable ONLY as a one-time push straight off a just-completed checkout
// -- nothing in the app could navigate back to an order placed earlier and
// then backgrounded/closed. A tracking feature nothing can reach isn't
// really shipped. So: one flat, unfiltered, most-recent-first list of the
// buyer's own order_groups (own-user data, §5.2), summarized (NOT
// loadOrderGroup's full per-item nesting -- this is a list to tap through
// from, not a detail view) -- tapping a row still lands on the exact same
// GET /order-groups/:id + Realtime subscription this sprint already built.
// Real Order History (Sprint 10) can replace or extend this without
// touching the tracking screen it feeds at all. Registered BEFORE
// /order-groups/:id, same defensive-but-not-load-bearing ordering
// shops.ts's own /shops/near-before-/shops/:id comment established in
// Sprint 5 (Hono's router resolves a static segment over a param one
// regardless of registration order -- this costs nothing and removes the
// question for a future reader).
// ---------------------------------------------------------------------------

checkoutRoute.get("/order-groups", async (c) => {
  const authUser = c.get("user");

  const groups = await db
    .select({
      id: orderGroups.id,
      paymentMode: orderGroups.paymentMode,
      paymentStatus: orderGroups.paymentStatus,
      total: orderGroups.total,
      createdAt: orderGroups.createdAt,
    })
    .from(orderGroups)
    .where(eq(orderGroups.userId, authUser.id))
    .orderBy(desc(orderGroups.createdAt))
    .limit(50);

  const groupIds = groups.map((g) => g.id);
  const shopStatusRows = groupIds.length
    ? await db
        .select({ orderGroupId: orders.orderGroupId, shopId: orders.shopId, status: orders.status, shopName: shops.name })
        .from(orders)
        .innerJoin(shops, eq(shops.id, orders.shopId))
        .where(inArray(orders.orderGroupId, groupIds))
    : [];

  return c.json({
    data: groups.map((g) => ({
      ...g,
      shops: shopStatusRows
        .filter((r) => r.orderGroupId === g.id)
        .map((r) => ({ shopId: r.shopId, shopName: r.shopName, status: r.status })),
    })),
  });
});

// ---------------------------------------------------------------------------
// Confirmation / order-group read (§7.4 step 5: "one card per shop-group,
// each showing its own fulfillment type, slot, and delivery-fee line --
// never a single merged summary"). The full order *history* list is still
// Sprint 10's job (§11); this is the single-group read the checkout flow
// itself needs to land on. Moved to lib/orderConfirmation.ts in Sprint 8 --
// see that file's header for why (routes/payments.ts needs it too).
// ---------------------------------------------------------------------------

checkoutRoute.get("/order-groups/:id", async (c) => {
  const authUser = c.get("user");
  const data = await loadOrderGroup(c.req.param("id"), authUser.id);
  if (!data) return c.json({ error: { code: "ORDER_NOT_FOUND", message: "Order not found" } }, 404);
  return c.json({ data });
});
