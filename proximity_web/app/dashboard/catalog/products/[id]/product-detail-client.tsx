"use client";

import { useState } from "react";
import { ProductForm } from "../product-form";
import { VariantManager } from "./variant-manager";
import { ImageManager } from "./image-manager";
import type { Category, Product, ShopSubCategory } from "@/lib/types";

export function ProductDetailClient({
  shopId,
  categories,
  subCategories,
  initialProduct,
}: {
  shopId: string;
  categories: Category[];
  subCategories: ShopSubCategory[];
  initialProduct: Product;
}) {
  const [product, setProduct] = useState(initialProduct);

  return (
    <div className="flex flex-col gap-8">
      <ProductForm shopId={shopId} categories={categories} subCategories={subCategories} product={product} onSaved={setProduct} />

      <div>
        <h2 className="mb-3 text-lg font-semibold">Variants</h2>
        <p className="mb-3 text-sm text-muted-foreground">
          At least one variant is required before buyers can see this product -- each is a distinct pack size/unit with its own price
          and stock.
        </p>
        <VariantManager
          shopId={shopId}
          productId={product.id}
          variants={product.variants}
          onChange={(variants) => setProduct((p) => ({ ...p, variants }))}
        />
      </div>

      <div>
        <h2 className="mb-3 text-lg font-semibold">Photos</h2>
        <ImageManager
          shopId={shopId}
          productId={product.id}
          images={product.images ?? []}
          onChange={(images) => setProduct((p) => ({ ...p, images }))}
        />
      </div>
    </div>
  );
}
