import { Hono } from "npm:hono";
import { zValidator } from "npm:@hono/zod-validator";
import { z } from "npm:zod";
import { desc, eq, inArray, sql } from "npm:drizzle-orm";

import { authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { db } from "../lib/db.ts";
import { orderItems, orders } from "../db/schema.ts";
import { isShopMember, isShopWriter } from "../lib/shopAccess.ts";
import { assignRider } from "../lib/riderAssignment.ts";

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
  SHOP_LOCATION_MISSING: { status: 409, message: "This shop has no location set" },
  NO_RIDER_AVAILABLE: { status: 503, message: "No riders are available nearby right now -- try again shortly" },
};

shopOrdersRoute.post("/shop/shops/:shopId/orders/:orderId/assign-rider", async (c) => {
  const authUser = c.get("user");
  const shopId = c.req.param("shopId");
  const orderId = c.req.param("orderId");

  if (!(await isShopWriter(authUser.id, shopId))) {
    return c.json({ error: { code: "NOT_SHOP_WRITER", message: "Only the shop owner or staff can do this" } }, 403);
  }

  const [order] = await db.select({ shopId: orders.shopId }).from(orders).where(eq(orders.id, orderId)).limit(1);
  if (!order || order.shopId !== shopId) {
    return c.json({ error: { code: "ORDER_NOT_FOUND", message: "Order not found" } }, 404);
  }

  try {
    const result = await assignRider(orderId);
    return c.json({ data: result });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    for (const [code, mapped] of Object.entries(ASSIGN_RIDER_ERRORS)) {
      if (message.includes(code)) {
        return c.json({ error: { code, message: mapped.message } }, mapped.status);
      }
    }
    throw err;
  }
});
