import { Hono } from "npm:hono";
import { zValidator } from "npm:@hono/zod-validator";
import { z } from "npm:zod";
import { and, eq, inArray, sql } from "npm:drizzle-orm";

import { authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { db } from "../lib/db.ts";
import { cartItems, carts, productImages, productVariants, products, shops } from "../db/schema.ts";

// Sprint 6 (§1.5/§7.3). Own-user data (§5.2), same ownership class and
// no-guest-usable-backing shape as wishlist.ts -- every route here needs a
// signed-in buyer. A guest tapping "Add to cart" gets the same "sign in to
// continue" prompt WishlistHeartButton already established, client-side,
// before this ever gets called.
//
// Deliberately NOT the Drift-backed offline-first/guest-cart/optimistic-sync
// architecture SPRINT_PLANNING.md §9's reuse map names ("Drift two-layer
// cart mechanics," borrowed from Baker Ally) -- every list provider this
// project has shipped since Sprint 1 has consistently gone network-only, no
// local cache, with offline support explicitly and repeatedly deferred to
// Sprint 13 polish (categoriesProvider's and nearbyShopsProvider's own
// comments both say so). A guest-cart-that-syncs-on-login also isn't
// implied by anything in this project's own §1.5/§5.2 -- those describe
// cart_items as ordinary own-user data, same ownership class as addresses/
// wishlists, both of which already require sign-in with no local-first
// fallback. Revisiting §9's reuse note here rather than silently ignoring
// it, same as §9 itself already revisited the single-shop cart trigger.
export const cartRoute = new Hono<AuthEnv>();

cartRoute.use("/cart*", authMiddleware);

async function getCartId(userId: string): Promise<string | null> {
  const [cart] = await db.select({ id: carts.id }).from(carts).where(eq(carts.userId, userId)).limit(1);
  return cart?.id ?? null;
}

cartRoute.get("/cart", async (c) => {
  const authUser = c.get("user");
  const cartId = await getCartId(authUser.id);
  if (!cartId) return c.json({ data: [] });

  const items = await db.select().from(cartItems).where(eq(cartItems.cartId, cartId)).orderBy(cartItems.addedAt);
  if (items.length === 0) return c.json({ data: [] });

  // Batch-fetched across every joined table, same "one query per table, not
  // one per row" shape as wishlist.ts's own GET.
  const variantIds = items.map((i) => i.variantId);
  const variantRows = await db.select().from(productVariants).where(inArray(productVariants.id, variantIds));
  const variantById = new Map(variantRows.map((v) => [v.id, v]));

  const productIds = [...new Set(variantRows.map((v) => v.productId))];
  const productRows = productIds.length ? await db.select().from(products).where(inArray(products.id, productIds)) : [];
  const productById = new Map(productRows.map((p) => [p.id, p]));

  // Sprint 7 widened this select beyond {id,name,logoUrl,status}: the
  // checkout screen (§7.4 step 1) has to render the right fulfillment
  // options per shop -- which types it offers, and whether delivery is the
  // shop's own or a Proximity rider's (§1.3's delivery_mode) -- plus its
  // min_order_value, which rpc_place_order enforces at placement
  // (migrations/032) and the buyer deserves to see before getting there.
  // Added to this existing query rather than fetched per-shop on the
  // checkout screen: same "one query per joined table, not one per row"
  // rule this handler already follows, and the cart screen simply ignores
  // the fields it doesn't use.
  const shopIds = [...new Set(productRows.map((p) => p.shopId))];
  const shopRows = shopIds.length
    ? await db
        .select({
          id: shops.id,
          name: shops.name,
          logoUrl: shops.logoUrl,
          status: shops.status,
          supportsPickup: shops.supportsPickup,
          supportsDelivery: shops.supportsDelivery,
          deliveryMode: shops.deliveryMode,
          minOrderValue: shops.minOrderValue,
        })
        .from(shops)
        .where(inArray(shops.id, shopIds))
    : [];
  const shopById = new Map(shopRows.map((s) => [s.id, s]));

  const imageRows = productIds.length
    ? await db.select().from(productImages).where(inArray(productImages.productId, productIds)).orderBy(productImages.sortOrder)
    : [];
  const firstImageByProduct = new Map<string, string>();
  for (const image of imageRows) {
    if (!firstImageByProduct.has(image.productId)) firstImageByProduct.set(image.productId, image.imageUrl);
  }

  const data = items.map((item) => {
    const variant = variantById.get(item.variantId);
    const product = variant ? productById.get(variant.productId) : undefined;
    const shop = product ? shopById.get(product.shopId) : undefined;

    // Same "never silently drop the row, flag availability explicitly"
    // rule wishlist.ts's own header states -- a cart item's variant/product
    // can be deactivated, or its shop suspended, after it was added; the
    // cart screen dims it and offers only "remove," it doesn't just vanish
    // (which would look like the buyer's own quantity edit lost data).
    const isAvailable = Boolean(variant?.isActive && product?.isActive && shop?.status === "approved");

    return {
      id: item.id,
      quantity: item.quantity,
      addedAt: item.addedAt,
      isAvailable,
      variant: variant
        ? {
            id: variant.id,
            unitValue: variant.unitValue,
            unitLabel: variant.unitLabel,
            price: variant.price,
            mrp: variant.mrp,
            stockStatus: variant.stockStatus,
          }
        : null,
      product: product
        ? {
            id: product.id,
            name: product.name,
            isVeg: product.isVeg,
            imageUrl: firstImageByProduct.get(product.id) ?? null,
          }
        : null,
      shop: shop
        ? {
            id: shop.id,
            name: shop.name,
            logoUrl: shop.logoUrl,
            supportsPickup: shop.supportsPickup,
            supportsDelivery: shop.supportsDelivery,
            deliveryMode: shop.deliveryMode,
            minOrderValue: shop.minOrderValue,
          }
        : null,
    };
  });

  return c.json({ data });
});

const addItemSchema = z.object({ variantId: z.string().uuid(), quantity: z.number().int().positive().max(99).optional() });

// Upsert-and-increment, via rpc_add_to_cart (migrations/024) -- not a plain
// Drizzle insert, because get-or-create-the-cart is a real cross-row race
// otherwise (§5.1's bar, same reasoning as rpc_set_default_address). Tapping
// "Add to cart" again on something already in the cart increments quantity
// rather than erroring on cart_items' own unique constraint -- same
// "resubmit is the same call as first" idempotency convention
// rpc_create_rider_profile established.
cartRoute.post("/cart/items", zValidator("json", addItemSchema), async (c) => {
  const authUser = c.get("user");
  const { variantId, quantity } = c.req.valid("json");

  try {
    await db.execute(sql`SELECT * FROM rpc_add_to_cart(${authUser.id}::uuid, ${variantId}::uuid, ${quantity ?? 1}::integer)`);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    if (message.includes("VARIANT_NOT_FOUND")) {
      return c.json({ error: { code: "VARIANT_NOT_FOUND", message: "Product variant not found" } }, 404);
    }
    if (message.includes("OUT_OF_STOCK")) {
      return c.json({ error: { code: "OUT_OF_STOCK", message: "This item is out of stock" } }, 400);
    }
    if (message.includes("INVALID_QUANTITY")) {
      return c.json({ error: { code: "INVALID_QUANTITY", message: "Quantity must be positive" } }, 400);
    }
    throw err;
  }

  // Re-select through Drizzle rather than trust the RPC's raw (snake_case)
  // return -- same landmine-avoidance every RPC-backed route since Sprint 2
  // has followed (routes/shops.ts's POST /shop/shops comment explains it
  // first).
  const cartId = await getCartId(authUser.id);
  const [item] = await db
    .select()
    .from(cartItems)
    .where(and(eq(cartItems.cartId, cartId!), eq(cartItems.variantId, variantId)))
    .limit(1);

  return c.json({ data: item }, 201);
});

// Sprint 10 -- Order Again's "Add All to Cart" / "Add Selected Items to
// Cart" actions (§4/§5 of Baker Ally's `03_order_again_tab.md` prose spec;
// that doc's own §9 names `POST /v1/cart/items/batch` directly, so the path
// is ported verbatim even though the route itself is a fresh implementation
// -- see routes/orderAgain.ts's header for why). Deliberately per-item
// best-effort, not all-or-nothing: §5's own rule is "adds all non-zero,
// in-stock items" -- a group tile can legitimately have one stale/
// deactivated item sitting in an otherwise-good bundle, and refusing the
// whole batch over that one item would be worse than skipping it and
// saying so. Each call into rpc_add_to_cart is already its own atomic,
// idempotent upsert (024) -- looping it sequentially here is safe to retry
// and doesn't need a wrapping transaction of its own.
const batchAddItemSchema = z.object({
  items: z.array(z.object({ variantId: z.string().uuid(), quantity: z.number().int().positive().max(99).optional() })).min(1).max(50),
});

cartRoute.post("/cart/items/batch", zValidator("json", batchAddItemSchema), async (c) => {
  const authUser = c.get("user");
  const { items } = c.req.valid("json");

  const added: string[] = [];
  const failed: { variantId: string; code: string }[] = [];

  for (const item of items) {
    try {
      await db.execute(sql`SELECT * FROM rpc_add_to_cart(${authUser.id}::uuid, ${item.variantId}::uuid, ${item.quantity ?? 1}::integer)`);
      added.push(item.variantId);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      const code = message.includes("VARIANT_NOT_FOUND")
        ? "VARIANT_NOT_FOUND"
        : message.includes("OUT_OF_STOCK")
          ? "OUT_OF_STOCK"
          : message.includes("INVALID_QUANTITY")
            ? "INVALID_QUANTITY"
            : "UNKNOWN_ERROR";
      failed.push({ variantId: item.variantId, code });
    }
  }

  return c.json({ data: { added, failed } }, 201);
});

const updateItemSchema = z.object({ quantity: z.number().int().positive().max(99) });

// Absolute set (the cart screen's own +/- stepper already knows the current
// quantity and sends the new one) -- deliberately different semantics from
// POST above's increment-on-add, same split most cart UIs make between "add
// from a product page" and "edit an existing line." No cross-row invariant
// here (only this one row changes), so a plain scoped Drizzle update is
// enough -- same "not every multi-statement write needs SECURITY DEFINER"
// call shops.ts's business-hours PUT already made.
cartRoute.patch("/cart/items/:id", zValidator("json", updateItemSchema), async (c) => {
  const authUser = c.get("user");
  const itemId = c.req.param("id");
  const { quantity } = c.req.valid("json");

  const cartId = await getCartId(authUser.id);
  if (!cartId) return c.json({ error: { code: "CART_ITEM_NOT_FOUND", message: "Cart item not found" } }, 404);

  const [updated] = await db
    .update(cartItems)
    .set({ quantity })
    .where(and(eq(cartItems.id, itemId), eq(cartItems.cartId, cartId)))
    .returning();

  if (!updated) return c.json({ error: { code: "CART_ITEM_NOT_FOUND", message: "Cart item not found" } }, 404);
  return c.json({ data: updated });
});

cartRoute.delete("/cart/items/:id", async (c) => {
  const authUser = c.get("user");
  const itemId = c.req.param("id");

  const cartId = await getCartId(authUser.id);
  if (!cartId) return c.json({ data: { id: itemId } });

  await db.delete(cartItems).where(and(eq(cartItems.id, itemId), eq(cartItems.cartId, cartId)));
  return c.json({ data: { id: itemId } });
});

// §7.3's section-level "Remove all from this shop" action. cart_items has
// no shop_id of its own (by design, per migrations/023's literal DDL) --
// scoped by first resolving which of this shop's variants are actually
// sitting in the caller's cart, then deleting by id, rather than one
// cross-table DELETE...USING statement -- no concurrent-request race here
// worth an RPC for (deleting your own rows is safe to retry/idempotent),
// same judgment call routes/catalog.ts's getOwnedProduct-then-act shape
// already makes for multi-step-but-not-atomic-risk operations.
cartRoute.delete("/cart/shops/:shopId", async (c) => {
  const authUser = c.get("user");
  const shopId = c.req.param("shopId");

  const cartId = await getCartId(authUser.id);
  if (!cartId) return c.json({ data: { removed: 0 } });

  const shopVariantRows = await db
    .select({ id: productVariants.id })
    .from(productVariants)
    .innerJoin(products, eq(products.id, productVariants.productId))
    .where(eq(products.shopId, shopId));
  const shopVariantIds = shopVariantRows.map((r) => r.id);
  if (shopVariantIds.length === 0) return c.json({ data: { removed: 0 } });

  const deleted = await db
    .delete(cartItems)
    .where(and(eq(cartItems.cartId, cartId), inArray(cartItems.variantId, shopVariantIds)))
    .returning({ id: cartItems.id });

  return c.json({ data: { removed: deleted.length } });
});
