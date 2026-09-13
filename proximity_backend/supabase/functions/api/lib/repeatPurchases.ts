import { inArray, sql } from "npm:drizzle-orm";

import { db } from "./db.ts";
import { productImages } from "../db/schema.ts";

// Sprint 10 -- shared query behind two features that both need "products
// this buyer has ordered before," at two different thresholds:
//   1. Order Again's "Previously Bought" section (routes/orderAgain.ts) --
//      every previously-bought product, no threshold, most-recently-bought
//      first (Baker Ally's own `03_order_again_tab.md` §6/§9 spec, ported
//      against prose -- see that route file's header for why prose, not
//      code: no `previously-bought` route/screen exists anywhere in Baker
//      Ally's actual working tree, checked directly).
//   2. Home's conditional "Frequently Bought" section (routes/home.ts,
//      §7.1/§11: "Frequently Bought at >=3 patterns") -- a narrower
//      question SPRINT_PLANNING.md names but never precisely defines.
//
// **Decided here, explicitly, since no other part of this project defines
// it precisely enough to implement:**
//   - A product counts as "previously bought" if it has >=1 `order_items`
//     row on any of the buyer's own `orders` whose status has reached at
//     least 'confirmed' -- i.e. NOT 'pending' (an unpaid, not-yet-confirmed
//     placement was never a real purchase) and NOT 'cancelled'.
//   - A "qualifying repeat-purchase pattern" (Home's own term) is a
//     previously-bought product ordered on **>=2 distinct such `orders`
//     rows** -- genuinely reordered at least once, not just bought at
//     quantity>1 on a single order. Home's section shows only when the
//     buyer has >=3 distinct qualifying products (routes/home.ts enforces
//     the ">=3" count; this function just answers "how many times has the
//     buyer ordered each product," at whatever threshold the caller asks
//     for via `minTimesOrdered`).
// This is a product-level definition (one item, not a multi-item combo) --
// deliberately a different, simpler concept from Order Again's own
// "Frequently Bought Together" section (lib/frequentlyBoughtGroups.ts),
// which groups by an entire order's item-set. The two features share a
// name-shaped resemblance ("frequently bought") but answer different
// questions; see routes/home.ts's header for why Home's gate uses this
// simpler, product-level definition rather than the group one.
export const REPEAT_PURCHASE_EXCLUDED_STATUSES = ["pending", "cancelled"] as const;

type RepeatProductRow = {
  variant_id: string;
  product_id: string;
  product_name: string;
  is_veg: boolean | null;
  variant_unit_value: string;
  variant_unit_label: string;
  price: number;
  mrp: number | null;
  stock_status: string;
  variant_active: boolean;
  product_active: boolean;
  shop_id: string;
  shop_name: string;
  shop_logo_url: string | null;
  shop_status: string;
  times_ordered: number;
  last_ordered_at: string;
};

export type RepeatProduct = {
  variantId: string;
  productId: string;
  name: string;
  isVeg: boolean | null;
  unitValue: string;
  unitLabel: string;
  price: number;
  mrp: number | null;
  imageUrl: string | null;
  isAvailable: boolean;
  shopId: string;
  shopName: string;
  shopLogoUrl: string | null;
  timesOrdered: number;
  lastOrderedAt: string;
};

async function attachImages(rows: RepeatProductRow[]): Promise<RepeatProduct[]> {
  const productIds = [...new Set(rows.map((r) => r.product_id))];
  const imageRows = productIds.length
    ? await db.select().from(productImages).where(inArray(productImages.productId, productIds)).orderBy(productImages.sortOrder)
    : [];
  const firstImageByProduct = new Map<string, string>();
  for (const image of imageRows) {
    if (!firstImageByProduct.has(image.productId)) firstImageByProduct.set(image.productId, image.imageUrl);
  }

  // Same "flag unavailable explicitly, never silently drop the row" rule
  // wishlist.ts/cart.ts both already follow -- a previously-bought product
  // is exactly the kind of thing §6's own "Out-of-stock items are shown"
  // rule (03_order_again_tab.md) asks to keep visible, dimmed, not hidden.
  return rows.map((r) => ({
    variantId: r.variant_id,
    productId: r.product_id,
    name: r.product_name,
    isVeg: r.is_veg,
    unitValue: r.variant_unit_value,
    unitLabel: r.variant_unit_label,
    price: r.price,
    mrp: r.mrp,
    imageUrl: firstImageByProduct.get(r.product_id) ?? null,
    isAvailable: r.variant_active && r.product_active && r.shop_status === "approved" && r.stock_status !== "out_of_stock",
    shopId: r.shop_id,
    shopName: r.shop_name,
    shopLogoUrl: r.shop_logo_url,
    timesOrdered: r.times_ordered,
    lastOrderedAt: r.last_ordered_at,
  }));
}

// One row per distinct product-variant this buyer has ordered, most
// recently bought first (Baker Ally's own §10 pseudocode used
// `selectDistinctOn` -- this uses GROUP BY/HAVING instead, since this
// project also needs the >=N-times threshold HAVING gives for free, and
// tracing every non-aggregated SELECT column against an explicit GROUP BY
// list is this codebase's own established discipline for exactly this
// shape of query, Sprint 6's recommendations.ts comment says so directly).
// `minTimesOrdered` is the one knob both callers share -- see this file's
// header for the two values they pass.
export async function getRepeatProducts({
  userId,
  minTimesOrdered = 1,
  limit,
  offset = 0,
}: {
  userId: string;
  minTimesOrdered?: number;
  limit: number;
  offset?: number;
}): Promise<RepeatProduct[]> {
  // Sprint 11 re-review fix (see this file's header -- this was a real bug,
  // not a style nit): the original query grouped by `pv.id` (variant), not
  // `p.id` (product), while every caller and this file's own header treat
  // the result as "distinct products." A product re-ordered under two
  // different variants (e.g. 200g and 500g of the same item, each bought
  // on >=2 separate orders) came back as TWO rows here -- which let Home's
  // own ">=3 qualifying products" gate (routes/home.ts) fire off only 2
  // real products, directly contradicting Sprint 10's own exit criteria
  // ("an account with fewer does not [see the section]"). Fixed by
  // aggregating at the product level first (CTE `per_product`, counting
  // DISTINCT orders per product regardless of which variant was in each),
  // then picking one representative variant per product -- the variant
  // actually used on that product's own most recent qualifying order
  // (`DISTINCT ON (product_id) ... ORDER BY created_at DESC`), so "Add to
  // cart" still adds a real, specific variant rather than an arbitrary one.
  const rows = (await db.execute(sql`
    WITH per_item AS (
      SELECT p.id AS product_id, pv.id AS variant_id, o.id AS order_id, o.created_at
      FROM order_items oi
      JOIN orders o ON o.id = oi.order_id
      JOIN product_variants pv ON pv.id = oi.variant_id
      JOIN products p ON p.id = pv.product_id
      WHERE o.user_id = ${userId}
        AND o.status NOT IN ('pending', 'cancelled')
    ),
    per_product AS (
      SELECT product_id,
             COUNT(DISTINCT order_id)::integer AS times_ordered,
             MAX(created_at) AS last_ordered_at
      FROM per_item
      GROUP BY product_id
      HAVING COUNT(DISTINCT order_id) >= ${minTimesOrdered}
    ),
    representative_variant AS (
      SELECT DISTINCT ON (product_id) product_id, variant_id
      FROM per_item
      ORDER BY product_id, created_at DESC
    )
    SELECT rv.variant_id, pp.product_id, p.name AS product_name, p.is_veg,
           pv.unit_value AS variant_unit_value, pv.unit_label AS variant_unit_label,
           pv.price, pv.mrp, pv.stock_status, pv.is_active AS variant_active,
           p.is_active AS product_active,
           s.id AS shop_id, s.name AS shop_name, s.logo_url AS shop_logo_url, s.status AS shop_status,
           pp.times_ordered, pp.last_ordered_at
    FROM per_product pp
    JOIN representative_variant rv ON rv.product_id = pp.product_id
    JOIN products p ON p.id = pp.product_id
    JOIN product_variants pv ON pv.id = rv.variant_id
    JOIN shops s ON s.id = p.shop_id
    ORDER BY pp.last_ordered_at DESC
    LIMIT ${limit} OFFSET ${offset}
  `)) as unknown as RepeatProductRow[];

  return attachImages(rows);
}
