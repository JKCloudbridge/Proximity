"use client";

import { useState } from "react";
import Link from "next/link";
import { toast } from "sonner";
import { apiFetchClient, ApiError } from "@/lib/api-client";
import { Button, buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { cn } from "@/lib/utils";
import type { Category, Product, ShopSubCategory } from "@/lib/types";

type Tab = "products" | "sub-categories";

export function CatalogClient({
  shopId,
  categories,
  initialSubCategories,
  initialProducts,
}: {
  shopId: string;
  categories: Category[];
  initialSubCategories: ShopSubCategory[];
  initialProducts: Product[];
}) {
  const [tab, setTab] = useState<Tab>("products");
  const [products] = useState(initialProducts);
  const [subCategories, setSubCategories] = useState(initialSubCategories);

  const categoryName = (id: string) => categories.find((c) => c.id === id)?.name ?? "Unknown category";

  async function addSubCategory(form: { categoryId: string; name: string; iconUrl: string }) {
    try {
      const { data } = await apiFetchClient<{ data: ShopSubCategory }>(`/v1/shop/shops/${shopId}/sub-categories`, {
        method: "POST",
        body: JSON.stringify({ categoryId: form.categoryId, name: form.name, iconUrl: form.iconUrl || undefined }),
      });
      setSubCategories((prev) => [...prev, data]);
      toast.success("Sub-category added");
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Could not add sub-category");
    }
  }

  async function deleteSubCategory(id: string) {
    try {
      await apiFetchClient(`/v1/shop/shops/${shopId}/sub-categories/${id}`, { method: "DELETE" });
      setSubCategories((prev) => prev.filter((s) => s.id !== id));
      toast.success("Sub-category removed");
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Could not remove sub-category");
    }
  }

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-semibold">Catalog</h1>
        {tab === "products" && (
          <Link href="/dashboard/catalog/products/new" className={buttonVariants({ size: "sm" })}>
            Add product
          </Link>
        )}
      </div>

      <div className="mb-4 flex gap-1 border-b">
        {(["products", "sub-categories"] as Tab[]).map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={cn(
              "border-b-2 border-transparent px-3 py-2 text-sm font-medium text-muted-foreground",
              tab === t && "border-primary text-foreground",
            )}
          >
            {t === "products" ? "Products" : "Sub-categories"}
          </button>
        ))}
      </div>

      {tab === "products" ? (
        <ProductsTable products={products} categoryName={categoryName} />
      ) : (
        <SubCategoriesPanel categories={categories} subCategories={subCategories} onAdd={addSubCategory} onDelete={deleteSubCategory} />
      )}
    </div>
  );
}

function priceRange(product: Product) {
  const active = product.variants.filter((v) => v.isActive);
  if (active.length === 0) return "No variants yet";
  const prices = active.map((v) => v.price);
  const min = Math.min(...prices);
  const max = Math.max(...prices);
  const fmt = (paise: number) => `₹${(paise / 100).toFixed(2)}`;
  return min === max ? fmt(min) : `${fmt(min)} – ${fmt(max)}`;
}

function ProductsTable({ products, categoryName }: { products: Product[]; categoryName: (id: string) => string }) {
  if (products.length === 0) {
    return <p className="text-sm text-muted-foreground">No products yet. Add your first one to get started.</p>;
  }

  return (
    <div className="overflow-x-auto rounded-lg border">
      <table className="w-full text-sm">
        <thead className="bg-muted text-left text-muted-foreground">
          <tr>
            <th className="px-4 py-2 font-medium">Product</th>
            <th className="px-4 py-2 font-medium">Category</th>
            <th className="px-4 py-2 font-medium">Variants</th>
            <th className="px-4 py-2 font-medium">Price</th>
            <th className="px-4 py-2 font-medium">Status</th>
            <th className="px-4 py-2 font-medium" />
          </tr>
        </thead>
        <tbody>
          {products.map((product) => (
            <tr key={product.id} className="border-t">
              <td className="px-4 py-2 font-medium">{product.name}</td>
              <td className="px-4 py-2">{categoryName(product.categoryId)}</td>
              <td className="px-4 py-2">{product.variants.length}</td>
              <td className="px-4 py-2">{priceRange(product)}</td>
              <td className="px-4 py-2">
                <Badge variant={product.isActive ? "default" : "secondary"}>{product.isActive ? "Active" : "Inactive"}</Badge>
              </td>
              <td className="px-4 py-2 text-right">
                <Link href={`/dashboard/catalog/products/${product.id}`} className={buttonVariants({ size: "sm", variant: "outline" })}>
                  Edit
                </Link>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function SubCategoriesPanel({
  categories,
  subCategories,
  onAdd,
  onDelete,
}: {
  categories: Category[];
  subCategories: ShopSubCategory[];
  onAdd: (form: { categoryId: string; name: string; iconUrl: string }) => void;
  onDelete: (id: string) => void;
}) {
  const [categoryId, setCategoryId] = useState(categories[0]?.id ?? "");
  const [name, setName] = useState("");
  const [iconUrl, setIconUrl] = useState("");
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!categoryId || !name.trim()) return;
    setSubmitting(true);
    await onAdd({ categoryId, name: name.trim(), iconUrl });
    setSubmitting(false);
    setName("");
    setIconUrl("");
  }

  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardContent className="pt-6">
          <form onSubmit={handleSubmit} className="grid gap-4 sm:grid-cols-[1fr_1fr_1fr_auto] sm:items-end">
            <div className="flex flex-col gap-2">
              <Label htmlFor="subCatCategory">Platform category</Label>
              <Select id="subCatCategory" value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
                {categories.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.icon ? `${c.icon} ` : ""}
                    {c.name}
                  </option>
                ))}
              </Select>
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="subCatName">Rail entry name</Label>
              <Input id="subCatName" required placeholder="e.g. Milk" value={name} onChange={(e) => setName(e.target.value)} />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="subCatIcon">Icon URL (optional)</Label>
              <Input id="subCatIcon" value={iconUrl} onChange={(e) => setIconUrl(e.target.value)} />
            </div>
            <Button type="submit" disabled={submitting || !categoryId}>
              Add
            </Button>
          </form>
        </CardContent>
      </Card>

      {subCategories.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          No sub-categories yet -- these power your shop&apos;s category rail once buyers can browse it (a later sprint), but you can
          set them up now and use them to organize products today.
        </p>
      ) : (
        <div className="overflow-x-auto rounded-lg border">
          <table className="w-full text-sm">
            <thead className="bg-muted text-left text-muted-foreground">
              <tr>
                <th className="px-4 py-2 font-medium">Name</th>
                <th className="px-4 py-2 font-medium">Platform category</th>
                <th className="px-4 py-2 font-medium" />
              </tr>
            </thead>
            <tbody>
              {subCategories.map((sc) => (
                <tr key={sc.id} className="border-t">
                  <td className="px-4 py-2 font-medium">{sc.name}</td>
                  <td className="px-4 py-2">{categories.find((c) => c.id === sc.categoryId)?.name ?? "Unknown"}</td>
                  <td className="px-4 py-2 text-right">
                    <Button size="sm" variant="destructive" onClick={() => onDelete(sc.id)}>
                      Remove
                    </Button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
