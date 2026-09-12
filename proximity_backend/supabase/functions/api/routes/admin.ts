import { Hono } from "npm:hono";
import { zValidator } from "npm:@hono/zod-validator";
import { z } from "npm:zod";
import { desc, eq } from "npm:drizzle-orm";

import { adminMiddleware, authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { db } from "../lib/db.ts";
import { riders, shops } from "../db/schema.ts";

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
