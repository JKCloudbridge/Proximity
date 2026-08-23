import { Hono } from "npm:hono";
import { eq } from "npm:drizzle-orm";

import { authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { db } from "../lib/db.ts";
import { users } from "../db/schema.ts";

export const authRoute = new Hono<AuthEnv>();

// Signup-hook replacement, same role Baker Ally's /auth/me plays: the first
// authenticated call after any sign-in (Email OTP, Google, Apple)
// idempotently creates the public.users row with the default 'buyer' role,
// then returns {user, role} either way. Flutter's authProvider calls this
// once per session sync to hydrate itself (proximity_app's auth_provider.dart
// _sync()). Simpler than Baker Ally's version: no separate roles table to
// join (SPRINT_PLANNING.md §4.1 -- role is a plain CHECK column here), so
// there's no ROLE_NOT_SEEDED failure mode to handle.
authRoute.post("/auth/me", authMiddleware, async (c) => {
  const authUser = c.get("user");

  const existing = await db.select().from(users).where(eq(users.id, authUser.id)).limit(1);

  if (existing.length > 0) {
    return c.json({ data: { user: existing[0], role: existing[0].role } });
  }

  const [created] = await db
    .insert(users)
    .values({
      id: authUser.id,
      email: authUser.email ?? null,
      phone: authUser.phone ?? null,
      // role defaults to 'buyer' at the DB level (migrations/001) -- not
      // repeated here so there's exactly one place that decides the default.
    })
    .returning();

  return c.json({ data: { user: created, role: created.role } }, 201);
});
