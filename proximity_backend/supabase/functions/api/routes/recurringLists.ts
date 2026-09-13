import { Hono } from "npm:hono";
import { zValidator } from "npm:@hono/zod-validator";
import { z } from "npm:zod";
import { and, eq, inArray, sql } from "npm:drizzle-orm";

import { authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { db } from "../lib/db.ts";
import { productImages, productVariants, products, recurringListItems, recurringLists } from "../db/schema.ts";

// Sprint 11 -- the Organizer CRUD surface over recurring_lists/
// recurring_list_items (migrations/043). Own-user data (§5.2), same
// authenticated-only shape as wishlist.ts/cart.ts -- a recurring list is
// never shop- or admin-visible.
//
// The two cross-row-atomic operations (create-with-items, replace-items,
// and a schedule edit that has to recompute next_run_at) go through the
// RPCs migrations/044 defines, same "cross-table/cross-row invariant ->
// SECURITY DEFINER function, not a raw client-side multi-statement write"
// bar every prior sprint's own RPCs hold to (§5.1). Pause/resume/rename-
// without-changing-the-schedule/delete are plain single-row Drizzle calls,
// same no-RPC-needed shape riders.ts's own online/offline PATCH already
// established -- not every own-user-data mutation needs one.
export const recurringListsRoute = new Hono<AuthEnv>();

recurringListsRoute.use("/recurring-lists*", authMiddleware);

const itemInputSchema = z.object({
  variantId: z.string().uuid(),
  quantity: z.number().int().positive().max(99).optional(),
});

async function hydrateItems(listId: string) {
  const items = await db.select().from(recurringListItems).where(eq(recurringListItems.recurringListId, listId));
  if (items.length === 0) return [];

  const variantIds = items.map((i) => i.variantId);
  const variantRows = await db.select().from(productVariants).where(inArray(productVariants.id, variantIds));
  const variantById = new Map(variantRows.map((v) => [v.id, v]));

  const productIds = [...new Set(variantRows.map((v) => v.productId))];
  const productRows = productIds.length ? await db.select().from(products).where(inArray(products.id, productIds)) : [];
  const productById = new Map(productRows.map((p) => [p.id, p]));

  const imageRows = productIds.length
    ? await db.select().from(productImages).where(inArray(productImages.productId, productIds)).orderBy(productImages.sortOrder)
    : [];
  const firstImageByProduct = new Map<string, string>();
  for (const image of imageRows) {
    if (!firstImageByProduct.has(image.productId)) firstImageByProduct.set(image.productId, image.imageUrl);
  }

  return items.map((item) => {
    const variant = variantById.get(item.variantId);
    const product = variant ? productById.get(variant.productId) : undefined;
    return {
      id: item.id,
      variantId: item.variantId,
      quantity: item.quantity,
      // Same "flag explicitly, never silently drop the row" rule every
      // other saved-reference list in this codebase follows (wishlist.ts,
      // repeatPurchases.ts) -- a variant that's since been deactivated or
      // deleted still shows, dimmed, not hidden, so the buyer can see and
      // remove it rather than wonder why their list came up short.
      isAvailable: Boolean(variant?.isActive && variant?.stockStatus !== "out_of_stock"),
      product: product
        ? { id: product.id, name: product.name, isVeg: product.isVeg, imageUrl: firstImageByProduct.get(product.id) ?? null }
        : null,
      variant: variant
        ? { unitValue: variant.unitValue, unitLabel: variant.unitLabel, price: variant.price }
        : null,
    };
  });
}

recurringListsRoute.get("/recurring-lists", async (c) => {
  const authUser = c.get("user");
  const lists = await db
    .select({
      id: recurringLists.id,
      name: recurringLists.name,
      cadence: recurringLists.cadence,
      intervalDays: recurringLists.intervalDays,
      timeOfDay: recurringLists.timeOfDay,
      nextRunAt: recurringLists.nextRunAt,
      lastRunAt: recurringLists.lastRunAt,
      isActive: recurringLists.isActive,
      itemCount: sql<number>`(SELECT COUNT(*) FROM recurring_list_items WHERE recurring_list_id = ${recurringLists.id})::integer`,
    })
    .from(recurringLists)
    .where(eq(recurringLists.userId, authUser.id))
    .orderBy(recurringLists.nextRunAt);

  return c.json({ data: lists });
});

recurringListsRoute.get("/recurring-lists/:id", async (c) => {
  const authUser = c.get("user");
  const id = c.req.param("id");

  const [list] = await db
    .select()
    .from(recurringLists)
    .where(and(eq(recurringLists.id, id), eq(recurringLists.userId, authUser.id)))
    .limit(1);
  if (!list) return c.json({ error: { code: "RECURRING_LIST_NOT_FOUND", message: "Recurring list not found" } }, 404);

  const items = await hydrateItems(id);
  return c.json({ data: { ...list, items } });
});

const createSchema = z.object({
  name: z.string().min(1).max(100),
  cadence: z.enum(["daily", "weekly", "biweekly", "monthly", "custom_days"]),
  intervalDays: z.number().int().positive().optional(),
  timeOfDay: z.string().regex(/^\d{2}:\d{2}(:\d{2})?$/, "timeOfDay must be HH:mm or HH:mm:ss"),
  items: z.array(itemInputSchema).min(1).max(50),
});

recurringListsRoute.post("/recurring-lists", zValidator("json", createSchema), async (c) => {
  const authUser = c.get("user");
  const { name, cadence, intervalDays, timeOfDay, items } = c.req.valid("json");

  if (cadence === "custom_days" && !intervalDays) {
    return c.json({ error: { code: "INTERVAL_DAYS_REQUIRED", message: "intervalDays is required for custom_days cadence" } }, 400);
  }

  try {
    // rpc_create_recurring_list's own SETOF result comes back snake_case
    // through this raw db.execute(sql...) path (the same landmine
    // routes/shops.ts's POST /shop/shops comment flags from Sprint 2) --
    // only `id` is grabbed off it (identical in both namings, so safe to
    // read directly); every other field is re-read through Drizzle's own
    // schema-mapped .select() below, same "re-select after the RPC, don't
    // trust its raw row shape" fix Sprint 2 applied rather than carrying a
    // third inconsistent response shape into this sprint.
    const [rawRow] = (await db.execute(sql`
      SELECT id FROM rpc_create_recurring_list(
        ${authUser.id}::uuid, ${name}, ${cadence}, ${intervalDays ?? null}::integer, ${timeOfDay}::time,
        ${JSON.stringify(items)}::jsonb
      )
    `)) as unknown as { id: string }[];

    const [list] = await db.select().from(recurringLists).where(eq(recurringLists.id, rawRow.id)).limit(1);
    const hydrated = await hydrateItems(list.id);
    return c.json({ data: { ...list, items: hydrated } }, 201);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    if (message.includes("EMPTY_ITEM_LIST")) {
      return c.json({ error: { code: "EMPTY_ITEM_LIST", message: "At least one item is required" } }, 400);
    }
    throw err;
  }
});

const updateScheduleSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  cadence: z.enum(["daily", "weekly", "biweekly", "monthly", "custom_days"]).optional(),
  intervalDays: z.number().int().positive().optional(),
  timeOfDay: z
    .string()
    .regex(/^\d{2}:\d{2}(:\d{2})?$/, "timeOfDay must be HH:mm or HH:mm:ss")
    .optional(),
  isActive: z.boolean().optional(),
});

recurringListsRoute.patch("/recurring-lists/:id", zValidator("json", updateScheduleSchema), async (c) => {
  const authUser = c.get("user");
  const id = c.req.param("id");
  const body = c.req.valid("json");

  const [existing] = await db
    .select()
    .from(recurringLists)
    .where(and(eq(recurringLists.id, id), eq(recurringLists.userId, authUser.id)))
    .limit(1);
  if (!existing) return c.json({ error: { code: "RECURRING_LIST_NOT_FOUND", message: "Recurring list not found" } }, 404);

  // isActive is a plain single-column flip, handled separately from (and
  // before) any schedule-affecting field -- see migrations/044's own
  // rpc_update_recurring_list_schedule header for why pausing/resuming
  // deliberately does NOT recompute next_run_at.
  if (body.isActive !== undefined) {
    await db.update(recurringLists).set({ isActive: body.isActive, updatedAt: new Date() }).where(eq(recurringLists.id, id));
  }

  const touchesSchedule = body.name !== undefined || body.cadence !== undefined || body.intervalDays !== undefined || body.timeOfDay !== undefined;
  if (!touchesSchedule) {
    const [updated] = await db.select().from(recurringLists).where(eq(recurringLists.id, id)).limit(1);
    return c.json({ data: { ...updated, items: await hydrateItems(id) } });
  }

  const name = body.name ?? existing.name;
  const cadence = body.cadence ?? existing.cadence;
  // Gated on the FINAL resolved `cadence`, not "either the new or the old
  // value happened to be custom_days" -- a real bug caught before this was
  // called done: that looser condition would have let a PATCH moving
  // cadence FROM 'custom_days' TO e.g. 'weekly' (without also explicitly
  // clearing intervalDays) carry the old intervalDays value forward into a
  // row whose new cadence isn't custom_days at all, which
  // migrations/043's own CHECK constraint (`cadence <> 'custom_days' AND
  // interval_days IS NULL`) would then reject outright.
  const intervalDays = cadence === "custom_days" ? body.intervalDays ?? existing.intervalDays : null;
  const timeOfDay = body.timeOfDay ?? existing.timeOfDay;

  if (cadence === "custom_days" && !intervalDays) {
    return c.json({ error: { code: "INTERVAL_DAYS_REQUIRED", message: "intervalDays is required for custom_days cadence" } }, 400);
  }

  // Same snake_case-raw-row caveat as the create route above -- the RPC's
  // own result is never spread into the response directly.
  await db.execute(sql`
    SELECT id FROM rpc_update_recurring_list_schedule(
      ${id}::uuid, ${authUser.id}::uuid, ${name}, ${cadence}, ${intervalDays}::integer, ${timeOfDay}::time
    )
  `);
  const [updated] = await db.select().from(recurringLists).where(eq(recurringLists.id, id)).limit(1);

  return c.json({ data: { ...updated, items: await hydrateItems(id) } });
});

const replaceItemsSchema = z.object({ items: z.array(itemInputSchema).min(1).max(50) });

recurringListsRoute.put("/recurring-lists/:id/items", zValidator("json", replaceItemsSchema), async (c) => {
  const authUser = c.get("user");
  const id = c.req.param("id");
  const { items } = c.req.valid("json");

  try {
    await db.execute(sql`SELECT * FROM rpc_replace_recurring_list_items(${id}::uuid, ${authUser.id}::uuid, ${JSON.stringify(items)}::jsonb)`);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    if (message.includes("RECURRING_LIST_NOT_FOUND")) {
      return c.json({ error: { code: "RECURRING_LIST_NOT_FOUND", message: "Recurring list not found" } }, 404);
    }
    if (message.includes("EMPTY_ITEM_LIST")) {
      return c.json({ error: { code: "EMPTY_ITEM_LIST", message: "At least one item is required" } }, 400);
    }
    throw err;
  }

  return c.json({ data: { items: await hydrateItems(id) } });
});

recurringListsRoute.delete("/recurring-lists/:id", async (c) => {
  const authUser = c.get("user");
  const id = c.req.param("id");

  const deleted = await db
    .delete(recurringLists)
    .where(and(eq(recurringLists.id, id), eq(recurringLists.userId, authUser.id)))
    .returning({ id: recurringLists.id });
  if (deleted.length === 0) return c.json({ error: { code: "RECURRING_LIST_NOT_FOUND", message: "Recurring list not found" } }, 404);

  return c.json({ data: { id } });
});
