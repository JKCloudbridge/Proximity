import { Hono } from "npm:hono";
import { zValidator } from "npm:@hono/zod-validator";
import { z } from "npm:zod";
import { desc, eq, sql } from "npm:drizzle-orm";

import { adminMiddleware, authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { db } from "../lib/db.ts";
import { discounts, platformSettings, riders, shops } from "../db/schema.ts";
import { getPlatformLedgerBalances, listLedgerEntries } from "../lib/ledger.ts";
import { getPlatformSalesSummary } from "../lib/salesSummary.ts";

export const adminRoute = new Hono<AuthEnv>();

// §8.6: shop approval queue, rider approval queue -- the "admin panel
// skeleton" this sprint's exit criteria names. Everything under /v1/admin
// requires the admin role claim written by the JWT hook (migrations/004);
// adminMiddleware is requireRole("admin") (middleware/auth.ts).
adminRoute.use("/admin/*", authMiddleware, adminMiddleware);

const shopStatusQuerySchema = z.object({ status: z.enum(["pending", "approved", "suspended"]).optional() });

adminRoute.get("/admin/shops", zValidator("query", shopStatusQuerySchema), async (c) => {
  const { status } = c.req.valid("query");
  const rows = status
    ? await db.select().from(shops).where(eq(shops.status, status)).orderBy(desc(shops.createdAt))
    : await db.select().from(shops).orderBy(desc(shops.createdAt));
  return c.json({ data: rows });
});

adminRoute.post("/admin/shops/:id/approve", async (c) => {
  const shopId = c.req.param("id");
  const [updated] = await db.update(shops).set({ status: "approved", updatedAt: new Date() }).where(eq(shops.id, shopId)).returning();
  if (!updated) return c.json({ error: { code: "SHOP_NOT_FOUND", message: "Shop not found" } }, 404);
  return c.json({ data: updated });
});

// No separate "reject" -- `shops.status` only has pending/approved/suspended
// (migrations/006), so declining or later deactivating a shop are the same
// action at the schema level. The web admin UI labels this differently
// depending on the shop's current status (Reject vs. Suspend) purely as a
// copy choice.
adminRoute.post("/admin/shops/:id/suspend", async (c) => {
  const shopId = c.req.param("id");
  const [updated] = await db.update(shops).set({ status: "suspended", updatedAt: new Date() }).where(eq(shops.id, shopId)).returning();
  if (!updated) return c.json({ error: { code: "SHOP_NOT_FOUND", message: "Shop not found" } }, 404);
  return c.json({ data: updated });
});

const riderVerifiedQuerySchema = z.object({ verified: z.enum(["true", "false"]).optional() });

adminRoute.get("/admin/riders", zValidator("query", riderVerifiedQuerySchema), async (c) => {
  const { verified } = c.req.valid("query");
  const rows = verified !== undefined
    ? await db.select().from(riders).where(eq(riders.isVerified, verified === "true")).orderBy(desc(riders.createdAt))
    : await db.select().from(riders).orderBy(desc(riders.createdAt));
  return c.json({ data: rows });
});

adminRoute.post("/admin/riders/:id/approve", async (c) => {
  const riderId = c.req.param("id");
  const [updated] = await db.update(riders).set({ isVerified: true }).where(eq(riders.id, riderId)).returning();
  if (!updated) return c.json({ error: { code: "RIDER_NOT_FOUND", message: "Rider not found" } }, 404);
  return c.json({ data: updated });
});

// Symmetric with shops' suspend action -- revokes a previously granted
// approval (rider went inactive, KYC turned out to be invalid, etc.)
// without a third `riders.is_verified`-adjacent state to model.
adminRoute.post("/admin/riders/:id/revoke", async (c) => {
  const riderId = c.req.param("id");
  const [updated] = await db.update(riders).set({ isVerified: false }).where(eq(riders.id, riderId)).returning();
  if (!updated) return c.json({ error: { code: "RIDER_NOT_FOUND", message: "Rider not found" } }, 404);
  return c.json({ data: updated });
});

// ---------------------------------------------------------------------------
// Sprint 12 -- §8.6's "platform_settings editor UI (delivery fee/slot window)"
// and §11's own exit criteria: "admin can change the platform delivery fee
// and see it reflected on the next new order." No RPC needed -- unlike
// cross-table writes elsewhere in this project, an admin overwriting one
// platform_settings row is a plain single-row upsert with no cross-row
// invariant to protect (§5.1's bar for "needs a SECURITY DEFINER function"
// isn't met here, same judgment call riders.ts's own online/offline PATCH
// already made for a different table). "Reflected on the next new order" is
// automatic and needs no extra wiring: routes/checkout.ts's own
// readSlotWindow()/readRiderFee() (Sprint 7) already read this same table
// fresh on every /checkout/config and /orders call -- there is no cache
// anywhere in this path to invalidate.
//
// Each known key's `value` shape is validated specifically (a discriminated
// union, not a bare JSONB passthrough) -- migrations/012's own seed-row
// comment is the only place these shapes were ever documented before now;
// letting an admin PATCH an arbitrary JSON blob into a key that
// routes/checkout.ts parses with a specific shape in mind would be a live
// footgun (a typo'd key name in the JSON would silently fall through to
// DEFAULT_SLOT_WINDOW/0 rather than erroring).
// ---------------------------------------------------------------------------

const platformSettingSchema = z.discriminatedUnion("key", [
  z.object({ key: z.literal("platform_rider_delivery_fee"), value: z.object({ amount_paise: z.number().int().min(0) }) }),
  z.object({
    key: z.literal("slot_window"),
    value: z.object({
      start: z.string().regex(/^\d{2}:\d{2}$/, "start must be HH:mm"),
      end: z.string().regex(/^\d{2}:\d{2}$/, "end must be HH:mm"),
      slot_minutes: z.number().int().positive(),
    }),
  }),
  z.object({ key: z.literal("default_shop_commission_pct"), value: z.object({ value: z.number().min(0).max(100) }) }),
]);

adminRoute.get("/admin/platform-settings", async (c) => {
  const rows = await db.select().from(platformSettings);
  return c.json({ data: rows });
});

adminRoute.patch("/admin/platform-settings", zValidator("json", platformSettingSchema), async (c) => {
  const authUser = c.get("user");
  const { key, value } = c.req.valid("json");

  await db.execute(sql`
    INSERT INTO platform_settings (key, value, updated_by, updated_at)
    VALUES (${key}, ${JSON.stringify(value)}::jsonb, ${authUser.id}::uuid, now())
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_by = EXCLUDED.updated_by, updated_at = now()
  `);

  const [updated] = await db.select().from(platformSettings).where(eq(platformSettings.key, key)).limit(1);
  return c.json({ data: updated });
});

// ---------------------------------------------------------------------------
// Sprint 12 -- §11's Sprint 12 entry: "per-shop platform_commission_pct
// override." The column has existed since Sprint 2 (migrations/006,
// defaulted 10.00) and rpc_place_order already snapshots it onto every new
// order's own platform_commission_pct (§4.8) -- this is the first route that
// ever writes it after shop creation. Admin-only, same reasoning
// shops.status/riders.is_verified already establish for "this field is
// platform-governed, not shop-editable" (routes/shops.ts's own PATCH
// deliberately excludes it).
// ---------------------------------------------------------------------------

const commissionOverrideSchema = z.object({ platformCommissionPct: z.number().min(0).max(99.99) });

adminRoute.patch("/admin/shops/:id/commission", zValidator("json", commissionOverrideSchema), async (c) => {
  const shopId = c.req.param("id");
  const { platformCommissionPct } = c.req.valid("json");

  const [updated] = await db
    .update(shops)
    .set({ platformCommissionPct: platformCommissionPct.toFixed(2), updatedAt: new Date() })
    .where(eq(shops.id, shopId))
    .returning();
  if (!updated) return c.json({ error: { code: "SHOP_NOT_FOUND", message: "Shop not found" } }, 404);
  return c.json({ data: updated });
});

// ---------------------------------------------------------------------------
// Sprint 12 -- §11's Sprint 12 entry: "discount authoring UI (discounts
// exists since Sprint 7 with one seeded code and no admin UI to add more)."
// Full CRUD, admin-only. No hard delete -- same "no third state, flip a
// boolean" precedent adminRoute's own shop suspend/rider revoke actions
// already establish -- a discount that's been used (`uses_count > 0`, or
// simply already handed out to buyers) shouldn't disappear from history,
// only stop being redeemable (`isActive: false`).
// ---------------------------------------------------------------------------

const discountUpsertSchema = z.object({
  code: z.string().min(3).max(30).transform((s) => s.trim().toUpperCase()).optional(),
  name: z.string().min(1).max(150),
  type: z.enum(["percent", "flat", "free_shipping"]),
  value: z.number().int().min(0).default(0),
  minOrderValue: z.number().int().min(0).default(0),
  maxUses: z.number().int().positive().optional(),
  isActive: z.boolean().default(true),
  startsAt: z.string().datetime().optional(),
  expiresAt: z.string().datetime().optional(),
});

adminRoute.get("/admin/discounts", async (c) => {
  const rows = await db.select().from(discounts).orderBy(desc(discounts.createdAt));
  return c.json({ data: rows });
});

adminRoute.post("/admin/discounts", zValidator("json", discountUpsertSchema), async (c) => {
  const authUser = c.get("user");
  const body = c.req.valid("json");

  const [created] = await db
    .insert(discounts)
    .values({
      code: body.code ?? null,
      name: body.name,
      type: body.type,
      value: body.value,
      minOrderValue: body.minOrderValue,
      maxUses: body.maxUses ?? null,
      isActive: body.isActive,
      startsAt: body.startsAt ? new Date(body.startsAt) : null,
      expiresAt: body.expiresAt ? new Date(body.expiresAt) : null,
      createdBy: authUser.id,
    })
    .returning();
  return c.json({ data: created }, 201);
});

const discountUpdateSchema = discountUpsertSchema.partial();

adminRoute.patch("/admin/discounts/:id", zValidator("json", discountUpdateSchema), async (c) => {
  const discountId = c.req.param("id");
  const body = c.req.valid("json");

  // Same "omitted key means leave unchanged, explicit null/value means set
  // it" convention every other partial-update route in this codebase uses
  // (routes/catalog.ts's isVeg fix, Sprint 3, is the reference case) -- only
  // spread in fields the caller actually sent.
  const patch: Record<string, unknown> = { ...body };
  if (body.startsAt !== undefined) patch.startsAt = new Date(body.startsAt);
  if (body.expiresAt !== undefined) patch.expiresAt = new Date(body.expiresAt);

  const [updated] = await db.update(discounts).set(patch).where(eq(discounts.id, discountId)).returning();
  if (!updated) return c.json({ error: { code: "DISCOUNT_NOT_FOUND", message: "Discount not found" } }, 404);
  return c.json({ data: updated });
});

// ---------------------------------------------------------------------------
// Sprint 12 -- §8.4/§8.6's platform-wide ledger view + sales summary, the
// admin-side counterpart to routes/shopOrders.ts's own per-shop versions.
// Same lib/ledger.ts / lib/salesSummary.ts these share -- one balance
// formula, one revenue definition, read from both sides rather than
// re-derived twice.
// ---------------------------------------------------------------------------

adminRoute.get("/admin/ledger", async (c) => {
  const balances = await getPlatformLedgerBalances();
  return c.json({ data: { balances } });
});

const adminLedgerEntriesQuerySchema = z.object({
  shopId: z.string().uuid().optional(),
  limit: z.coerce.number().int().min(1).max(200).optional(),
  offset: z.coerce.number().int().min(0).optional(),
});

adminRoute.get("/admin/ledger/entries", zValidator("query", adminLedgerEntriesQuerySchema), async (c) => {
  const { shopId, limit, offset } = c.req.valid("query");
  const entries = await listLedgerEntries({ shopId, limit: limit ?? 50, offset: offset ?? 0 });
  return c.json({ data: entries });
});

const analyticsQuerySchema = z.object({ days: z.coerce.number().int().min(1).max(365).optional() });

adminRoute.get("/admin/analytics/sales-summary", zValidator("query", analyticsQuerySchema), async (c) => {
  const { days } = c.req.valid("query");
  const summary = await getPlatformSalesSummary(days ?? 30);
  return c.json({ data: summary });
});
