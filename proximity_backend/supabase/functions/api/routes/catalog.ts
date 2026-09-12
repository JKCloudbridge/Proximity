import { Hono } from "npm:hono";
import { zValidator } from "npm:@hono/zod-validator";
import { z } from "npm:zod";
import { and, eq, inArray } from "npm:drizzle-orm";

import { authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { db } from "../lib/db.ts";
import { productImages, productVariants, products, shopSubCategories, shops } from "../db/schema.ts";
import { getShopMembership, isShopWriter } from "../lib/shopAccess.ts";

export const catalogRoute = new Hono<AuthEnv>();

// Same split as shops.ts: everything under /shop/* is shop-team-only
// (§8.2's dashboard catalog CRUD); the routes without that prefix, at the
// bottom of this file, are the buyer-facing public read API this sprint's
// exit criteria names -- unauthenticated, filtered to approved shops/active
// rows, same shape as categories.ts's public GET.
catalogRoute.use("/shop/*", authMiddleware);

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

// Every product/variant/image route takes both :shopId and either :id or
// :productId in its path -- this fetches the product and confirms it
// actually belongs to :shopId, so a caller who's a writer on shop A can't
// reach shop B's product just by knowing its id (isShopWriter alone
// wouldn't catch that -- it only checks the path's shopId, not which shop
// the target row is really in).
async function getOwnedProduct(shopId: string, productId: string) {
  const [product] = await db.select().from(products).where(and(eq(products.id, productId), eq(products.shopId, shopId))).limit(1);
  return product ?? null;
}

async function withVariants<T extends { id: string }>(rows: T[]) {
  if (rows.length === 0) return rows.map((r) => ({ ...r, variants: [] }));
  const ids = rows.map((r) => r.id);
  const variants = await db.select().from(productVariants).where(inArray(productVariants.productId, ids));
  return rows.map((r) => ({ ...r, variants: variants.filter((v) => v.productId === r.id) }));
}

// Sprint 5. Deliberately a separate helper from withVariants above rather
// than folding images into it -- the shop-team dashboard's product list
// (GET /shop/shops/:shopId/products) doesn't need thumbnails and shares
// withVariants; only this file's buyer-facing listing (below) needs images
// too, for the shop-detail product grid (§7.1) to have a thumbnail per
// tile without a second round trip per product.
async function withImages<T extends { id: string }>(rows: T[]) {
  if (rows.length === 0) return rows.map((r) => ({ ...r, images: [] }));
  const ids = rows.map((r) => r.id);
  const images = await db.select().from(productImages).where(inArray(productImages.productId, ids)).orderBy(productImages.sortOrder);
  return rows.map((r) => ({ ...r, images: images.filter((i) => i.productId === r.id) }));
}

// ---------------------------------------------------------------------------
// Shop sub-categories -- §4.3's shop-owned half of the taxonomy, §8.2's
// "browse platform categories, create shop_sub_categories" step. Table
// existed since Sprint 2 (migrations/010); this is its first route.
// ---------------------------------------------------------------------------

const subCategorySchema = z.object({
  categoryId: z.string().uuid(),
  name: z.string().min(1).max(100),
  iconUrl: z.string().url().optional(),
  sortOrder: z.number().int().optional(),
});

catalogRoute.get("/shop/shops/:shopId/sub-categories", async (c) => {
  const authUser = c.get("user");
  const shopId = c.req.param("shopId");
  if (!(await getShopMembership(authUser.id, shopId))) {
    return c.json({ error: { code: "FORBIDDEN", message: "Not a member of this shop" } }, 403);
  }
  const rows = await db.select().from(shopSubCategories).where(eq(shopSubCategories.shopId, shopId)).orderBy(shopSubCategories.sortOrder);
  return c.json({ data: rows });
});

catalogRoute.post("/shop/shops/:shopId/sub-categories", zValidator("json", subCategorySchema), async (c) => {
  const authUser = c.get("user");
  const shopId = c.req.param("shopId");
  const body = c.req.valid("json");

  if (!(await isShopWriter(authUser.id, shopId))) {
    return c.json({ error: { code: "FORBIDDEN", message: "Only the shop owner or staff can edit the catalog" } }, 403);
  }

  const [created] = await db
    .insert(shopSubCategories)
    .values({ shopId, categoryId: body.categoryId, name: body.name, iconUrl: body.iconUrl, sortOrder: body.sortOrder ?? 0 })
    .returning();
  return c.json({ data: created }, 201);
});

const subCategoryUpdateSchema = subCategorySchema.omit({ categoryId: true }).partial().extend({ isActive: z.boolean().optional() });

catalogRoute.patch("/shop/shops/:shopId/sub-categories/:id", zValidator("json", subCategoryUpdateSchema), async (c) => {
  const authUser = c.get("user");
  const shopId = c.req.param("shopId");
  const id = c.req.param("id");
  const body = c.req.valid("json");

  if (!(await isShopWriter(authUser.id, shopId))) {
    return c.json({ error: { code: "FORBIDDEN", message: "Only the shop owner or staff can edit the catalog" } }, 403);
  }

  const [updated] = await db
    .update(shopSubCategories)
    .set({
      ...(body.name !== undefined ? { name: body.name } : {}),
      ...(body.iconUrl !== undefined ? { iconUrl: body.iconUrl } : {}),
      ...(body.sortOrder !== undefined ? { sortOrder: body.sortOrder } : {}),
      ...(body.isActive !== undefined ? { isActive: body.isActive } : {}),
    })
    .where(and(eq(shopSubCategories.id, id), eq(shopSubCategories.shopId, shopId)))
    .returning();

  if (!updated) return c.json({ error: { code: "SUB_CATEGORY_NOT_FOUND", message: "Sub-category not found" } }, 404);
  return c.json({ data: updated });
});

catalogRoute.delete("/shop/shops/:shopId/sub-categories/:id", async (c) => {
  const authUser = c.get("user");
  const shopId = c.req.param("shopId");
  const id = c.req.param("id");

  if (!(await isShopWriter(authUser.id, shopId))) {
    return c.json({ error: { code: "FORBIDDEN", message: "Only the shop owner or staff can edit the catalog" } }, 403);
  }

  // Products referencing this sub-category fall back to sub_category_id
  // NULL (migrations/017's ON DELETE SET NULL) rather than being blocked or
  // cascaded away -- deleting a rail entry shouldn't delete the products
  // under it.
  const [deleted] = await db.delete(shopSubCategories).where(and(eq(shopSubCategories.id, id), eq(shopSubCategories.shopId, shopId))).returning();
  if (!deleted) return c.json({ error: { code: "SUB_CATEGORY_NOT_FOUND", message: "Sub-category not found" } }, 404);
  return c.json({ data: deleted });
});

// ---------------------------------------------------------------------------
// Products -- §8.2's "add products/variants" step.
// ---------------------------------------------------------------------------

const createProductSchema = z.object({
  categoryId: z.string().uuid(),
  subCategoryId: z.string().uuid().optional(),
  name: z.string().min(1).max(150),
  description: z.string().max(2000).optional(),
  // Nullable, not just optional -- `null` is a real, distinct value here
  // ("not applicable," this migrations/017's own header comment's
  // reasoning), and the edit form needs to be able to send it explicitly to
  // clear a previously-set true/false back to "not applicable" (omitting the
  // key entirely, via `undefined`, would leave the existing value
  // untouched instead).
  isVeg: z.boolean().nullable().optional(),
  infoMessage: z.string().max(500).optional(),
});

// Shared by create and PATCH: if a sub-category is given, it must actually
// belong to this shop and sit under the same top-level category -- a
// cross-table invariant, not a CHECK constraint (§5.1: enforced at the one
// place that writes it, same judgment call shops.ts's supportsDelivery/
// deliveryMode check makes).
async function validateSubCategory(shopId: string, categoryId: string, subCategoryId: string | undefined) {
  if (!subCategoryId) return null;
  const [sub] = await db.select().from(shopSubCategories).where(eq(shopSubCategories.id, subCategoryId)).limit(1);
  if (!sub || sub.shopId !== shopId) {
    return { code: "SUB_CATEGORY_NOT_FOUND", message: "Sub-category not found for this shop" };
  }
  if (sub.categoryId !== categoryId) {
    return { code: "SUB_CATEGORY_CATEGORY_MISMATCH", message: "Sub-category belongs to a different top-level category" };
  }
  return null;
}

catalogRoute.get("/shop/shops/:shopId/products", async (c) => {
  const authUser = c.get("user");
  const shopId = c.req.param("shopId");
  if (!(await getShopMembership(authUser.id, shopId))) {
    return c.json({ error: { code: "FORBIDDEN", message: "Not a member of this shop" } }, 403);
  }
  const rows = await db.select().from(products).where(eq(products.shopId, shopId)).orderBy(products.createdAt);
  return c.json({ data: await withVariants(rows) });
});

catalogRoute.post("/shop/shops/:shopId/products", zValidator("json", createProductSchema), async (c) => {
  const authUser = c.get("user");
  const shopId = c.req.param("shopId");
  const body = c.req.valid("json");

  if (!(await isShopWriter(authUser.id, shopId))) {
    return c.json({ error: { code: "FORBIDDEN", message: "Only the shop owner or staff can edit the catalog" } }, 403);
  }

  const subCategoryError = await validateSubCategory(shopId, body.categoryId, body.subCategoryId);
  if (subCategoryError) return c.json({ error: subCategoryError }, 400);

  const [created] = await db
    .insert(products)
    .values({
      shopId,
      categoryId: body.categoryId,
      subCategoryId: body.subCategoryId,
      name: body.name,
      description: body.description,
      isVeg: body.isVeg,
      infoMessage: body.infoMessage,
    })
    .returning();

  return c.json({ data: { ...created, variants: [], images: [] } }, 201);
});

catalogRoute.get("/shop/shops/:shopId/products/:id", async (c) => {
  const authUser = c.get("user");
  const shopId = c.req.param("shopId");
  const id = c.req.param("id");

  if (!(await getShopMembership(authUser.id, shopId))) {
    return c.json({ error: { code: "FORBIDDEN", message: "Not a member of this shop" } }, 403);
  }

  const product = await getOwnedProduct(shopId, id);
  if (!product) return c.json({ error: { code: "PRODUCT_NOT_FOUND", message: "Product not found" } }, 404);

  const [variants, images] = await Promise.all([
    db.select().from(productVariants).where(eq(productVariants.productId, id)).orderBy(productVariants.sortOrder),
    db.select().from(productImages).where(eq(productImages.productId, id)).orderBy(productImages.sortOrder),
  ]);

  return c.json({ data: { ...product, variants, images } });
});

const updateProductSchema = createProductSchema.partial().extend({ isActive: z.boolean().optional() });

catalogRoute.patch("/shop/shops/:shopId/products/:id", zValidator("json", updateProductSchema), async (c) => {
  const authUser = c.get("user");
  const shopId = c.req.param("shopId");
  const id = c.req.param("id");
  const body = c.req.valid("json");

  if (!(await isShopWriter(authUser.id, shopId))) {
    return c.json({ error: { code: "FORBIDDEN", message: "Only the shop owner or staff can edit the catalog" } }, 403);
  }

  const existing = await getOwnedProduct(shopId, id);
  if (!existing) return c.json({ error: { code: "PRODUCT_NOT_FOUND", message: "Product not found" } }, 404);

  if (body.subCategoryId !== undefined) {
    const subCategoryError = await validateSubCategory(shopId, body.categoryId ?? existing.categoryId, body.subCategoryId);
    if (subCategoryError) return c.json({ error: subCategoryError }, 400);
  }

  const [updated] = await db
    .update(products)
    .set({
      ...(body.categoryId !== undefined ? { categoryId: body.categoryId } : {}),
      ...(body.subCategoryId !== undefined ? { subCategoryId: body.subCategoryId } : {}),
      ...(body.name !== undefined ? { name: body.name } : {}),
      ...(body.description !== undefined ? { description: body.description } : {}),
      ...(body.isVeg !== undefined ? { isVeg: body.isVeg } : {}),
      ...(body.infoMessage !== undefined ? { infoMessage: body.infoMessage } : {}),
      ...(body.isActive !== undefined ? { isActive: body.isActive } : {}),
      updatedAt: new Date(),
    })
    .where(eq(products.id, id))
    .returning();

  return c.json({ data: updated });
});

catalogRoute.delete("/shop/shops/:shopId/products/:id", async (c) => {
  const authUser = c.get("user");
  const shopId = c.req.param("shopId");
  const id = c.req.param("id");

  if (!(await isShopWriter(authUser.id, shopId))) {
    return c.json({ error: { code: "FORBIDDEN", message: "Only the shop owner or staff can edit the catalog" } }, 403);
  }

  const existing = await getOwnedProduct(shopId, id);
  if (!existing) return c.json({ error: { code: "PRODUCT_NOT_FOUND", message: "Product not found" } }, 404);

  // Hard delete -- variants/images cascade (migrations/018, 019). No orders
  // reference product_variants yet (Sprint 6+), so there's no "can't delete,
  // it's been sold" invariant to worry about this sprint; revisit once
  // order_items exists.
  await db.delete(products).where(eq(products.id, id));
  return c.json({ data: { id } });
});

// ---------------------------------------------------------------------------
// Product variants
// ---------------------------------------------------------------------------

const createVariantSchema = z.object({
  unitValue: z.number().positive(),
  unitLabel: z.string().min(1).max(20),
  sku: z.string().max(50).optional(),
  price: z.number().int().positive(),
  mrp: z.number().int().positive().optional(),
  stockQty: z.number().int().min(0).optional(),
  stockStatus: z.enum(["in_stock", "low_stock", "out_of_stock"]).optional(),
  sortOrder: z.number().int().optional(),
});

catalogRoute.post(
  "/shop/shops/:shopId/products/:productId/variants",
  zValidator("json", createVariantSchema),
  async (c) => {
    const authUser = c.get("user");
    const shopId = c.req.param("shopId");
    const productId = c.req.param("productId");
    const body = c.req.valid("json");

    if (!(await isShopWriter(authUser.id, shopId))) {
      return c.json({ error: { code: "FORBIDDEN", message: "Only the shop owner or staff can edit the catalog" } }, 403);
    }
    if (!(await getOwnedProduct(shopId, productId))) {
      return c.json({ error: { code: "PRODUCT_NOT_FOUND", message: "Product not found" } }, 404);
    }
    if (body.mrp !== undefined && body.mrp < body.price) {
      return c.json({ error: { code: "MRP_BELOW_PRICE", message: "MRP cannot be less than the selling price" } }, 400);
    }

    const [created] = await db
      .insert(productVariants)
      .values({
        productId,
        unitValue: String(body.unitValue),
        unitLabel: body.unitLabel,
        sku: body.sku,
        price: body.price,
        mrp: body.mrp,
        stockQty: body.stockQty ?? 0,
        stockStatus: body.stockStatus ?? "in_stock",
        sortOrder: body.sortOrder ?? 0,
      })
      .returning();

    return c.json({ data: created }, 201);
  },
);

const updateVariantSchema = createVariantSchema.partial().extend({ isActive: z.boolean().optional() });

catalogRoute.patch(
  "/shop/shops/:shopId/products/:productId/variants/:id",
  zValidator("json", updateVariantSchema),
  async (c) => {
    const authUser = c.get("user");
    const shopId = c.req.param("shopId");
    const productId = c.req.param("productId");
    const id = c.req.param("id");
    const body = c.req.valid("json");

    if (!(await isShopWriter(authUser.id, shopId))) {
      return c.json({ error: { code: "FORBIDDEN", message: "Only the shop owner or staff can edit the catalog" } }, 403);
    }
    if (!(await getOwnedProduct(shopId, productId))) {
      return c.json({ error: { code: "PRODUCT_NOT_FOUND", message: "Product not found" } }, 404);
    }

    const [existing] = await db.select().from(productVariants).where(and(eq(productVariants.id, id), eq(productVariants.productId, productId))).limit(1);
    if (!existing) return c.json({ error: { code: "VARIANT_NOT_FOUND", message: "Variant not found" } }, 404);

    const nextPrice = body.price ?? existing.price;
    const nextMrp = body.mrp !== undefined ? body.mrp : existing.mrp;
    if (nextMrp !== null && nextMrp !== undefined && nextMrp < nextPrice) {
      return c.json({ error: { code: "MRP_BELOW_PRICE", message: "MRP cannot be less than the selling price" } }, 400);
    }

    const [updated] = await db
      .update(productVariants)
      .set({
        ...(body.unitValue !== undefined ? { unitValue: String(body.unitValue) } : {}),
        ...(body.unitLabel !== undefined ? { unitLabel: body.unitLabel } : {}),
        ...(body.sku !== undefined ? { sku: body.sku } : {}),
        ...(body.price !== undefined ? { price: body.price } : {}),
        ...(body.mrp !== undefined ? { mrp: body.mrp } : {}),
        ...(body.stockQty !== undefined ? { stockQty: body.stockQty } : {}),
        ...(body.stockStatus !== undefined ? { stockStatus: body.stockStatus } : {}),
        ...(body.sortOrder !== undefined ? { sortOrder: body.sortOrder } : {}),
        ...(body.isActive !== undefined ? { isActive: body.isActive } : {}),
        updatedAt: new Date(),
      })
      .where(eq(productVariants.id, id))
      .returning();

    return c.json({ data: updated });
  },
);

catalogRoute.delete("/shop/shops/:shopId/products/:productId/variants/:id", async (c) => {
  const authUser = c.get("user");
  const shopId = c.req.param("shopId");
  const productId = c.req.param("productId");
  const id = c.req.param("id");

  if (!(await isShopWriter(authUser.id, shopId))) {
    return c.json({ error: { code: "FORBIDDEN", message: "Only the shop owner or staff can edit the catalog" } }, 403);
  }
  if (!(await getOwnedProduct(shopId, productId))) {
    return c.json({ error: { code: "PRODUCT_NOT_FOUND", message: "Product not found" } }, 404);
  }

  const [deleted] = await db
    .delete(productVariants)
    .where(and(eq(productVariants.id, id), eq(productVariants.productId, productId)))
    .returning();
  if (!deleted) return c.json({ error: { code: "VARIANT_NOT_FOUND", message: "Variant not found" } }, 404);
  return c.json({ data: deleted });
});

// ---------------------------------------------------------------------------
// Product images -- the row-recording half of the upload flow; the image
// bytes themselves go straight from proximity_web's browser client to the
// `product-images` Storage bucket (migrations/020), never through this Edge
// Function, same "Storage is a separate, already-authenticated path"
// precedent as the rider KYC upload (Sprint 2).
// ---------------------------------------------------------------------------

const createImageSchema = z.object({ imageUrl: z.string().url(), sortOrder: z.number().int().optional() });

catalogRoute.post(
  "/shop/shops/:shopId/products/:productId/images",
  zValidator("json", createImageSchema),
  async (c) => {
    const authUser = c.get("user");
    const shopId = c.req.param("shopId");
    const productId = c.req.param("productId");
    const body = c.req.valid("json");

    if (!(await isShopWriter(authUser.id, shopId))) {
      return c.json({ error: { code: "FORBIDDEN", message: "Only the shop owner or staff can edit the catalog" } }, 403);
    }
    if (!(await getOwnedProduct(shopId, productId))) {
      return c.json({ error: { code: "PRODUCT_NOT_FOUND", message: "Product not found" } }, 404);
    }

    const [created] = await db.insert(productImages).values({ productId, imageUrl: body.imageUrl, sortOrder: body.sortOrder ?? 0 }).returning();
    return c.json({ data: created }, 201);
  },
);

catalogRoute.delete("/shop/shops/:shopId/products/:productId/images/:id", async (c) => {
  const authUser = c.get("user");
  const shopId = c.req.param("shopId");
  const productId = c.req.param("productId");
  const id = c.req.param("id");

  if (!(await isShopWriter(authUser.id, shopId))) {
    return c.json({ error: { code: "FORBIDDEN", message: "Only the shop owner or staff can edit the catalog" } }, 403);
  }
  if (!(await getOwnedProduct(shopId, productId))) {
    return c.json({ error: { code: "PRODUCT_NOT_FOUND", message: "Product not found" } }, 404);
  }

  // Only the row is deleted here, not the underlying Storage object -- a
  // stray file left in the bucket is harmless (it's keyed off the shop's own
  // folder and never linked from anywhere once its row is gone); deleting it
  // too would mean this route also needs Storage-admin credentials, not
  // worth it for this sprint's scope.
  const [deleted] = await db.delete(productImages).where(and(eq(productImages.id, id), eq(productImages.productId, productId))).returning();
  if (!deleted) return c.json({ error: { code: "IMAGE_NOT_FOUND", message: "Image not found" } }, 404);
  return c.json({ data: deleted });
});

// ---------------------------------------------------------------------------
// Buyer-facing public read API -- this sprint's exit criteria: "a shopkeeper
// can list a real product with variants and see it queryable via the
// buyer-facing read API." No auth, filtered to approved shops/active rows
// (mirrors the RLS backstop in migrations/017-019, per §5.1 not relied on
// alone). Real browse/search UX (filtering, sorting, pagination) is
// Sprint 4+'s job -- this is deliberately the minimum that makes the exit
// criteria true, not the finished buyer API.
// ---------------------------------------------------------------------------

// Sprint 5: optional subCategoryId narrows to one shop-detail rail entry
// (§7.1's vertical category rail, scoped to that shop's own
// shop_sub_categories, §4.3) -- omitted entirely shows the shop's full
// catalog, same "All" convention selectedCategoryIdProvider already
// established on Home (Sprint 4).
const shopProductsQuerySchema = z.object({ subCategoryId: z.string().uuid().optional() });

catalogRoute.get("/shops/:shopId/products", zValidator("query", shopProductsQuerySchema), async (c) => {
  const shopId = c.req.param("shopId");
  const { subCategoryId } = c.req.valid("query");

  const [shop] = await db.select({ id: shops.id }).from(shops).where(and(eq(shops.id, shopId), eq(shops.status, "approved"))).limit(1);
  if (!shop) return c.json({ error: { code: "SHOP_NOT_FOUND", message: "Shop not found" } }, 404);

  const rows = await db
    .select()
    .from(products)
    .where(
      and(
        eq(products.shopId, shopId),
        eq(products.isActive, true),
        subCategoryId ? eq(products.subCategoryId, subCategoryId) : undefined,
      ),
    )
    .orderBy(products.createdAt);
  const withAllVariants = await withVariants(rows);
  const withAllImages = await withImages(withAllVariants);
  // Public listing only ever shows active variants -- an inactive
  // (discontinued) one shouldn't appear even nested under a visible product.
  const data = withAllImages.map((p) => ({ ...p, variants: p.variants.filter((v) => v.isActive) }));
  return c.json({ data });
});

catalogRoute.get("/products/:id", async (c) => {
  const id = c.req.param("id");

  const [product] = await db.select().from(products).where(and(eq(products.id, id), eq(products.isActive, true))).limit(1);
  if (!product) return c.json({ error: { code: "PRODUCT_NOT_FOUND", message: "Product not found" } }, 404);

  // Sprint 5: includes name/logoUrl, not just an existence check -- the PDP
  // (§7.1) can be reached from places with no shop already loaded (the
  // wishlist screen, in particular), so it carries just enough shop context
  // to render a "from <shop>" line and a link back, without a second
  // request for something this callsite already has in hand.
  const [shop] = await db
    .select({ id: shops.id, name: shops.name, logoUrl: shops.logoUrl })
    .from(shops)
    .where(and(eq(shops.id, product.shopId), eq(shops.status, "approved")))
    .limit(1);
  if (!shop) return c.json({ error: { code: "PRODUCT_NOT_FOUND", message: "Product not found" } }, 404);

  const [variants, images] = await Promise.all([
    db.select().from(productVariants).where(and(eq(productVariants.productId, id), eq(productVariants.isActive, true))).orderBy(productVariants.sortOrder),
    db.select().from(productImages).where(eq(productImages.productId, id)).orderBy(productImages.sortOrder),
  ]);

  return c.json({ data: { ...product, variants, images, shop } });
});

catalogRoute.get("/shops/:shopId/sub-categories", async (c) => {
  const shopId = c.req.param("shopId");

  const [shop] = await db.select({ id: shops.id }).from(shops).where(and(eq(shops.id, shopId), eq(shops.status, "approved"))).limit(1);
  if (!shop) return c.json({ error: { code: "SHOP_NOT_FOUND", message: "Shop not found" } }, 404);

  const rows = await db
    .select()
    .from(shopSubCategories)
    .where(and(eq(shopSubCategories.shopId, shopId), eq(shopSubCategories.isActive, true)))
    .orderBy(shopSubCategories.sortOrder);
  return c.json({ data: rows });
});
