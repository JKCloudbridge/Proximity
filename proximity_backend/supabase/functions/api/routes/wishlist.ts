import { Hono } from "npm:hono";
import { zValidator } from "npm:@hono/zod-validator";
import { z } from "npm:zod";
import { and, desc, eq, inArray } from "npm:drizzle-orm";

import { authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { db } from "../lib/db.ts";
import { productImages, productVariants, products, shops, wishlists } from "../db/schema.ts";

export const wishlistRoute = new Hono<AuthEnv>();

// Own-user data (§5.2), same ownership class as addresses/cart -- every
// route here needs a signed-in buyer, no public read at all (unlike
// catalog.ts/shops.ts, this file has no unauthenticated half).
wishlistRoute.use("/wishlist*", authMiddleware);

wishlistRoute.get("/wishlist", async (c) => {
  const authUser = c.get("user");
  const rows = await db.select().from(wishlists).where(eq(wishlists.userId, authUser.id)).orderBy(desc(wishlists.createdAt));
  if (rows.length === 0) return c.json({ data: [] });

  // Batch-fetched the same way home_repository's nearby-shops route shares
  // one platform_settings/business-hours read across every shop in the
  // response, rather than N round trips -- one query per joined table here,
  // filtered client-side (in this function) by id.
  const productIds = rows.map((r) => r.productId);
  const productRows = await db.select().from(products).where(inArray(products.id, productIds));
  const productById = new Map(productRows.map((p) => [p.id, p]));

  const shopIds = [...new Set(productRows.map((p) => p.shopId))];
  const shopRows = shopIds.length
    ? await db.select({ id: shops.id, name: shops.name, status: shops.status }).from(shops).where(inArray(shops.id, shopIds))
    : [];
  const shopById = new Map(shopRows.map((s) => [s.id, s]));

  const variantRows = await db
    .select()
    .from(productVariants)
    .where(and(inArray(productVariants.productId, productIds), eq(productVariants.isActive, true)));
  const imageRows = await db
    .select()
    .from(productImages)
    .where(inArray(productImages.productId, productIds))
    .orderBy(productImages.sortOrder);

  const data = rows.map((w) => {
    const product = productById.get(w.productId);
    const shop = product ? shopById.get(product.shopId) : undefined;
    const prices = variantRows.filter((v) => v.productId === w.productId).map((v) => v.price);
    const image = imageRows.find((i) => i.productId === w.productId);

    return {
      productId: w.productId,
      addedAt: w.createdAt,
      // A wishlisted product can later be deleted, deactivated, have its
      // shop suspended, or simply have every one of its variants
      // deactivated independently (products/variants toggle separately,
      // migrations/017 vs 018) -- rather than silently drop the row (the
      // buyer would then have no way to find and remove that dead entry),
      // every saved id is always listed and availability is surfaced
      // explicitly; the mobile screen renders an "unavailable" state
      // instead of hiding the row outright.
      isAvailable: Boolean(product?.isActive && shop?.status === "approved" && prices.length > 0),
      product: product
        ? {
            id: product.id,
            name: product.name,
            isVeg: product.isVeg,
            shopId: product.shopId,
            shopName: shop?.name ?? null,
            imageUrl: image?.imageUrl ?? null,
            // The cheapest active variant's price, for the wishlist grid's
            // price line -- the actual variant choice still happens on the
            // PDP, same "wishlist is product-scoped" reasoning as
            // migrations/021's header.
            minPrice: prices.length ? Math.min(...prices) : null,
          }
        : null,
    };
  });

  return c.json({ data });
});

const addSchema = z.object({ productId: z.string().uuid() });

wishlistRoute.post("/wishlist", zValidator("json", addSchema), async (c) => {
  const authUser = c.get("user");
  const { productId } = c.req.valid("json");

  const [product] = await db.select({ id: products.id }).from(products).where(eq(products.id, productId)).limit(1);
  if (!product) return c.json({ error: { code: "PRODUCT_NOT_FOUND", message: "Product not found" } }, 404);

  // Idempotent, same "resubmit is the same call as first" convention rider
  // onboarding (migrations/015) established -- an already-filled heart
  // tapped again (a slow double-tap, a stale UI after a refetch) shouldn't
  // 500 on wishlists' own unique constraint (migrations/021).
  await db.insert(wishlists).values({ userId: authUser.id, productId }).onConflictDoNothing();
  return c.json({ data: { productId } }, 201);
});

wishlistRoute.delete("/wishlist/:productId", async (c) => {
  const authUser = c.get("user");
  const productId = c.req.param("productId");

  // Also idempotent -- removing an id that's already gone (or never there)
  // isn't an error, same reasoning as the add path above; the mobile heart
  // button doesn't need to special-case "already removed."
  await db.delete(wishlists).where(and(eq(wishlists.userId, authUser.id), eq(wishlists.productId, productId)));
  return c.json({ data: { productId } });
});
