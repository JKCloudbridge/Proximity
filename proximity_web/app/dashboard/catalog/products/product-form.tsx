"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { apiFetchClient, ApiError } from "@/lib/api-client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { Card, CardContent } from "@/components/ui/card";
import type { Category, Product, ShopSubCategory } from "@/lib/types";

const VEG_OPTIONS = [
  { value: "", label: "Not applicable (non-food item)" },
  { value: "true", label: "Veg" },
  { value: "false", label: "Non-veg" },
];

// Shared between the create page (no `product` prop) and the edit page
// (Sprint 3's product detail screen) -- same shape as most of this
// codebase's forms not splitting create/edit into separate components when
// the fields are identical (e.g. ShopCreationForm handles onboarding only,
// but the *pattern* -- controlled inputs, one submit handler branching on
// mode -- is the same one used here).
export function ProductForm({
  shopId,
  categories,
  subCategories,
  product,
  onSaved,
}: {
  shopId: string;
  categories: Category[];
  subCategories: ShopSubCategory[];
  product?: Product;
  onSaved?: (product: Product) => void;
}) {
  const router = useRouter();
  const isEdit = !!product;

  const [categoryId, setCategoryId] = useState(product?.categoryId ?? categories[0]?.id ?? "");
  const [subCategoryId, setSubCategoryId] = useState(product?.subCategoryId ?? "");
  const [name, setName] = useState(product?.name ?? "");
  const [description, setDescription] = useState(product?.description ?? "");
  const [isVeg, setIsVeg] = useState(product?.isVeg === true ? "true" : product?.isVeg === false ? "false" : "");
  const [infoMessage, setInfoMessage] = useState(product?.infoMessage ?? "");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Only offer sub-categories that sit under the currently-chosen category
  // (migrations/017's own invariant, enforced again server-side in
  // routes/catalog.ts's validateSubCategory) -- avoids the user picking a
  // combination the API will just reject.
  const availableSubCategories = useMemo(() => subCategories.filter((s) => s.categoryId === categoryId), [subCategories, categoryId]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);

    const body = {
      categoryId,
      subCategoryId: subCategoryId || undefined,
      name,
      description: description || undefined,
      // Explicit `null`, not `undefined`, when "not applicable" is chosen --
      // an omitted key leaves an existing value untouched on PATCH
      // (routes/catalog.ts's updateProductSchema), which isn't what
      // re-selecting "not applicable" in the edit form should do.
      isVeg: isVeg === "" ? null : isVeg === "true",
      infoMessage: infoMessage || undefined,
    };

    try {
      if (isEdit) {
        const { data } = await apiFetchClient<{ data: Product }>(`/v1/shop/shops/${shopId}/products/${product.id}`, {
          method: "PATCH",
          body: JSON.stringify(body),
        });
        toast.success("Product details saved");
        onSaved?.({ ...product, ...data });
      } else {
        const { data } = await apiFetchClient<{ data: Product }>(`/v1/shop/shops/${shopId}/products`, {
          method: "POST",
          body: JSON.stringify(body),
        });
        toast.success("Product created -- now add at least one variant");
        router.push(`/dashboard/catalog/products/${data.id}`);
        router.refresh();
      }
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Could not save product");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Card>
      <CardContent className="pt-6">
        <form onSubmit={handleSubmit} className="flex flex-col gap-4">
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="flex flex-col gap-2">
              <Label htmlFor="categoryId">Platform category</Label>
              <Select
                id="categoryId"
                value={categoryId}
                onChange={(e) => {
                  setCategoryId(e.target.value);
                  setSubCategoryId("");
                }}
              >
                {categories.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.icon ? `${c.icon} ` : ""}
                    {c.name}
                  </option>
                ))}
              </Select>
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="subCategoryId">Your sub-category (optional)</Label>
              <Select id="subCategoryId" value={subCategoryId} onChange={(e) => setSubCategoryId(e.target.value)}>
                <option value="">None</option>
                {availableSubCategories.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))}
              </Select>
            </div>
          </div>

          <div className="flex flex-col gap-2">
            <Label htmlFor="name">Product name</Label>
            <Input id="name" required value={name} onChange={(e) => setName(e.target.value)} />
          </div>

          <div className="flex flex-col gap-2">
            <Label htmlFor="description">Description (optional)</Label>
            <Textarea id="description" value={description} onChange={(e) => setDescription(e.target.value)} />
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            <div className="flex flex-col gap-2">
              <Label htmlFor="isVeg">Veg / non-veg (FSSAI labelling)</Label>
              <Select id="isVeg" value={isVeg} onChange={(e) => setIsVeg(e.target.value)}>
                {VEG_OPTIONS.map((o) => (
                  <option key={o.value} value={o.value}>
                    {o.label}
                  </option>
                ))}
              </Select>
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="infoMessage">Note to buyers (optional)</Label>
              <Input id="infoMessage" placeholder="e.g. Contains nuts" value={infoMessage} onChange={(e) => setInfoMessage(e.target.value)} />
            </div>
          </div>

          {error && <p className="text-sm text-destructive">{error}</p>}
          <Button type="submit" disabled={submitting} className="self-start">
            {submitting ? "Saving..." : isEdit ? "Save changes" : "Create product"}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
