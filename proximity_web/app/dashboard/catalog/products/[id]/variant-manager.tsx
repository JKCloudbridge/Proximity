"use client";

import { useState } from "react";
import { toast } from "sonner";
import { apiFetchClient, ApiError } from "@/lib/api-client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { Card, CardContent } from "@/components/ui/card";
import type { ProductVariant, StockStatus } from "@/lib/types";

const STOCK_LABELS: Record<StockStatus, string> = { in_stock: "In stock", low_stock: "Low stock", out_of_stock: "Out of stock" };

// paise <-> rupee-string conversion -- every price this form sends/receives
// is paise (§1.7's convention), but a shopkeeper types "45.50", not "4550".
function toPaise(rupees: string): number {
  return Math.round(Number(rupees) * 100);
}
function toRupees(paise: number): string {
  return (paise / 100).toFixed(2);
}

export function VariantManager({
  shopId,
  productId,
  variants,
  onChange,
}: {
  shopId: string;
  productId: string;
  variants: ProductVariant[];
  onChange: (variants: ProductVariant[]) => void;
}) {
  const base = `/v1/shop/shops/${shopId}/products/${productId}/variants`;

  const [unitValue, setUnitValue] = useState("1");
  const [unitLabel, setUnitLabel] = useState("");
  const [price, setPrice] = useState("");
  const [mrp, setMrp] = useState("");
  const [stockQty, setStockQty] = useState("0");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleAdd(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    const priceValue = toPaise(price);
    if (!unitLabel.trim() || !Number(unitValue) || !priceValue) {
      setError("Enter a unit, unit value, and price");
      return;
    }

    setSubmitting(true);
    try {
      const { data } = await apiFetchClient<{ data: ProductVariant }>(base, {
        method: "POST",
        body: JSON.stringify({
          unitValue: Number(unitValue),
          unitLabel: unitLabel.trim(),
          price: priceValue,
          mrp: mrp ? toPaise(mrp) : undefined,
          stockQty: Number(stockQty) || 0,
        }),
      });
      onChange([...variants, data]);
      toast.success("Variant added");
      setUnitValue("1");
      setUnitLabel("");
      setPrice("");
      setMrp("");
      setStockQty("0");
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Could not add variant");
    } finally {
      setSubmitting(false);
    }
  }

  async function updateVariant(id: string, patch: Partial<Pick<ProductVariant, "stockStatus" | "isActive">>) {
    try {
      const { data } = await apiFetchClient<{ data: ProductVariant }>(`${base}/${id}`, {
        method: "PATCH",
        body: JSON.stringify(patch),
      });
      onChange(variants.map((v) => (v.id === id ? data : v)));
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Could not update variant");
    }
  }

  async function deleteVariant(id: string) {
    try {
      await apiFetchClient(`${base}/${id}`, { method: "DELETE" });
      onChange(variants.filter((v) => v.id !== id));
      toast.success("Variant removed");
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Could not remove variant");
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardContent className="pt-6">
          <form onSubmit={handleAdd} className="grid gap-4 sm:grid-cols-[6rem_6rem_7rem_7rem_6rem_auto] sm:items-end">
            <div className="flex flex-col gap-2">
              <Label htmlFor="unitValue">Value</Label>
              <Input id="unitValue" type="number" step="any" min="0" value={unitValue} onChange={(e) => setUnitValue(e.target.value)} />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="unitLabel">Unit</Label>
              <Input id="unitLabel" placeholder="g, kg, ml, pcs" required value={unitLabel} onChange={(e) => setUnitLabel(e.target.value)} />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="price">Price (₹)</Label>
              <Input id="price" type="number" step="0.01" min="0" required value={price} onChange={(e) => setPrice(e.target.value)} />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="mrp">MRP (₹, optional)</Label>
              <Input id="mrp" type="number" step="0.01" min="0" value={mrp} onChange={(e) => setMrp(e.target.value)} />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="stockQty">Stock qty</Label>
              <Input id="stockQty" type="number" min="0" value={stockQty} onChange={(e) => setStockQty(e.target.value)} />
            </div>
            <Button type="submit" disabled={submitting}>
              Add variant
            </Button>
          </form>
          {error && <p className="mt-2 text-sm text-destructive">{error}</p>}
        </CardContent>
      </Card>

      {variants.length === 0 ? (
        <p className="text-sm text-muted-foreground">No variants yet.</p>
      ) : (
        <div className="overflow-x-auto rounded-lg border">
          <table className="w-full text-sm">
            <thead className="bg-muted text-left text-muted-foreground">
              <tr>
                <th className="px-4 py-2 font-medium">Pack</th>
                <th className="px-4 py-2 font-medium">Price</th>
                <th className="px-4 py-2 font-medium">Stock qty</th>
                <th className="px-4 py-2 font-medium">Stock status</th>
                <th className="px-4 py-2 font-medium">Active</th>
                <th className="px-4 py-2 font-medium" />
              </tr>
            </thead>
            <tbody>
              {variants.map((v) => (
                <tr key={v.id} className="border-t">
                  <td className="px-4 py-2 font-medium">
                    {v.unitValue} {v.unitLabel}
                  </td>
                  <td className="px-4 py-2">
                    ₹{toRupees(v.price)}
                    {v.mrp && v.mrp > v.price && <span className="ml-1 text-xs text-muted-foreground line-through">₹{toRupees(v.mrp)}</span>}
                  </td>
                  <td className="px-4 py-2">{v.stockQty}</td>
                  <td className="px-4 py-2">
                    <Select
                      className="h-8 w-36"
                      value={v.stockStatus}
                      onChange={(e) => updateVariant(v.id, { stockStatus: e.target.value as StockStatus })}
                    >
                      {(Object.keys(STOCK_LABELS) as StockStatus[]).map((s) => (
                        <option key={s} value={s}>
                          {STOCK_LABELS[s]}
                        </option>
                      ))}
                    </Select>
                  </td>
                  <td className="px-4 py-2">
                    <Button size="sm" variant="outline" onClick={() => updateVariant(v.id, { isActive: !v.isActive })}>
                      {v.isActive ? "Active" : "Inactive"}
                    </Button>
                  </td>
                  <td className="px-4 py-2 text-right">
                    <Button size="sm" variant="destructive" onClick={() => deleteVariant(v.id)}>
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
