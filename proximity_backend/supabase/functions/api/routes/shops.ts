import { Hono } from "npm:hono";
import { zValidator } from "npm:@hono/zod-validator";
import { z } from "npm:zod";
import { and, eq, inArray, sql } from "npm:drizzle-orm";

import { authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { db } from "../lib/db.ts";
import { platformSettings, shopBusinessHours, shops } from "../db/schema.ts";
import { getShopMembership, isShopOwner, shopIdsForUser } from "../lib/shopAccess.ts";
import { computeNextSlot, DEFAULT_SLOT_WINDOW, istWeekday, type SlotWindow } from "../lib/slots.ts";

export const shopsRoute = new Hono<AuthEnv>();

shopsRoute.use("/shop/*", authMiddleware);

// §8.1's onboarding flow: shopkeeper signup (proximity_web) -> this endpoint
// -> shop status='pending' -> admin approval (routes/admin.ts). Any
// authenticated user can call this (a buyer becoming a shop owner) --
// there's no requireRole("shop_owner") gate here on purpose, since nobody
// *has* that role until this call succeeds (§1.2: "shop_owner: Created a
// shop"). The actual cross-table write (shop + owner team-member row +
// role flip, all atomic) goes through rpc_create_shop (migrations/014),
// not a bare Drizzle insert -- see that file and SPRINT_PLANNING.md §5.1
// for why.
const weekdayHoursSchema = z.object({
  weekday: z.number().int().min(0).max(6),
  opensAt: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  closesAt: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  isClosed: z.boolean().optional(),
});

const createShopSchema = z.object({
  name: z.string().min(1).max(150),
  description: z.string().max(1000).optional(),
  addressLine: z.string().min(1).max(200),
  city: z.string().min(1).max(100),
  pincode: z.string().min(4).max(10),
  location: z.object({ lat: z.number().min(-90).max(90), lng: z.number().min(-180).max(180) }),
  gstin: z.string().max(20).optional(),
  fssaiLicenseNo: z.string().max(30).optional(),
  serviceRadiusKm: z.number().positive().max(50).optional(),
  supportsPickup: z.boolean(),
  supportsDelivery: z.boolean(),
  deliveryMode: z.enum(["self", "platform", "both"]),
  minOrderValue: z.number().int().min(0).optional(),
  businessHours: z.array(weekdayHoursSchema).max(7).optional(),
});

shopsRoute.post("/shop/shops", zValidator("json", createShopSchema), async (c) => {
  const authUser = c.get("user");
  const body = c.req.valid("json");

  // A shop's delivery_mode='self' means no platform-rider fee ever applies
  // (§1.3) -- pickup-only shops (supportsDelivery=false) must not be
  // 'platform'/'both' either, since there'd be nothing for a rider to do.
  // Not a DB CHECK constraint (delivery_mode and supports_delivery are
  // independent columns), so it's enforced here at the one place shops get
  // created.
  if (!body.supportsDelivery && body.deliveryMode !== "self") {
    return c.json(
      { error: { code: "INVALID_DELIVERY_MODE", message: "A shop that doesn't offer delivery must use delivery_mode 'self'" } },
      400,
    );
  }

  const rpcRows = await db.execute(sql`
    SELECT * FROM rpc_create_shop(
      ${authUser.id}::uuid, ${body.name}, ${body.description ?? null}, ${body.addressLine},
      ${body.city}, ${body.pincode}, ${body.location.lat}::double precision, ${body.location.lng}::double precision,
      ${body.gstin ?? null}, ${body.fssaiLicenseNo ?? null}, ${body.serviceRadiusKm ?? 3.0}::numeric,
      ${body.supportsPickup}, ${body.supportsDelivery}, ${body.deliveryMode}, ${body.minOrderValue ?? 0},
      ${body.businessHours ? JSON.stringify(body.businessHours) : null}::jsonb
    )
  `);

  // rpcRows is a raw postgres.js result -- its columns come back exactly as
  // the RPC's SETOF shops names them (snake_case), not through Drizzle's
  // schema mapping, so it does NOT match the camelCase shape every other
  // response in this file returns. rpc_set_default_address hit this same
  // gap in Sprint 1 and worked around it client-side (Address.fromJson
  // checks both isDefault and is_default) -- rather than carry that same
  // landmine into new code, re-select the created row through Drizzle so
  // POST /shop/shops responds with the same shape GET does.
  const newShopId = (rpcRows[0] as { id: string }).id;
  const [shop] = await db.select().from(shops).where(eq(shops.id, newShopId)).limit(1);

  return c.json({ data: shop }, 201);
});

// Shops the caller is a team member of (any member_role) -- powers both
// "does this user already have a shop" (onboarding redirect logic in
// proximity_web) and the dashboard's own shop-picker once a shop exists.
shopsRoute.get("/shop/shops/mine", async (c) => {
  const authUser = c.get("user");
  const shopIds = await shopIdsForUser(authUser.id);
  if (shopIds.length === 0) return c.json({ data: [] });

  const rows = await db.select().from(shops).where(inArray(shops.id, shopIds));
  return c.json({ data: rows });
});

shopsRoute.get("/shop/shops/:id", async (c) => {
  const authUser = c.get("user");
  const shopId = c.req.param("id");

  const [shop] = await db.select().from(shops).where(eq(shops.id, shopId)).limit(1);
  if (!shop) return c.json({ error: { code: "SHOP_NOT_FOUND", message: "Shop not found" } }, 404);

  // Team membership of any role can view (§5.3 -- owner/staff/delivery all
  // get read access; ownership only gates writes, below).
  const membership = await getShopMembership(authUser.id, shopId);
  if (!membership) return c.json({ error: { code: "SHOP_NOT_FOUND", message: "Shop not found" } }, 404);

  return c.json({ data: shop });
});

const updateShopSchema = createShopSchema.omit({ businessHours: true }).partial();

// Owner-only (§5.3) -- never touches `status`/`platform_commission_pct`,
// same admin-only-column exclusion as the DB-level WITH CHECK in
// migrations/007's shops_owner_update policy (defense in depth: this route
// enforces it even though the service-role connection bypasses RLS
// entirely, per §5.1).
shopsRoute.patch("/shop/shops/:id", zValidator("json", updateShopSchema), async (c) => {
  const authUser = c.get("user");
  const shopId = c.req.param("id");
  const body = c.req.valid("json");

  if (!(await isShopOwner(authUser.id, shopId))) {
    return c.json({ error: { code: "FORBIDDEN", message: "Only the shop owner can edit shop settings" } }, 403);
  }

  const [updated] = await db
    .update(shops)
    .set({
      ...(body.name !== undefined ? { name: body.name } : {}),
      ...(body.description !== undefined ? { description: body.description } : {}),
      ...(body.addressLine !== undefined ? { addressLine: body.addressLine } : {}),
      ...(body.city !== undefined ? { city: body.city } : {}),
      ...(body.pincode !== undefined ? { pincode: body.pincode } : {}),
      ...(body.gstin !== undefined ? { gstin: body.gstin } : {}),
      ...(body.fssaiLicenseNo !== undefined ? { fssaiLicenseNo: body.fssaiLicenseNo } : {}),
      ...(body.serviceRadiusKm !== undefined ? { serviceRadiusKm: String(body.serviceRadiusKm) } : {}),
      ...(body.supportsPickup !== undefined ? { supportsPickup: body.supportsPickup } : {}),
      ...(body.supportsDelivery !== undefined ? { supportsDelivery: body.supportsDelivery } : {}),
      ...(body.deliveryMode !== undefined ? { deliveryMode: body.deliveryMode } : {}),
      ...(body.minOrderValue !== undefined ? { minOrderValue: body.minOrderValue } : {}),
      updatedAt: new Date(),
    })
    .where(eq(shops.id, shopId))
    .returning();

  if (body.location) {
    await db.execute(
      sql`UPDATE shops SET location = ST_SetSRID(ST_MakePoint(${body.location.lng}, ${body.location.lat}), 4326)::geography WHERE id = ${shopId}`,
    );
  }

  return c.json({ data: updated });
});

shopsRoute.get("/shop/shops/:id/business-hours", async (c) => {
  const authUser = c.get("user");
  const shopId = c.req.param("id");

  if (!(await getShopMembership(authUser.id, shopId))) {
    return c.json({ error: { code: "FORBIDDEN", message: "Not a member of this shop" } }, 403);
  }

  const rows = await db.select().from(shopBusinessHours).where(eq(shopBusinessHours.shopId, shopId)).orderBy(shopBusinessHours.weekday);
  return c.json({ data: rows });
});

// Owner-only bulk replace (§5.3) -- simple enough (one shop's 7 rows, no
// cross-table invariant) to do as a plain delete+insert rather than a new
// RPC, same "not every multi-statement write needs SECURITY DEFINER"
// judgment call the addresses routes made for their non-default-flip paths.
shopsRoute.put(
  "/shop/shops/:id/business-hours",
  zValidator("json", z.array(weekdayHoursSchema).max(7)),
  async (c) => {
    const authUser = c.get("user");
    const shopId = c.req.param("id");
    const body = c.req.valid("json");

    if (!(await isShopOwner(authUser.id, shopId))) {
      return c.json({ error: { code: "FORBIDDEN", message: "Only the shop owner can edit business hours" } }, 403);
    }

    await db.delete(shopBusinessHours).where(eq(shopBusinessHours.shopId, shopId));
    if (body.length > 0) {
      await db.insert(shopBusinessHours).values(
        body.map((h) => ({
          shopId,
          weekday: h.weekday,
          opensAt: h.isClosed ? null : h.opensAt ?? null,
          closesAt: h.isClosed ? null : h.closesAt ?? null,
          isClosed: h.isClosed ?? false,
        })),
      );
    }

    const rows = await db.select().from(shopBusinessHours).where(eq(shopBusinessHours.shopId, shopId)).orderBy(shopBusinessHours.weekday);
    return c.json({ data: rows });
  },
);

// ---------------------------------------------------------------------------
// Buyer-facing "Shops near you" -- Sprint 4 (§7.1/§7.2). Public, unauthenticated
// (Home renders for guests too, same rule as categories.ts). No /shop/ prefix,
// so authMiddleware above doesn't apply -- same public/team split catalog.ts
// already established.
//
// `location` has no Drizzle column type (see schema.ts's header), so
// distance itself is computed in a raw SQL fragment; everything past that
// point is re-shaped into a plain camelCase object by hand rather than
// returned as db.execute's raw rows, which come back snake_case straight
// from Postgres (the same landmine flagged in this file's POST /shop/shops
// comment) -- no reason to let that leak into a brand-new response shape.
// ---------------------------------------------------------------------------

const nearQuerySchema = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
  categoryId: z.string().uuid().optional(),
  limit: z.coerce.number().int().min(1).max(100).optional(),
});

type ShopDistanceRow = {
  id: string;
  name: string;
  description: string | null;
  logo_url: string | null;
  cover_image_url: string | null;
  city: string;
  address_line: string;
  service_radius_km: string;
  supports_pickup: boolean;
  supports_delivery: boolean;
  delivery_mode: string;
  min_order_value: number;
  distance_m: number;
};

shopsRoute.get("/shops/near", zValidator("query", nearQuerySchema), async (c) => {
  const { lat, lng, categoryId, limit } = c.req.valid("query");
  const maxResults = limit ?? 30;

  // ST_DWithin(..., 50000) hits idx_shops_location (migrations/006's GIST
  // index) before the exact per-shop service_radius_km cut below narrows
  // further -- 50km is createShopSchema's own serviceRadiusKm ceiling
  // (this file, above), so no shop's real radius can ever exceed it; this
  // is purely an index-friendly pre-filter, not a second business rule.
  const rows = (await db.execute(sql`
    SELECT id, name, description, logo_url, cover_image_url, city, address_line,
           service_radius_km, supports_pickup, supports_delivery, delivery_mode, min_order_value,
           ST_Distance(location, ST_SetSRID(ST_MakePoint(${lng}::double precision, ${lat}::double precision), 4326)::geography) AS distance_m
    FROM shops
    WHERE status = 'approved'
      AND ST_DWithin(location, ST_SetSRID(ST_MakePoint(${lng}::double precision, ${lat}::double precision), 4326)::geography, 50000)
      ${
    categoryId
      ? sql`AND EXISTS (SELECT 1 FROM products p WHERE p.shop_id = shops.id AND p.category_id = ${categoryId}::uuid AND p.is_active = true)`
      : sql``
  }
  `)) as unknown as ShopDistanceRow[];

  const nearby = rows
    .filter((r) => r.distance_m <= Number(r.service_radius_km) * 1000)
    .sort((a, b) => a.distance_m - b.distance_m)
    .slice(0, maxResults);

  if (nearby.length === 0) return c.json({ data: [] });

  // §7.2's NextSlotBadge -- one platform_settings read + one business-hours
  // read for today's weekday, shared across every shop in this response
  // rather than a per-shop round trip.
  const [slotWindowRow] = await db.select().from(platformSettings).where(eq(platformSettings.key, "slot_window")).limit(1);
  const slotWindow = (slotWindowRow?.value as SlotWindow | undefined) ?? DEFAULT_SLOT_WINDOW;
  const now = new Date();
  const weekday = istWeekday(now);
  const shopIds = nearby.map((s) => s.id);
  const hoursRows = await db
    .select()
    .from(shopBusinessHours)
    .where(and(inArray(shopBusinessHours.shopId, shopIds), eq(shopBusinessHours.weekday, weekday)));
  const hoursByShop = new Map(hoursRows.map((h) => [h.shopId, h]));

  const data = nearby.map((s) => ({
    id: s.id,
    name: s.name,
    description: s.description,
    logoUrl: s.logo_url,
    coverImageUrl: s.cover_image_url,
    city: s.city,
    addressLine: s.address_line,
    serviceRadiusKm: Number(s.service_radius_km),
    supportsPickup: s.supports_pickup,
    supportsDelivery: s.supports_delivery,
    deliveryMode: s.delivery_mode,
    minOrderValue: s.min_order_value,
    distanceKm: Math.round((s.distance_m / 1000) * 10) / 10,
    nextSlot: computeNextSlot(now, slotWindow, hoursByShop.get(s.id) ?? null),
  }));

  return c.json({ data });
});
