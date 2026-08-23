import { createMiddleware } from "npm:hono/factory";
import type { User } from "npm:@supabase/supabase-js";

import { supabaseAdmin } from "../lib/supabaseAdmin.ts";

export type AuthEnv = { Variables: { user: User } };

// The one and only trust boundary in this backend (SPRINT_PLANNING.md §5.1).
// supabaseAdmin.auth.getUser(token) verifies the JWT's signature and looks
// the user up by `sub` -- same pattern as Baker Ally's middleware/auth.ts.
// Every route handler downstream trusts c.get("user") completely; every RPC
// a route calls gets that user's id passed in explicitly rather than
// re-deriving it from auth.uid() (which wouldn't work anyway -- see
// lib/db.ts).
export const authMiddleware = createMiddleware<AuthEnv>(async (c, next) => {
  const token = c.req.header("Authorization")?.replace("Bearer ", "");
  if (!token) {
    return c.json({ error: { code: "UNAUTHORIZED", message: "Missing bearer token" } }, 401);
  }

  const { data, error } = await supabaseAdmin.auth.getUser(token);
  if (error || !data.user) {
    return c.json({ error: { code: "UNAUTHORIZED", message: "Invalid or expired token" } }, 401);
  }

  c.set("user", data.user);
  await next();
});

// Reads the role claim written by migrations/004's JWT hook
// (app_metadata.role). Sprint 2+ is the first real consumer
// (requireRole("shop_owner"), requireRole("admin")) -- included now so the
// pattern exists before it's needed under time pressure.
export const requireRole = (...roles: string[]) =>
  createMiddleware<AuthEnv>(async (c, next) => {
    const user = c.get("user");
    const role = user.app_metadata?.role;
    if (!role || !roles.includes(role)) {
      return c.json({ error: { code: "FORBIDDEN", message: "Insufficient role" } }, 403);
    }
    await next();
  });

export const adminMiddleware = requireRole("admin");
