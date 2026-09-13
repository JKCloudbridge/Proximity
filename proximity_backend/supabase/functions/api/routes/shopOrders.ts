import { Hono } from "npm:hono";
import { zValidator } from "npm:@hono/zod-validator";
import { z } from "npm:zod";
import { desc, eq, inArray, sql } from "npm:drizzle-orm";

import { authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { db } from "../lib/db.ts";
import { orderItems, orders } from "../db/schema.ts";
import { isShopMember, isShopWriter } from "../lib/shopAccess.ts";
import { assignRider, forceReassignRider, OrderNotReassignableError } from "../lib/riderAssignment.ts";
import { cancelOrder, CANCEL_ORDER_ERRORS } from "../lib/cancellation.ts";
import { getShopSalesSummary } from "../lib/salesSummary.ts";
import { getShopLedgerBalance, listLedgerEntries } from "../lib/ledger.ts";

// Sprint 9 -- §8.3's "Order list scoped to their own shop," now with a real
// backend surface for the first time (Sprint 3-8 all deferred this: nothing
// before this sprint needed a shop to ever change orders.status past
// 'confirmed'). §2's system map puts "lightweight in-app views for
// shop-order-notifications (shopkeepers/staff)" on proximity_app, not
// proximity_web -- these routes are that: consumed by
// proximity_app/lib/features/shop_orders (this sprint), not a
// proximity_web dashboard page, which stays out of scope here same as
// every sprint since Sprint 3. A future sprint is free to also build a
// proximity_web view against these same routes; nothing here is
// mobile-specific.
export const shopOrdersRoute = new Hono<AuthEnv>();

// A broad prefix, not a narrow `/orders/*` -- same convention shops.ts's own
// `.use("/shop/*", authMiddleware)` and riders.ts's `.use("/rider/*", ...)`
// use, rather than a wildcard scoped tightly enough to risk NOT matching
// this file's own bare-collection route (`GET .../orders`, no trailing
// segment) depending on how Hono's router treats a `/*` suffix against a
// path with nothing after the final slash. Costs nothing to be broad here
// -- this router only ever mounts orders-related paths under
// `/shop/shops/:shopId/`.
shopOrdersRoute.use("/shop/shops/*", authMiddleware);

// ---------------------------------------------------------------------------
// Order list -- any member_role can view (§5.3: owner/staff/delivery all
// "view orders"). No pagination, same "minimum that makes the exit
// criteria true" scope discipline Sprint 3/5's own public routes used --
// worth revisiting once a real shop has hundreds of orders.
// ---------------------------------------------------------------------------

shopOrdersRoute.get("/shop/shops/:shopId/orders", async (c) => {
  const authUser = c.get("user");
  const shopId = c.req.param("shopId");

  if (!(await isShopMember(authUser.id, shopId))) {
    return c.json({ error: { code: "NOT_SHOP_TEAM_MEMBER", message: "Not a member of this shop" } }, 403);
  }

  const rows = await db
    .select({
      id: orders.id,
      status: orders.status,
      fulfillmentType: orders.fulfillmentType,
      deliveryFulfilledBy: orders.deliveryFulfilledBy,
      riderId: orders.riderId,
      slotStart: orders.slotStart,
      slotEnd: orders.slotEnd,
      subtotal: orders.subtotal,
      deliveryFee: orders.deliveryFee,
      total: orders.total,
      createdAt: orders.createdAt,
    })
    .from(orders)
    .where(eq(orders.shopId, shopId))
    .orderBy(desc(orders.createdAt))
    .limit(100);

  const orderIds = rows.map((r) => r.id);
  const itemCounts = orderIds.length
    ? await db
        .select({ orderId: orderItems.orderId, count: sql<number>`count(*)::int` })
        .from(orderItems)
        .where(inArray(orderItems.orderId, orderIds))
        .groupBy(orderItems.orderId)
    : [];
  const countByOrder = new Map(itemCounts.map((r) => [r.orderId, r.count]));

  return c.json({
    data: rows.map((r) => ({ ...r, itemCount: countByOrder.get(r.id) ?? 0 })),
  });
});

// ---------------------------------------------------------------------------
// Advance status (rpc_shop_advance_order_status, migrations/040). Any
// member_role -- §5.3 gives all three "advance status" rights.
// ---------------------------------------------------------------------------

const advanceStatusSchema = z.object({
  status: z.enum(["preparing", "ready_for_pickup", "out_for_delivery", "completed"]),
});

const ADVANCE_STATUS_ERRORS: Record<string, { status: 400 | 403 | 404 | 409; message: string }> = {
  ORDER_NOT_FOUND: { status: 404, message: "Order not found" },
  NOT_SHOP_TEAM_MEMBER: { status: 403, message: "Not a member of this shop" },
  ORDER_ALREADY_FINAL: { status: 409, message: "This order is already completed or cancelled" },
  INVALID_STATUS_TRANSITION: { status: 409, message: "That status change isn't valid right now" },
  PLATFORM_RIDER_HANDLES_REMAINING_STATUS: {
    status: 409,
    message: "A Proximity rider handles this order from here",
  },
  INVALID_NEW_STATUS: { status: 400, message: "Invalid status" },
};

shopOrdersRoute.post(
  "/shop/shops/:shopId/orders/:orderId/advance-status",
  zValidator("json", advanceStatusSchema),
  async (c) => {
    const authUser = c.get("user");
    const shopId = c.req.param("shopId");
    const orderId = c.req.param("orderId");
    const body = c.req.valid("json");

    // Ownership of :orderId by :shopId is re-checked by the RPC itself
    // (it looks up the order's own shop_id and verifies membership against
    // that, not against the URL's :shopId) -- this route's own membership
    // check above all only proves the caller belongs to *a* shop matching
    // the URL; it doesn't yet prove :orderId is that shop's own order. A
    // foreign orderId simply fails NOT_SHOP_TEAM_MEMBER inside the RPC
    // (the caller isn't a member of whatever shop that order actually
    // belongs to), same "don't trust the URL alone" discipline
    // catalog.ts's getOwnedProduct established in Sprint 3.
    if (!(await isShopMember(authUser.id, shopId))) {
      return c.json({ error: { code: "NOT_SHOP_TEAM_MEMBER", message: "Not a member of this shop" } }, 403);
    }

    try {
      const rows = (await db.execute(sql`
        SELECT * FROM public.rpc_shop_advance_order_status(
          ${orderId}::uuid, ${authUser.id}::uuid, ${body.status}
        )
      `)) as unknown as Record<string, unknown>[];
      return c.json({ data: rows[0] });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      for (const [code, mapped] of Object.entries(ADVANCE_STATUS_ERRORS)) {
        if (message.includes(code)) {
          return c.json({ error: { code, message: mapped.message } }, mapped.status);
        }
      }
      throw err;
    }
  },
);

// ---------------------------------------------------------------------------
// Manual rider-assignment retry (migrations/039's documented fallback for
// "no rider was available at confirmation time"). Owner/staff only --
// deliberately narrower than advance-status: handing an order to the
// platform's own rider network is an operational/business decision, not the
// same kind of "mark it done" action §5.3 gives every delivery-role member.
// ---------------------------------------------------------------------------

const ASSIGN_RIDER_ERRORS: Record<string, { status: 400 | 403 | 404 | 409 | 503; message: string }> = {
  ORDER_NOT_FOUND: { status: 404, message: "Order not found" },
  NOT_PLATFORM_RIDER_ORDER: { status: 400, message: "This order isn't fulfilled by a Proximity rider" },
  ORDER_NOT_ASSIGNABLE: { status: 409, message: "This order is already completed or cancelled" },
  // Sprint 12 -- thrown by forceReassignRider (lib/riderAssignment.ts) when
  // `force: true` is used on an order past the point a reassignment could
  // ever help (already out for delivery, completed, or cancelled).
  ORDER_NOT_REASSIGNABLE: { status: 409, message: "This order can no longer be reassigned" },
  SHOP_LOCATION_MISSING: { status: 409, message: "This shop has no location set" },
  NO_RIDER_AVAILABLE: { status: 503, message: "No riders are available nearby right now -- try again shortly" },
};

// Sprint 12 addition: `force` (optional, default false) lets this same route
// also cover the "current rider is unreachable mid-delivery" case
// (migrations/048's own header names this explicitly as the one gap this
// project does NOT auto-detect) -- without `force`, this route keeps its
// original Sprint 9 behavior exactly (idempotent no-op on an
// already-assigned order, via assignRider's own guard). With `force: true`
// on an order that already has a rider, the current rider is released and a
// fresh search runs, excluding nobody (a manually-forced reassignment isn't
// a decline -- the rider being replaced didn't refuse anything, so they
// stay eligible for a different order right away, and there's no reason to
// permanently exclude them from ever being reassigned to this one either if
// they were the only option).
const assignRiderBodySchema = z.object({ force: z.boolean().optional() });

shopOrdersRoute.post("/shop/shops/:shopId/orders/:orderId/assign-rider", zValidator("json", assignRiderBodySchema), async (c) => {
  const authUser = c.get("user");
  const shopId = c.req.param("shopId");
  const orderId = c.req.param("orderId");
  const { force } = c.req.valid("json");

  if (!(await isShopWriter(authUser.id, shopId))) {
    return c.json({ error: { code: "NOT_SHOP_WRITER", message: "Only the shop owner or staff can do this" } }, 403);
  }

  const [order] = await db.select({ shopId: orders.shopId }).from(orders).where(eq(orders.id, orderId)).limit(1);
  if (!order || order.shopId !== shopId) {
    return c.json({ error: { code: "ORDER_NOT_FOUND", message: "Order not found" } }, 404);
  }

  try {
    const result = force ? await forceReassignRider(orderId) : await assignRider(orderId);
    return c.json({ data: result });
  } catch (err) {
    if (err instanceof OrderNotReassignableError) {
      const mapped = ASSIGN_RIDER_ERRORS[err.code] ?? { status: 409 as const, message: "This order can't be reassigned right now" };
      return c.json({ error: { code: err.code, message: mapped.message } }, mapped.status);
    }
    const message = err instanceof Error ? err.message : String(err);
    for (const [code, mapped] of Object.entries(ASSIGN_RIDER_ERRORS)) {
      if (message.includes(code)) {
        return c.json({ error: { code, message: mapped.message } }, mapped.status);
      }
    }
    throw err;
  }
});

// ---------------------------------------------------------------------------
// Sprint 12 -- shop-initiated cancellation (rpc_cancel_order, migrations/047,
// via lib/cancellation.ts). Owner/staff only, same tier as the manual
// rider-assignment retry above -- see that migration's header for the full
// state-machine/ledger-reversal/rider-release design this one RPC call
// performs atomically.
// ---------------------------------------------------------------------------

const cancelOrderSchema = z.object({ reason: z.string().max(300).optional() });

shopOrdersRoute.post(
  "/shop/shops/:shopId/orders/:orderId/cancel",
  zValidator("json", cancelOrderSchema),
  async (c) => {
    const authUser = c.get("user");
    const shopId = c.req.param("shopId");
    const orderId = c.req.param("orderId");
    const { reason } = c.req.valid("json");

    const [order] = await db.select({ shopId: orders.shopId }).from(orders).where(eq(orders.id, orderId)).limit(1);
    if (!order || order.shopId !== shopId) {
      return c.json({ error: { code: "ORDER_NOT_FOUND", message: "Order not found" } }, 404);
    }

    try {
      const result = await cancelOrder(orderId, "shop", authUser.id, reason);
      return c.json({ data: result });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      for (const [code, mapped] of Object.entries(CANCEL_ORDER_ERRORS)) {
        if (message.includes(code)) {
          return c.json({ error: { code, message: mapped.message } }, mapped.status);
        }
      }
      throw err;
    }
  },
);

// ---------------------------------------------------------------------------
// Sprint 12 -- §8.4's sales summary + ledger view, on the shopkeeper's own
// dashboard side. Owner/staff only (§5.3: "View sales summary / ledger /
// invoices" excludes `delivery`) -- same gate isShopWriter already provides
// for catalog writes, reused here for a read for the first time (§5.3's
// table names it read-only for owner/staff, which isShopWriter's own name
// doesn't advertise but its actual role-set match is exactly right).
// ---------------------------------------------------------------------------

const salesSummaryQuerySchema = z.object({ days: z.coerce.number().int().min(1).max(365).optional() });

shopOrdersRoute.get(
  "/shop/shops/:shopId/analytics/sales-summary",
  zValidator("query", salesSummaryQuerySchema),
  async (c) => {
    const authUser = c.get("user");
    const shopId = c.req.param("shopId");
    const { days } = c.req.valid("query");

    if (!(await isShopWriter(authUser.id, shopId))) {
      return c.json({ error: { code: "NOT_SHOP_WRITER", message: "Only the shop owner or staff can view this" } }, 403);
    }

    const summary = await getShopSalesSummary(shopId, days ?? 30);
    return c.json({ data: summary });
  },
);

const ledgerQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(200).optional(),
  offset: z.coerce.number().int().min(0).optional(),
});

shopOrdersRoute.get("/shop/shops/:shopId/ledger", zValidator("query", ledgerQuerySchema), async (c) => {
  const authUser = c.get("user");
  const shopId = c.req.param("shopId");
  const { limit, offset } = c.req.valid("query");

  if (!(await isShopWriter(authUser.id, shopId))) {
    return c.json({ error: { code: "NOT_SHOP_WRITER", message: "Only the shop owner or staff can view this" } }, 403);
  }

  const [balance, entries] = await Promise.all([
    getShopLedgerBalance(shopId),
    listLedgerEntries({ shopId, limit: limit ?? 50, offset: offset ?? 0 }),
  ]);

  return c.json({ data: { balance, entries } });
});
