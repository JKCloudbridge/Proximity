import { requireShop } from "@/lib/auth";
import { apiFetch } from "@/lib/api";
import { CatalogClient } from "./catalog-client";
import type { Category, Product, ShopSubCategory } from "@/lib/types";

// §8.2: "browse platform categories, create shop_sub_categories, add
// products/variants." Unlike dashboard/page.tsx, this page does NOT gate on
// shop.status === 'approved' -- a shop still in 'pending' can build out its
// catalog while it waits on admin review, so it's ready the moment approval
// lands rather than blocked on it. (The buyer-facing read API in
// routes/catalog.ts still only ever surfaces an approved shop's products,
// so nothing here leaks a pending shop's catalog to buyers early.)
export default async function CatalogPage() {
  const { shop } = await requireShop();

  const [{ data: categories }, { data: subCategories }, { data: products }] = await Promise.all([
    apiFetch<{ data: Category[] }>("/v1/categories"),
    apiFetch<{ data: ShopSubCategory[] }>(`/v1/shop/shops/${shop.id}/sub-categories`),
    apiFetch<{ data: Product[] }>(`/v1/shop/shops/${shop.id}/products`),
  ]);

  return (
    <div className="mx-auto max-w-4xl">
      <CatalogClient shopId={shop.id} categories={categories} initialSubCategories={subCategories} initialProducts={products} />
    </div>
  );
}
