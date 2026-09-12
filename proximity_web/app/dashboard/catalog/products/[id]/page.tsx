import { notFound } from "next/navigation";
import { requireShop } from "@/lib/auth";
import { apiFetch, ApiError } from "@/lib/api";
import { ProductDetailClient } from "./product-detail-client";
import type { Category, Product, ShopSubCategory } from "@/lib/types";

export default async function ProductDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { shop } = await requireShop();

  let product: Product;
  try {
    ({ data: product } = await apiFetch<{ data: Product }>(`/v1/shop/shops/${shop.id}/products/${id}`));
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) notFound();
    throw err;
  }

  const [{ data: categories }, { data: subCategories }] = await Promise.all([
    apiFetch<{ data: Category[] }>("/v1/categories"),
    apiFetch<{ data: ShopSubCategory[] }>(`/v1/shop/shops/${shop.id}/sub-categories`),
  ]);

  return (
    <div className="mx-auto max-w-2xl">
      <h1 className="mb-6 text-xl font-semibold">{product.name}</h1>
      <ProductDetailClient shopId={shop.id} categories={categories} subCategories={subCategories} initialProduct={product} />
    </div>
  );
}
