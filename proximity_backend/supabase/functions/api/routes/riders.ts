import { Hono } from "npm:hono";
import { zValidator } from "npm:@hono/zod-validator";
import { z } from "npm:zod";
import { eq, sql } from "npm:drizzle-orm";

import { authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { db } from "../lib/db.ts";
import { riders } from "../db/schema.ts";

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
// alongside migrations/011's riders_update_own RLS backstop).
const updateRiderStatusSchema = z.object({ status: z.enum(["offline", "available"]) });

ridersRoute.patch("/rider/riders/me/status", zValidator("json", updateRiderStatusSchema), async (c) => {
  const authUser = c.get("user");
  const body = c.req.valid("json");

  const [existing] = await db.select({ id: riders.id, isVerified: riders.isVerified }).from(riders).where(eq(riders.userId, authUser.id)).limit(1);
  if (!existing) return c.json({ error: { code: "RIDER_PROFILE_NOT_FOUND", message: "No rider profile yet" } }, 404);
  if (!existing.isVerified) {
    return c.json({ error: { code: "RIDER_NOT_VERIFIED", message: "Rider is not yet approved" } }, 403);
  }

  const [updated] = await db.update(riders).set({ status: body.status }).where(eq(riders.userId, authUser.id)).returning();
  return c.json({ data: updated });
});
