import { Hono } from "npm:hono";
import { zValidator } from "npm:@hono/zod-validator";
import { z } from "npm:zod";
import { and, desc, eq, ne, sql } from "npm:drizzle-orm";

import { authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { db } from "../lib/db.ts";
import { addresses } from "../db/schema.ts";

export const addressesRoute = new Hono<AuthEnv>();

addressesRoute.use("/addresses*", authMiddleware);

// Shape mirrors Baker Ally's routes/addresses.ts (list/create/update/delete),
// which is a proven, correct-enough REST shape -- see the chat writeup for
// the one real bug in that file (non-atomic default-address handling) that
// this version does NOT repeat: POST/PATCH here still do their own
// best-effort unset-then-set for the *first-address-is-always-default* and
// *isDefault:true on create* cases (low risk -- these are single-request,
// not the "flip an existing default" race), but the actual
// flip-the-default operation (the one with real concurrent-request risk)
// is routed through rpc_set_default_address (migrations/005) instead of
// being reimplemented as bare sequential statements here.
//
// `location` (GEOGRAPHY(Point,4326)) is accepted in the request body and
// written via a raw `sql` fragment, since drizzle-orm's pg-core has no
// built-in PostGIS column type and this project doesn't need a custom-type
// abstraction for the one geography column that exists so far (Sprint 2's
// `shops.location` will likely want the same treatment -- if a third geo
// column shows up, that's the signal to build the customType properly
// instead of repeating this by hand a third time).

addressesRoute.get("/addresses", async (c) => {
  const authUser = c.get("user");
  const rows = await db
    .select()
    .from(addresses)
    .where(eq(addresses.userId, authUser.id))
    .orderBy(desc(addresses.isDefault), desc(addresses.createdAt));
  return c.json({ data: rows });
});

const latLngSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
});

const createAddressSchema = z.object({
  label: z.string().max(50).optional(),
  line1: z.string().min(1).max(200),
  line2: z.string().max(200).optional(),
  city: z.string().min(1).max(100),
  state: z.string().min(1).max(100),
  pincode: z.string().min(4).max(10),
  location: latLngSchema,
  isDefault: z.boolean().optional(),
});

addressesRoute.post("/addresses", zValidator("json", createAddressSchema), async (c) => {
  const authUser = c.get("user");
  const body = c.req.valid("json");

  const existing = await db
    .select({ id: addresses.id })
    .from(addresses)
    .where(eq(addresses.userId, authUser.id));

  // First address is always default so checkout has one to preselect --
  // same rule as Baker Ally (06_profile_and_account.md Key Rules).
  const makeDefault = existing.length === 0 ? true : body.isDefault === true;

  if (makeDefault && existing.length > 0) {
    await db
      .update(addresses)
      .set({ isDefault: false })
      .where(and(eq(addresses.userId, authUser.id), ne(addresses.isDefault, false)));
  }

  const [created] = await db
    .insert(addresses)
    .values({
      userId: authUser.id,
      label: body.label ?? null,
      line1: body.line1,
      line2: body.line2 ?? null,
      city: body.city,
      state: body.state,
      pincode: body.pincode,
      isDefault: makeDefault,
    })
    .returning();

  // Set the geography column separately -- see file header on why this
  // isn't part of the Drizzle insert above.
  await db.execute(
    sql`UPDATE addresses SET location = ST_SetSRID(ST_MakePoint(${body.location.lng}, ${body.location.lat}), 4326)::geography WHERE id = ${created.id}`,
  );

  return c.json({ data: created }, 201);
});

const updateAddressSchema = z.object({
  label: z.string().max(50).optional(),
  line1: z.string().min(1).max(200).optional(),
  line2: z.string().max(200).optional(),
  city: z.string().min(1).max(100).optional(),
  state: z.string().min(1).max(100).optional(),
  pincode: z.string().min(4).max(10).optional(),
  location: latLngSchema.optional(),
});

addressesRoute.patch("/addresses/:id", zValidator("json", updateAddressSchema), async (c) => {
  const authUser = c.get("user");
  const addressId = c.req.param("id");
  const body = c.req.valid("json");

  const [existing] = await db
    .select({ id: addresses.id })
    .from(addresses)
    .where(and(eq(addresses.id, addressId), eq(addresses.userId, authUser.id)))
    .limit(1);
  if (!existing) {
    return c.json({ error: { code: "ADDRESS_NOT_FOUND", message: "Address not found" } }, 404);
  }

  const [updated] = await db
    .update(addresses)
    .set({
      ...(body.label !== undefined ? { label: body.label } : {}),
      ...(body.line1 !== undefined ? { line1: body.line1 } : {}),
      ...(body.line2 !== undefined ? { line2: body.line2 } : {}),
      ...(body.city !== undefined ? { city: body.city } : {}),
      ...(body.state !== undefined ? { state: body.state } : {}),
      ...(body.pincode !== undefined ? { pincode: body.pincode } : {}),
    })
    .where(eq(addresses.id, addressId))
    .returning();

  if (body.location) {
    await db.execute(
      sql`UPDATE addresses SET location = ST_SetSRID(ST_MakePoint(${body.location.lng}, ${body.location.lat}), 4326)::geography WHERE id = ${addressId}`,
    );
  }

  return c.json({ data: updated });
});

// The one operation that actually has the concurrent-request race Baker
// Ally's version doesn't guard against -- routed through the RPC
// (migrations/005_rpc_set_default_address.sql) instead of hand-rolled
// sequential statements. p_user_id is passed explicitly (not auth.uid())
// because this connection is the service-role pooler connection -- see
// SPRINT_PLANNING.md §5.1.
addressesRoute.post("/addresses/:id/default", async (c) => {
  const authUser = c.get("user");
  const addressId = c.req.param("id");

  try {
    const rows = await db.execute(
      sql`SELECT * FROM rpc_set_default_address(${authUser.id}::uuid, ${addressId}::uuid)`,
    );
    return c.json({ data: rows });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    if (message.includes("ADDRESS_NOT_FOUND_OR_NOT_OWNED")) {
      return c.json({ error: { code: "ADDRESS_NOT_FOUND", message: "Address not found" } }, 404);
    }
    throw err;
  }
});

addressesRoute.delete("/addresses/:id", async (c) => {
  const authUser = c.get("user");
  const addressId = c.req.param("id");

  const [existing] = await db
    .select({ id: addresses.id, isDefault: addresses.isDefault })
    .from(addresses)
    .where(and(eq(addresses.id, addressId), eq(addresses.userId, authUser.id)))
    .limit(1);
  if (!existing) {
    return c.json({ error: { code: "ADDRESS_NOT_FOUND", message: "Address not found" } }, 404);
  }

  await db.delete(addresses).where(eq(addresses.id, addressId));

  if (existing.isDefault) {
    // Promote the most-recently-created remaining address, if any -- same
    // "there must always be a default when one exists" rule as Baker Ally.
    const [next] = await db
      .select({ id: addresses.id })
      .from(addresses)
      .where(eq(addresses.userId, authUser.id))
      .orderBy(desc(addresses.createdAt))
      .limit(1);
    if (next) {
      await db.update(addresses).set({ isDefault: true }).where(eq(addresses.id, next.id));
    }
  }

  return c.json({ data: { ok: true } });
});
