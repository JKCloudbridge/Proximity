import { Hono } from "npm:hono";
import { asc, eq } from "npm:drizzle-orm";

import { db } from "../lib/db.ts";
import { categories } from "../db/schema.ts";

export const categoriesRoute = new Hono();

// Unauthenticated -- the Home category chip row (SPRINT_PLANNING.md §7.1)
// needs to render for guests too, same "browse without login" rule Baker
// Ally applied to its cart. Read-only; writes are admin-only and don't
// exist yet (Sprint 2+, once there's an admin panel to call them from).
categoriesRoute.get("/categories", async (c) => {
  const rows = await db
    .select()
    .from(categories)
    .where(eq(categories.isActive, true))
    .orderBy(asc(categories.sortOrder));
  return c.json({ data: rows });
});
