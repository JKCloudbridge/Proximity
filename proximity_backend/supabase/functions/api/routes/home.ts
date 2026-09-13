import { Hono } from "npm:hono";

import { authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { getRepeatProducts } from "../lib/repeatPurchases.ts";

// Sprint 10 -- §7.1/§11's conditional Home section: "Frequently Bought at
// >=3 patterns". Own-user data (§5.2), same authenticated-only shape as
// wishlist.ts/cart.ts -- there's no guest version of "products you
// personally reorder."
//
// **Why this is its own route file, not folded into recommendations.ts or
// orderAgain.ts:** it answers a genuinely different question from both.
// recommendations.ts's "Recommended for you" is trending/cross-sell-based
// and works for guests; this is personal repeat-purchase history only.
// orderAgain.ts's own "Frequently Bought Together" section groups whole
// *orders* (multi-item bundles, lib/frequentlyBoughtGroups.ts); this gate
// is a simpler, product-level question -- see repeatPurchases.ts's header
// for the exact "qualifying repeat-purchase pattern" definition this
// project uses, since SPRINT_PLANNING.md §7.1 names the >=3 threshold but
// never defines what a "pattern" actually is. Deliberately NOT scoped to
// shops near the buyer's current location (unlike recommendations.ts) --
// a product the buyer has genuinely bought before and reorders is relevant
// regardless of where they happen to be standing right now; the buyer's
// existing past purchase, not current proximity, is the relevance signal
// here.
export const homeRoute = new Hono<AuthEnv>();

homeRoute.use("/home/*", authMiddleware);

// Fetches enough rows to answer "does the buyer qualify at all" (>=3) AND
// have something to render in the same call -- no separate COUNT query,
// same "fetch a bit more than you need for display, answer a size question
// from what you already have" judgment call recommendations.ts's own
// candidateCap headroom makes.
const HOME_SECTION_DISPLAY_LIMIT = 10;
const HOME_QUALIFYING_MIN_ORDERS = 2;
const HOME_QUALIFYING_MIN_PRODUCTS = 3;

homeRoute.get("/home/frequently-bought", async (c) => {
  const authUser = c.get("user");

  const products = await getRepeatProducts({
    userId: authUser.id,
    minTimesOrdered: HOME_QUALIFYING_MIN_ORDERS,
    limit: HOME_QUALIFYING_MIN_PRODUCTS + HOME_SECTION_DISPLAY_LIMIT,
  });

  const qualifies = products.length >= HOME_QUALIFYING_MIN_PRODUCTS;

  return c.json({
    data: {
      qualifies,
      products: qualifies ? products.slice(0, HOME_SECTION_DISPLAY_LIMIT) : [],
    },
  });
});
