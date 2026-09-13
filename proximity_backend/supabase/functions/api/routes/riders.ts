import { Hono } from "npm:hono";
import { zValidator } from "npm:@hono/zod-validator";
import { z } from "npm:zod";
import { and, desc, eq, inArray, ne, sql } from "npm:drizzle-orm";

import { authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { db } from "../lib/db.ts";
import { orderStatusHistory, orders, riders, shops } from "../db/schema.ts";

export const ridersRoute = new Hono<AuthEnv>();

ridersRoute.use("/rider/*", authMiddleware);

// §8.5/§4.7's onboarding: mobile signup form -> KYC document uploaded
// directly Flutter -> Supabase Storage (see migrations/011's comment for
// why that's not proxied through this route) -> the resulting object path
// posted here -> is_verified=false -> admin approval (routes/admin.ts). Any
// authenticated user can call this, same reasoning as shop creation --
// nobody has role='rider' until this succeeds.
//
// `kycDocumentUrl` is a storage *path* (`{user_id}/{filename}` inside the
// private rider-documents bucket, migrations/016), not a resolvable URL --
// the bucket is private, so there's no stable public URL for it. Kept the
// DB column/field name as-is (matches SPRINT_PLANNING.md's own loose
// "document URL" phrasing) rather than renaming for pedantic accuracy;
// whatever renders this for admin review (Sprint 2.md's "not yet built"
// list -- inline document preview isn't in this sprint's scope) will need
// to call createSignedUrl(path) at view-time, not treat this as
// directly loadable.
const createRiderSchema = z.object({
  fullName: z.string().min(1).max(150),
  phone: z.string().min(6).max(20),
  vehicleType: z.enum(["bike", "scooter", "bicycle", "on_foot"]).optional(),
  vehicleNumber: z.string().max(20).optional(),
  kycDocumentUrl: z.string().min(1).max(500).optional(),
});

ridersRoute.post("/rider/riders", zValidator("json", createRiderSchema), async (c) => {
  const authUser = c.get("user");
  const body = c.req.valid("json");

  // Idempotent (migrations/015's ON CONFLICT) -- a rider resubmitting after
  // fixing a rejected KYC document calls this same endpoint again rather
  // than needing a separate "update" route.
  await db.execute(sql`
    SELECT * FROM rpc_create_rider_profile(
      ${authUser.id}::uuid, ${body.fullName}, ${body.phone},
      ${body.vehicleType ?? null}, ${body.vehicleNumber ?? null}, ${body.kycDocumentUrl ?? null}
    )
  `);

  // Re-select via Drizzle rather than returning the raw RPC result -- same
  // camelCase-consistency reasoning as shops.ts's POST /shop/shops.
  const [rider] = await db.select().from(riders).where(eq(riders.userId, authUser.id)).limit(1);
  return c.json({ data: rider }, 201);
});

ridersRoute.get("/rider/riders/me", async (c) => {
  const authUser = c.get("user");
  const [rider] = await db.select().from(riders).where(eq(riders.userId, authUser.id)).limit(1);
  if (!rider) return c.json({ error: { code: "RIDER_PROFILE_NOT_FOUND", message: "No rider profile yet" } }, 404);
  return c.json({ data: rider });
});

// Online/offline toggle -- the one self-service field a rider needs before
// the assignment machinery (rpc_assign_rider, Sprint 9) exists to make any
// other field meaningful. `isVerified` is deliberately not settable here,
// same admin-only-column exclusion as shops.ts's PATCH (belt-and-suspenders
// alongside migrations/011's riders_update_own RLS backstop). The schema
// only ever allowed 'offline'/'available' here -- 'on_delivery' has never
// been client-settable, only rpc_assign_rider/rpc_rider_update_status
// (Sprint 9) flip it, system-side.
const updateRiderStatusSchema = z.object({ status: z.enum(["offline", "available"]) });

ridersRoute.patch("/rider/riders/me/status", zValidator("json", updateRiderStatusSchema), async (c) => {
  const authUser = c.get("user");
  const body = c.req.valid("json");

  const [existing] = await db.select({ id: riders.id, isVerified: riders.isVerified, status: riders.status }).from(riders).where(eq(riders.userId, authUser.id)).limit(1);
  if (!existing) return c.json({ error: { code: "RIDER_PROFILE_NOT_FOUND", message: "No rider profile yet" } }, 404);
  if (!existing.isVerified) {
    return c.json({ error: { code: "RIDER_NOT_VERIFIED", message: "Rider is not yet approved" } }, 403);
  }
  // Sprint 9: a rider mid-delivery can't self-toggle out of it -- that state
  // is system-owned (rpc_rider_update_status's own 'delivered' step is the
  // only path back to 'available', migrations/042). Without this guard, a
  // rider could go "offline" while still holding an active assignment,
  // silently orphaning it with no cancellation/reassignment flow anywhere
  // in this project to notice (Sprint 7/8's still-open gap).
  if (existing.status === "on_delivery") {
    return c.json({ error: { code: "CANNOT_CHANGE_STATUS_ON_DELIVERY", message: "Finish your current delivery first" } }, 409);
  }

  const [updated] = await db.update(riders).set({ status: body.status }).where(eq(riders.userId, authUser.id)).returning();
  return c.json({ data: updated });
});

// ---------------------------------------------------------------------------
// Sprint 9 -- location pings while on_delivery (§8.5), feeding both
// rpc_assign_rider's own nearest-rider search (migrations/039) and, once a
// future sprint builds a live map pin (§10 backlog, explicitly deferred),
// the buyer's own view of where their rider actually is. Raw SQL for the
// GEOGRAPHY write, same ST_SetSRID/ST_MakePoint idiom shops.ts's own
// location PATCH already established (Sprint 2) -- riders.current_location
// has no clean Drizzle column type either (schema.ts's header, unchanged).
// No verified-gate here unlike the status toggle above: a location ping is
// harmless from an unverified rider (rpc_assign_rider only ever searches
// is_verified=true rows, migrations/039), and gating it would just mean one
// more round trip for the rider app to check before every ping.
// ---------------------------------------------------------------------------

const updateLocationSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
});

ridersRoute.patch("/rider/riders/me/location", zValidator("json", updateLocationSchema), async (c) => {
  const authUser = c.get("user");
  const body = c.req.valid("json");

  // Existence checked first via a plain Drizzle select, same order-of-
  // operations shops.ts's own location PATCH uses (check, then fire the raw
  // geography UPDATE unconditionally) -- rather than inspecting whatever
  // shape postgres.js's raw execute result takes for a RETURNING-less
  // UPDATE, which nothing else in this codebase relies on either.
  const [existing] = await db.select({ id: riders.id }).from(riders).where(eq(riders.userId, authUser.id)).limit(1);
  if (!existing) return c.json({ error: { code: "RIDER_PROFILE_NOT_FOUND", message: "No rider profile yet" } }, 404);

  await db.execute(
    sql`UPDATE riders SET current_location = ST_SetSRID(ST_MakePoint(${body.lng}, ${body.lat}), 4326)::geography
        WHERE user_id = ${authUser.id}::uuid`,
  );
  return c.json({ data: { ok: true } });
});

// ---------------------------------------------------------------------------
// Sprint 9 -- the rider's own active-assignment list. Hydrates the rider
// home screen on load and re-syncs it whenever the Realtime "assignment"
// channel (proximity_app's own subscription on `orders` filtered to
// rider_id = this rider, migrations/038's new RLS policy is what makes that
// subscription legal at all) fires -- this REST route is what actually
// fetches the full order once the Realtime ping says something changed,
// same "Realtime tells you to refetch, REST is what you render" split
// §7.5's buyer-side tracking uses.
// ---------------------------------------------------------------------------

ridersRoute.get("/rider/riders/me/orders", async (c) => {
  const authUser = c.get("user");
  const [rider] = await db.select({ id: riders.id }).from(riders).where(eq(riders.userId, authUser.id)).limit(1);
  if (!rider) return c.json({ error: { code: "RIDER_PROFILE_NOT_FOUND", message: "No rider profile yet" } }, 404);

  const rows = await db
    .select({
      id: orders.id,
      status: orders.status,
      slotStart: orders.slotStart,
      slotEnd: orders.slotEnd,
      addressId: orders.addressId,
      createdAt: orders.createdAt,
      shopName: shops.name,
      shopAddressLine: shops.addressLine,
      shopCity: shops.city,
    })
    .from(orders)
    .innerJoin(shops, eq(shops.id, orders.shopId))
    .where(and(eq(orders.riderId, rider.id), ne(orders.status, "completed"), ne(orders.status, "cancelled")))
    .orderBy(desc(orders.createdAt));

  // `orders.status` alone can't tell the rider app which ladder button to
  // show next -- migrations/042's own header explains why 'picked_up' and
  // 'out_for_delivery' (this ladder's re-ping step) both leave
  // orders.status at 'out_for_delivery'. `riderLadderStep` is the most
  // recent of this rider's own ladder words
  // (rider_accepted/picked_up/out_for_delivery/delivered) logged for each
  // order, batch-fetched the same "one query, group in JS" way GET
  // /shops/:shopId/products' withImages/withVariants helpers do -- not a
  // per-row round trip.
  const orderIds = rows.map((r) => r.id);
  const ladderRows = orderIds.length
    ? await db
        .select({ orderId: orderStatusHistory.orderId, status: orderStatusHistory.status, changedAt: orderStatusHistory.changedAt })
        .from(orderStatusHistory)
        .where(
          and(
            inArray(orderStatusHistory.orderId, orderIds),
            inArray(orderStatusHistory.status, ["rider_accepted", "picked_up", "out_for_delivery", "delivered"]),
          ),
        )
        .orderBy(desc(orderStatusHistory.changedAt))
    : [];
  const latestLadderStepByOrder = new Map<string, string>();
  for (const row of ladderRows) {
    // Rows arrive newest-first; the first one seen per order is its latest.
    if (!latestLadderStepByOrder.has(row.orderId)) latestLadderStepByOrder.set(row.orderId, row.status);
  }

  return c.json({
    data: rows.map((r) => ({ ...r, riderLadderStep: latestLadderStepByOrder.get(r.id) ?? null })),
  });
});

// ---------------------------------------------------------------------------
// Accept (rpc_rider_accept_order, migrations/041) and the status ladder
// (rpc_rider_update_status, migrations/042). Both scoped to the caller's
// own rider row by the RPC itself, not by this route -- see those
// migrations' headers for why p_rider_user_id, not a pre-fetched rider id,
// is what gets passed (the RPC re-derives it, same belt-and-suspenders
// discipline every RPC in this project applies to its one intended caller).
// ---------------------------------------------------------------------------

ridersRoute.post("/rider/riders/me/orders/:orderId/accept", async (c) => {
  const authUser = c.get("user");
  const orderId = c.req.param("orderId");

  try {
    const rows = (await db.execute(
      sql`SELECT * FROM public.rpc_rider_accept_order(${authUser.id}::uuid, ${orderId}::uuid)`,
    )) as unknown as Record<string, unknown>[];
    return c.json({ data: rows[0] });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    if (message.includes("RIDER_PROFILE_NOT_FOUND")) {
      return c.json({ error: { code: "RIDER_PROFILE_NOT_FOUND", message: "No rider profile yet" } }, 404);
    }
    if (message.includes("ORDER_NOT_ASSIGNED_TO_RIDER")) {
      return c.json({ error: { code: "ORDER_NOT_ASSIGNED_TO_RIDER", message: "This order isn't assigned to you" } }, 403);
    }
    throw err;
  }
});

const riderUpdateStatusSchema = z.object({ status: z.enum(["picked_up", "out_for_delivery", "delivered"]) });

const RIDER_STATUS_ERRORS: Record<string, { status: 400 | 403 | 404 | 409; message: string }> = {
  RIDER_PROFILE_NOT_FOUND: { status: 404, message: "No rider profile yet" },
  ORDER_NOT_ASSIGNED_TO_RIDER: { status: 403, message: "This order isn't assigned to you" },
  ORDER_ALREADY_FINAL: { status: 409, message: "This order is already completed or cancelled" },
  RIDER_HAS_NOT_ACCEPTED: { status: 409, message: "Accept the delivery before picking it up" },
  ORDER_NOT_READY_FOR_PICKUP: { status: 409, message: "The shop hasn't marked this ready yet" },
  NOT_PICKED_UP_YET: { status: 409, message: "Mark it picked up first" },
  NOT_OUT_FOR_DELIVERY_YET: { status: 409, message: "Mark it out for delivery first" },
  INVALID_NEW_STATUS: { status: 400, message: "Invalid status" },
};

ridersRoute.post(
  "/rider/riders/me/orders/:orderId/status",
  zValidator("json", riderUpdateStatusSchema),
  async (c) => {
    const authUser = c.get("user");
    const orderId = c.req.param("orderId");
    const body = c.req.valid("json");

    try {
      const rows = (await db.execute(
        sql`SELECT * FROM public.rpc_rider_update_status(${authUser.id}::uuid, ${orderId}::uuid, ${body.status})`,
      )) as unknown as Record<string, unknown>[];
      return c.json({ data: rows[0] });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      for (const [code, mapped] of Object.entries(RIDER_STATUS_ERRORS)) {
        if (message.includes(code)) {
          return c.json({ error: { code, message: mapped.message } }, mapped.status);
        }
      }
      throw err;
    }
  },
);

// ---------------------------------------------------------------------------
// Sprint 12 -- Decline (rpc_rider_decline_order, migrations/048). §8.5 only
// ever built Accept; this is the other half. Only legal before the rider has
// accepted (ALREADY_ACCEPTED_CANNOT_DECLINE below) -- see that migration's
// own header for the full decline/timeout/reassignment design and why a
// post-accept "I can't do this anymore" is handled by the shop's own manual
// reassign action instead, not this route.
// ---------------------------------------------------------------------------

const declineOrderSchema = z.object({ reason: z.string().max(300).optional() });

const RIDER_DECLINE_ERRORS: Record<string, { status: 403 | 404 | 409; message: string }> = {
  RIDER_PROFILE_NOT_FOUND: { status: 404, message: "No rider profile yet" },
  ORDER_NOT_ASSIGNED_TO_RIDER: { status: 403, message: "This order isn't assigned to you" },
  ORDER_ALREADY_FINAL: { status: 409, message: "This order is already completed or cancelled" },
  ALREADY_ACCEPTED_CANNOT_DECLINE: { status: 409, message: "You've already accepted this delivery -- contact the shop if you can no longer complete it" },
};

ridersRoute.post(
  "/rider/riders/me/orders/:orderId/decline",
  zValidator("json", declineOrderSchema),
  async (c) => {
    const authUser = c.get("user");
    const orderId = c.req.param("orderId");
    const { reason } = c.req.valid("json");

    try {
      const rows = (await db.execute(
        sql`SELECT * FROM public.rpc_rider_decline_order(${authUser.id}::uuid, ${orderId}::uuid, ${reason ?? null})`,
      )) as unknown as Record<string, unknown>[];
      return c.json({ data: rows[0] });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      for (const [code, mapped] of Object.entries(RIDER_DECLINE_ERRORS)) {
        if (message.includes(code)) {
          return c.json({ error: { code, message: mapped.message } }, mapped.status);
        }
      }
      throw err;
    }
  },
);
