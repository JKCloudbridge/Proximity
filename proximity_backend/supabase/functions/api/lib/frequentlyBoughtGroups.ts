import { inArray, sql } from "npm:drizzle-orm";

import { db } from "./db.ts";
import { productImages, productVariants, products, shops } from "../db/schema.ts";

// Sprint 10 -- Order Again tab's "Frequently Bought Together" section
// (§7.6/§9's reuse map names `group_tile`/`group_detail_sheet` as the
// pattern to port). **Checked directly before writing any of this, per the
// standing "read the real files first" rule: neither file exists anywhere
// in Baker Ally's actual working tree** (grepped the whole reference
// project for group_tile/group_detail_sheet/GroupTile/GroupDetailSheet,
// case-insensitive -- zero matches, in code OR planning docs), and
// `baker_ally_flutter/lib` itself is nearly empty (`main.dart` +
// `core/providers.dart` only -- no screens, no cart, nothing resembling a
// shipped Order Again tab). The one thing that DOES exist and is real:
// `Planning docs/Architecture/03_order_again_tab.md`, a full prose spec
// (layout, tile design, bottom-sheet design, API shape, backend pseudocode)
// that was apparently never implemented as code. This module is a fresh
// design against that prose, the same "recoverable spec, not recoverable
// code" situation Sprint 7 hit for `discounts` -- except here even the code
// wasn't real, only the design doc was. Same "documented, not silently
// assumed" discipline every prior sprint's own reuse-map revisit has used
// (Sprint 6 did this for "Drift two-layer cart mechanics," Sprint 8 did it
// for `checkout_repository.dart`).
//
// **What "a group" means in THIS project's data model -- a real decision,
// not a 1:1 port:** Baker Ally's own single-shop-cart/single-order model
// (predating this project's Sprint 6/7 multi-shop-cart/order_groups
// redesign) had exactly one natural unit for "items ordered together": one
// order. This project's checkout produces one `order_groups` row (the
// charge) containing N per-shop `orders` rows (§4.8) -- and a "group" here
// is defined as **the item-set of one `orders` row**, not one
// `order_groups` row. Reasoning: (1) `order_items` FKs to `orders`, not
// `order_groups` -- there is no item-set at the order_groups level at all
// without an extra join-and-flatten step that would silently blend
// multiple shops' items into one "group," which is exactly the ambiguity
// §4.8's own redesign was built to avoid ("never a single merged summary
// line," §7.4 step 5). (2) A group's own "Add All to Cart" action only
// makes sense scoped to one shop anyway -- cart_items has no shop lock
// (§1.5), but re-adding a two-shop bundle as a single action would need to
// silently re-run this project's whole per-shop-fulfillment checkout logic
// on the buyer's behalf, which is checkout's job, not a quick-add
// shortcut's. A group is therefore inherently single-shop, matching how
// this app already groups everything else shop-first (cart screen, §7.3).
export const FREQUENTLY_BOUGHT_GROUP_LIMIT = 10;
// A "group" needs >=2 distinct items -- a single-item order isn't a
// "bundle," it's just a previously-bought product (the other section).
const MIN_ITEMS_PER_GROUP = 2;
// A group only "qualifies" (personal or platform-wide) once the exact same
// item-set has recurred at least once -- one-off multi-item orders are
// real orders, but not yet a "pattern" worth resurfacing as a quick-add
// bundle. Same repeat-count reasoning as repeatPurchases.ts's own
// minTimesOrdered, applied to a whole item-set instead of one product.
const MIN_GROUP_OCCURRENCES = 2;
// Bounded scan, same "documented, not unlimited" discipline
// recommendations.ts's own candidateCap uses -- this computes live off
// `order_items`/`orders` with no materialized/cached aggregate table
// (there's no admin curation surface for this the way product_cross_sell
// has one either, so "live, bounded" is the honest MVP shape here too).
// Revisit with a real cache/materialized view once order volume actually
// makes this scan expensive -- not a concern at this project's current
// (zero) real order volume.
const MAX_CANDIDATE_ORDERS_SCANNED = 2000;

type CandidateOrderRow = {
  order_id: string;
  shop_id: string;
  created_at: string;
  variant_ids: string[];
};

type GroupItem = {
  variantId: string;
  productId: string;
  productName: string;
  isVeg: boolean | null;
  unitValue: string;
  unitLabel: string;
  price: number;
  mrp: number | null;
  imageUrl: string | null;
  isAvailable: boolean;
};

export type FrequentlyBoughtGroup = {
  groupKey: string;
  source: "mine" | "platform";
  timesOrdered: number;
  lastOrderedAt: string;
  shopId: string;
  shopName: string;
  items: GroupItem[];
  totalPrice: number;
  anyUnavailable: boolean;
};

type SignatureEntry = {
  signature: string;
  variantIds: string[];
  shopId: string;
  count: number;
  mostRecentOrderId: string;
  mostRecentCreatedAt: string;
};

function buildSignatureMap(rows: CandidateOrderRow[]): Map<string, SignatureEntry> {
  const bySignature = new Map<string, SignatureEntry>();
  for (const row of rows) {
    // variant_id is a globally-unique UUID (product_variants.id), never
    // shop-scoped, so the joined signature string is already unambiguous
    // across shops -- no need to prefix it with shop_id.
    const signature = row.variant_ids.join(",");
    const existing = bySignature.get(signature);
    if (!existing) {
      bySignature.set(signature, {
        signature,
        variantIds: row.variant_ids,
        shopId: row.shop_id,
        count: 1,
        mostRecentOrderId: row.order_id,
        mostRecentCreatedAt: row.created_at,
      });
    } else {
      existing.count += 1;
      // Rows arrive ORDER BY created_at DESC, so the first occurrence seen
      // per signature is already the most recent -- nothing to compare here.
    }
  }
  return bySignature;
}

async function candidateOrders(userId: string | null): Promise<CandidateOrderRow[]> {
  const rows = (await db.execute(
    userId
      ? sql`
          SELECT oi.order_id, o.shop_id, o.created_at,
                 array_agg(oi.variant_id ORDER BY oi.variant_id) AS variant_ids
          FROM order_items oi
          JOIN orders o ON o.id = oi.order_id
          WHERE o.user_id = ${userId} AND o.status NOT IN ('pending', 'cancelled')
          GROUP BY oi.order_id, o.shop_id, o.created_at
          HAVING COUNT(*) >= ${MIN_ITEMS_PER_GROUP}
          ORDER BY o.created_at DESC
          LIMIT ${MAX_CANDIDATE_ORDERS_SCANNED}
        `
      : // Platform-wide -- anonymised by construction: this query never
        // selects o.user_id at all, only the item-set/shop/recency, exactly
        // matching 03_order_again_tab.md's own "no user data leaked" rule.
        sql`
          SELECT oi.order_id, o.shop_id, o.created_at,
                 array_agg(oi.variant_id ORDER BY oi.variant_id) AS variant_ids
          FROM order_items oi
          JOIN orders o ON o.id = oi.order_id
          WHERE o.status NOT IN ('pending', 'cancelled')
          GROUP BY oi.order_id, o.shop_id, o.created_at
          HAVING COUNT(*) >= ${MIN_ITEMS_PER_GROUP}
          ORDER BY o.created_at DESC
          LIMIT ${MAX_CANDIDATE_ORDERS_SCANNED}
        `,
  )) as unknown as CandidateOrderRow[];
  return rows;
}

async function hydrateGroups(entries: SignatureEntry[], source: "mine" | "platform"): Promise<FrequentlyBoughtGroup[]> {
  if (entries.length === 0) return [];

  const allVariantIds = [...new Set(entries.flatMap((e) => e.variantIds))];
  const shopIds = [...new Set(entries.map((e) => e.shopId))];

  const variantRows = await db.select().from(productVariants).where(inArray(productVariants.id, allVariantIds));
  const variantById = new Map(variantRows.map((v) => [v.id, v]));

  const productIds = [...new Set(variantRows.map((v) => v.productId))];
  const productRows = productIds.length ? await db.select().from(products).where(inArray(products.id, productIds)) : [];
  const productById = new Map(productRows.map((p) => [p.id, p]));

  const shopRows = await db
    .select({ id: shops.id, name: shops.name, status: shops.status })
    .from(shops)
    .where(inArray(shops.id, shopIds));
  const shopById = new Map(shopRows.map((s) => [s.id, s]));

  const imageRows = productIds.length
    ? await db.select().from(productImages).where(inArray(productImages.productId, productIds)).orderBy(productImages.sortOrder)
    : [];
  const firstImageByProduct = new Map<string, string>();
  for (const image of imageRows) {
    if (!firstImageByProduct.has(image.productId)) firstImageByProduct.set(image.productId, image.imageUrl);
  }

  return entries.map((entry) => {
    const shop = shopById.get(entry.shopId);
    const items: GroupItem[] = entry.variantIds.map((variantId) => {
      const variant = variantById.get(variantId);
      const product = variant ? productById.get(variant.productId) : undefined;
      const isAvailable = Boolean(
        variant?.isActive && product?.isActive && shop?.status === "approved" && variant?.stockStatus !== "out_of_stock",
      );
      return {
        variantId,
        productId: product?.id ?? "",
        productName: product?.name ?? "Unavailable item",
        isVeg: product?.isVeg ?? null,
        unitValue: variant?.unitValue ?? "0",
        unitLabel: variant?.unitLabel ?? "",
        price: variant?.price ?? 0,
        mrp: variant?.mrp ?? null,
        imageUrl: product ? firstImageByProduct.get(product.id) ?? null : null,
        isAvailable,
      };
    });

    return {
      groupKey: entry.mostRecentOrderId,
      source,
      timesOrdered: entry.count,
      lastOrderedAt: entry.mostRecentCreatedAt,
      shopId: entry.shopId,
      shopName: shop?.name ?? "Unknown shop",
      items,
      totalPrice: items.filter((i) => i.isAvailable).reduce((sum, i) => sum + i.price, 0),
      anyUnavailable: items.some((i) => !i.isAvailable),
    };
  });
}

// §3's priority order: the buyer's own recurring bundles first (ranked by
// how often THEY ordered that combo), then platform-wide popular bundles
// fill any remaining slots up to FREQUENTLY_BOUGHT_GROUP_LIMIT -- only when
// the buyer has fewer than that many personal ones, and never repeating a
// bundle already shown personally.
export async function getFrequentlyBoughtGroups(userId: string): Promise<FrequentlyBoughtGroup[]> {
  const ownRows = await candidateOrders(userId);
  const ownSignatures = buildSignatureMap(ownRows);

  const personalQualifying = [...ownSignatures.values()]
    .filter((e) => e.count >= MIN_GROUP_OCCURRENCES)
    .sort((a, b) => b.count - a.count || (a.mostRecentCreatedAt < b.mostRecentCreatedAt ? 1 : -1))
    .slice(0, FREQUENTLY_BOUGHT_GROUP_LIMIT);

  const personalGroups = await hydrateGroups(personalQualifying, "mine");

  const remaining = FREQUENTLY_BOUGHT_GROUP_LIMIT - personalGroups.length;
  if (remaining <= 0) return personalGroups;

  const platformRows = await candidateOrders(null);
  const platformSignatures = buildSignatureMap(platformRows);
  const shownSignatures = new Set(personalQualifying.map((e) => e.signature));

  const platformQualifying = [...platformSignatures.values()]
    .filter((e) => e.count >= MIN_GROUP_OCCURRENCES && !shownSignatures.has(e.signature))
    .sort((a, b) => b.count - a.count || (a.mostRecentCreatedAt < b.mostRecentCreatedAt ? 1 : -1))
    .slice(0, remaining);

  const platformGroups = await hydrateGroups(platformQualifying, "platform");

  return [...personalGroups, ...platformGroups];
}
