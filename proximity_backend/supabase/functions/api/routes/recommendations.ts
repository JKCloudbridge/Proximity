import { Hono } from "npm:hono";
import { zValidator } from "npm:@hono/zod-validator";
import { z } from "npm:zod";
import { eq, inArray, sql } from "npm:drizzle-orm";

import { optionalAuthMiddleware, type OptionalAuthEnv } from "../middleware/auth.ts";
import { db } from "../lib/db.ts";
import { productCrossSell, productImages, wishlists } from "../db/schema.ts";

// Sprint 6 (§7.1's "Recommended for you" Home section, §11's Sprint 6 entry:
// "product_cross_sell + trending fallback"). Public -- guests see Home's
// Recommended-for-you row too -- but personalizes off the caller's own
// wishlist when signed in, via optionalAuthMiddleware (this route's only
// consumer so far).
//
// §4.10 says product_cross_sell "carries over unchanged from v1" without
// giving its DDL -- same fresh-design-against-prose situation Sprint 5's
// wishlists and this sprint's own carts hit, except here the v1 original
// turned out to be recoverable from the read-only Baker Ally reference
// project rather than genuinely lost -- see migrations/025's header. Worth
// being plain about the practical consequence: **no admin route curates
// product_cross_sell yet** (not itemized anywhere in §8.6's admin scope),
// so `sourceProductId -> recommendedProductId` rows never get created in
// this sprint's own code, and the personalization path below finds zero
// candidates in any real run right now. It's still built correctly (finds
// real rows the moment a future admin UI writes any), rather than skipped,
// but the *trending* fallback is what actually powers this section today --
// flagging that honestly rather than implying personalization is live.
//
// "Trending" has no order-history table to draw on yet (order_groups/orders
// are Sprint 7's job) -- defined here as total quantity currently sitting in
// any buyer's cart_items (Sprint 6's own new table), which is a genuine,
// real signal from the moment carts start filling, not a placeholder. Falls
// through to newest-first (p.created_at DESC as the ORDER BY's second key)
// on a cold/empty database, so this section still shows *something*
// meaningful before any cart activity exists, rather than an empty row.
//
// Scoped to shops near the buyer, same ST_DWithin-then-service_radius_km cut
// as GET /v1/shops/near (routes/shops.ts) -- recommending a product from a
// shop 500km away is useless on a hyperlocal marketplace, and lat/lng is
// something Home already has in hand via buyerLocationProvider.
export const recommendationsRoute = new Hono<OptionalAuthEnv>();

const recommendedQuerySchema = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
  limit: z.coerce.number().int().min(1).max(30).optional(),
});

type CandidateRow = {
  id: string;
  name: string;
  is_veg: boolean | null;
  shop_id: string;
  shop_name: string;
  shop_logo_url: string | null;
  distance_m: number;
  min_price: number;
  trend_score: number;
};

recommendationsRoute.get("/recommended", optionalAuthMiddleware, zValidator("query", recommendedQuerySchema), async (c) => {
  const authUser = c.get("user");
  const { lat, lng, limit } = c.req.valid("query");
  const maxResults = limit ?? 10;
  // Fetch extra headroom beyond maxResults so wishlist-exclusion and
  // cross-sell re-ranking (below) still have enough candidates left to fill
  // a full row, rather than fetching exactly maxResults and then filtering
  // some away.
  const candidateCap = Math.min(60, maxResults * 3 + 10);

  const rows = (await db.execute(sql`
    SELECT p.id, p.name, p.is_veg, p.shop_id, s.name AS shop_name, s.logo_url AS shop_logo_url,
           ST_Distance(s.location, ST_SetSRID(ST_MakePoint(${lng}::double precision, ${lat}::double precision), 4326)::geography) AS distance_m,
           MIN(pv.price) AS min_price,
           -- SUM(integer) is bigint in Postgres, which postgres.js returns
           -- as a JS string, not a number -- cast back down since real
           -- per-product cart quantities never approach int4's range, and
           -- this column is only ever used for the ORDER BY below anyway
           -- (never read back out in the response mapping further down).
           COALESCE(SUM(ci.quantity), 0)::integer AS trend_score
    FROM products p
    JOIN shops s ON s.id = p.shop_id
    JOIN product_variants pv ON pv.product_id = p.id AND pv.is_active = true
    LEFT JOIN cart_items ci ON ci.variant_id = pv.id
    WHERE p.is_active = true
      AND s.status = 'approved'
      AND ST_DWithin(s.location, ST_SetSRID(ST_MakePoint(${lng}::double precision, ${lat}::double precision), 4326)::geography, 50000)
    GROUP BY p.id, p.name, p.is_veg, p.shop_id, p.created_at, s.id, s.name, s.logo_url, s.location, s.service_radius_km
    HAVING ST_Distance(s.location, ST_SetSRID(ST_MakePoint(${lng}::double precision, ${lat}::double precision), 4326)::geography) <= s.service_radius_km * 1000
    ORDER BY trend_score DESC, p.created_at DESC
    LIMIT ${candidateCap}
  `)) as unknown as CandidateRow[];

  if (rows.length === 0) return c.json({ data: [] });

  // Personalization: source products are the caller's own wishlist (the one
  // real per-buyer signal that exists before order history does, Sprint 10)
  // -- both queries below are plain Drizzle, no raw-array-parameter binding
  // needed anywhere in this route.
  let boostedIds = new Set<string>();
  let wishlistProductIds = new Set<string>();
  if (authUser) {
    const wishlistRows = await db.select({ productId: wishlists.productId }).from(wishlists).where(eq(wishlists.userId, authUser.id));
    wishlistProductIds = new Set(wishlistRows.map((w) => w.productId));
    if (wishlistProductIds.size > 0) {
      const crossSellRows = await db
        .select({ recommendedProductId: productCrossSell.recommendedProductId })
        .from(productCrossSell)
        .where(inArray(productCrossSell.sourceProductId, [...wishlistProductIds]))
        .orderBy(productCrossSell.sortOrder);
      boostedIds = new Set(crossSellRows.map((r) => r.recommendedProductId));
    }
  }

  // Never recommend something already saved -- filter first, then apply the
  // cross-sell boost as a stable re-sort (boosted items float to the front,
  // relative order otherwise unchanged, i.e. still trend/recency-ordered
  // within each group) before truncating to what the caller asked for.
  const eligible = rows.filter((r) => !wishlistProductIds.has(r.id));
  const ranked = [...eligible].sort((a, b) => Number(boostedIds.has(b.id)) - Number(boostedIds.has(a.id)));
  const selected = ranked.slice(0, maxResults);

  const productIds = selected.map((r) => r.id);
  const imageRows = await db.select().from(productImages).where(inArray(productImages.productId, productIds)).orderBy(productImages.sortOrder);
  const firstImageByProduct = new Map<string, string>();
  for (const image of imageRows) {
    if (!firstImageByProduct.has(image.productId)) firstImageByProduct.set(image.productId, image.imageUrl);
  }

  const data = selected.map((r) => ({
    productId: r.id,
    name: r.name,
    isVeg: r.is_veg,
    shopId: r.shop_id,
    shopName: r.shop_name,
    shopLogoUrl: r.shop_logo_url,
    imageUrl: firstImageByProduct.get(r.id) ?? null,
    minPrice: r.min_price,
    distanceKm: Math.round((r.distance_m / 1000) * 10) / 10,
  }));

  return c.json({ data });
});
