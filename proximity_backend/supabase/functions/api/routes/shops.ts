import { Hono } from "npm:hono";
import { zValidator } from "npm:@hono/zod-validator";
import { z } from "npm:zod";
import { eq, inArray, sql } from "npm:drizzle-orm";

import { authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { db } from "../lib/db.ts";
import { shopBusinessHours, shops } from "../db/schema.ts";
import { getShopMembership, isShopOwner, shopIdsForUser } from "../lib/shopAccess.ts";

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
