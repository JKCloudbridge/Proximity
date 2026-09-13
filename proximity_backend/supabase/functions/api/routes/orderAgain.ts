import { Hono } from "npm:hono";
import { zValidator } from "npm:@hono/zod-validator";
import { z } from "npm:zod";

import { authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { getRepeatProducts } from "../lib/repeatPurchases.ts";
import { getFrequentlyBoughtGroups } from "../lib/frequentlyBoughtGroups.ts";

// Sprint 10 -- the fourth bottom-nav tab (§7.1/§7.6), replacing
// PlaceholderScreen(title: 'Order Again'). Own-user data (§5.2), same
// authenticated-only shape as wishlist.ts/cart.ts.
//
// §9's reuse map names Baker Ally's `group_tile`/`group_detail_sheet` as
// the pattern to port -- **checked directly before writing anything here,
// per the standing rule, and neither exists in Baker Ally's actual working
// tree** (grepped the whole reference project, case-insensitive: zero
// matches in code or planning docs beyond filenames). What DOES exist:
// `Planning docs/Architecture/03_order_again_tab.md`, a complete prose
// spec that documents a tab apparently never implemented as code -- no
// `/v1/order-again/*` route, no cart-batch route, nothing beyond the
// `baker_ally_flutter/lib` folder's two files (`main.dart`,
// `core/providers.dart`). Both routes below are a fresh design against
// that prose (§9/§10 of that doc), the same "recoverable spec, not
// recoverable code" situation this project has now hit for a second reuse-
// map entry (Sprint 6 found this for "Drift two-layer cart mechanics";
// Sprint 8 found `checkout_repository.dart` didn't exist either) -- see
// lib/frequentlyBoughtGroups.ts's own header for the one real *data-model*
// decision this port had to make (what "a group" means in this project's
// multi-shop order_groups/orders shape, since Baker Ally's own cart/order
// predates that redesign entirely).
export const orderAgainRoute = new Hono<AuthEnv>();

orderAgainRoute.use("/order-again/*", authMiddleware);

// §9's own table: `GET /v1/order-again/frequently-bought`. Baker Ally's
// prose returns "user groups first, then platform-wide popular groups" in
// one flat list (§3's priority order) -- lib/frequentlyBoughtGroups.ts
// already returns them pre-ordered that way (`source` on each entry tells
// the client which is which, for the tile's own "anonymised" framing --
// nothing here needs client-side re-sorting).
orderAgainRoute.get("/order-again/frequently-bought", async (c) => {
  const authUser = c.get("user");
  const groups = await getFrequentlyBoughtGroups(authUser.id);
  return c.json({ data: groups });
});

// §9's own table: `GET /v1/order-again/previously-bought?page=1&limit=20`.
// Ported as `limit`/`offset` rather than `page`, matching this codebase's
// own existing pagination-less convention elsewhere (nothing else in this
// project paginates by page number) -- functionally identical to §9's own
// pseudocode, just offset-shaped. §6's own rule: infinite scroll, not
// numbered pages; the client just keeps incrementing offset by the
// previous page's length.
const previouslyBoughtQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(50).optional(),
  offset: z.coerce.number().int().min(0).optional(),
});

orderAgainRoute.get("/order-again/previously-bought", zValidator("query", previouslyBoughtQuerySchema), async (c) => {
  const authUser = c.get("user");
  const { limit, offset } = c.req.valid("query");
  const pageSize = limit ?? 20;

  // No repeat-count threshold here (minTimesOrdered defaults to 1) -- §6's
  // own rule: "Out-of-stock items are shown... user should know the
  // product exists even if temporarily unavailable," i.e. every previously
  // bought product belongs in this list, not just the reordered ones (that
  // narrower question is Home's own gate, routes/home.ts).
  const products = await getRepeatProducts({ userId: authUser.id, limit: pageSize + 1, offset: offset ?? 0 });
  const hasMore = products.length > pageSize;

  return c.json({
    data: products.slice(0, pageSize),
    hasMore,
  });
});
