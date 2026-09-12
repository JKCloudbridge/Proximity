import { requireShop } from "@/lib/auth";
import { apiFetch } from "@/lib/api";
import { ProductForm } from "../product-form";
import type { Category, ShopSubCategory } from "@/lib/types";

export default async function NewProductPage() {
  const { shop } = await requireShop();

  const [{ data: categories }, { data: subCategories }] = await Promise.all([
    apiFetch<{ data: Category[] }>("/v1/categories"),
    apiFetch<{ data: ShopSubCategory[] }>(`/v1/shop/shops/${shop.id}/sub-categories`),
  ]);

  return (
    <div className="mx-auto max-w-2xl">
      <h1 className="mb-6 text-xl font-semibold">Add a product</h1>
      <ProductForm shopId={shop.id} categories={categories} subCategories={subCategories} />
    </div>
  );
}
