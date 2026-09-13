"use client";

import { useState } from "react";
import { toast } from "sonner";
import { apiFetchClient, ApiError } from "@/lib/api-client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import type { Discount, DiscountType } from "@/lib/types";

const TYPE_LABEL: Record<DiscountType, string> = {
  percent: "% off subtotal",
  flat: "₹ off subtotal",
  free_shipping: "Free delivery",
};

type DraftDiscount = {
  code: string;
  name: string;
  type: DiscountType;
  value: string;
  minOrderValue: string;
  maxUses: string;
};

const EMPTY_DRAFT: DraftDiscount = { code: "", name: "", type: "percent", value: "10", minOrderValue: "0", maxUses: "" };

export function DiscountsClient({ initialDiscounts }: { initialDiscounts: Discount[] }) {
  const [discounts, setDiscounts] = useState(initialDiscounts);
  const [draft, setDraft] = useState<DraftDiscount>(EMPTY_DRAFT);
  const [creating, setCreating] = useState(false);
  const [actingOn, setActingOn] = useState<string | null>(null);

  async function create() {
    if (!draft.name.trim()) {
      toast.error("Name is required");
      return;
    }
    setCreating(true);
    try {
      const { data } = await apiFetchClient<{ data: Discount }>("/v1/admin/discounts", {
        method: "POST",
        body: JSON.stringify({
          code: draft.code.trim() || undefined,
          name: draft.name.trim(),
          type: draft.type,
          value: draft.type === "free_shipping" ? 0 : Number(draft.value || 0),
          minOrderValue: Math.round(Number(draft.minOrderValue || 0) * 100),
          maxUses: draft.maxUses ? Number(draft.maxUses) : undefined,
        }),
      });
      setDiscounts((prev) => [data, ...prev]);
      setDraft(EMPTY_DRAFT);
      toast.success("Discount created");
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Could not create discount");
    } finally {
      setCreating(false);
    }
  }

  async function toggleActive(discount: Discount) {
    setActingOn(discount.id);
    try {
      const { data } = await apiFetchClient<{ data: Discount }>(`/v1/admin/discounts/${discount.id}`, {
        method: "PATCH",
        body: JSON.stringify({ isActive: !discount.isActive }),
      });
      setDiscounts((prev) => prev.map((d) => (d.id === data.id ? data : d)));
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Could not update discount");
    } finally {
      setActingOn(null);
    }
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>New discount</CardTitle>
          <CardDescription>Platform-wide, admin-authored -- every discount here is funded by the platform, never a shop (migrations/026&rsquo;s own header).</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-2">
          <div>
            <Label htmlFor="d-name">Name</Label>
            <Input id="d-name" value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} />
          </div>
          <div>
            <Label htmlFor="d-code">Code (optional)</Label>
            <Input id="d-code" value={draft.code} onChange={(e) => setDraft({ ...draft, code: e.target.value.toUpperCase() })} placeholder="PROX20" />
          </div>
          <div>
            <Label htmlFor="d-type">Type</Label>
            <Select id="d-type" value={draft.type} onChange={(e) => setDraft({ ...draft, type: e.target.value as DiscountType })}>
              <option value="percent">Percent off</option>
              <option value="flat">Flat amount off</option>
              <option value="free_shipping">Free delivery</option>
            </Select>
          </div>
          {draft.type !== "free_shipping" && (
            <div>
              <Label htmlFor="d-value">{draft.type === "percent" ? "Percent (e.g. 10)" : "Amount off (₹)"}</Label>
              <Input id="d-value" type="number" min="0" value={draft.value} onChange={(e) => setDraft({ ...draft, value: e.target.value })} />
            </div>
          )}
          <div>
            <Label htmlFor="d-min">Minimum order value (₹)</Label>
            <Input id="d-min" type="number" min="0" value={draft.minOrderValue} onChange={(e) => setDraft({ ...draft, minOrderValue: e.target.value })} />
          </div>
          <div>
            <Label htmlFor="d-uses">Max uses (blank = unlimited)</Label>
            <Input id="d-uses" type="number" min="1" value={draft.maxUses} onChange={(e) => setDraft({ ...draft, maxUses: e.target.value })} />
          </div>
        </CardContent>
        <CardFooter>
          <Button disabled={creating} onClick={create}>
            {creating ? "Creating…" : "Create discount"}
          </Button>
        </CardFooter>
      </Card>

      {discounts.length === 0 ? (
        <p className="text-sm text-muted-foreground">No discounts yet.</p>
      ) : (
        <div className="overflow-x-auto rounded-lg border">
          <table className="w-full text-sm">
            <thead className="bg-muted text-left text-muted-foreground">
              <tr>
                <th className="px-4 py-2 font-medium">Name</th>
                <th className="px-4 py-2 font-medium">Code</th>
                <th className="px-4 py-2 font-medium">Type</th>
                <th className="px-4 py-2 font-medium">Value</th>
                <th className="px-4 py-2 font-medium">Uses</th>
                <th className="px-4 py-2 font-medium">Status</th>
                <th className="px-4 py-2 font-medium" />
              </tr>
            </thead>
            <tbody>
              {discounts.map((d) => (
                <tr key={d.id} className="border-t">
                  <td className="px-4 py-2 font-medium">{d.name}</td>
                  <td className="px-4 py-2 tabular-nums">{d.code ?? "—"}</td>
                  <td className="px-4 py-2">{TYPE_LABEL[d.type]}</td>
                  <td className="px-4 py-2 tabular-nums">{d.type === "flat" ? `₹${(d.value / 100).toFixed(2)}` : d.type === "percent" ? `${d.value}%` : "—"}</td>
                  <td className="px-4 py-2 tabular-nums">{d.usesCount}{d.maxUses ? ` / ${d.maxUses}` : ""}</td>
                  <td className="px-4 py-2">
                    <Badge variant={d.isActive ? "default" : "secondary"}>{d.isActive ? "Active" : "Inactive"}</Badge>
                  </td>
                  <td className="px-4 py-2 text-right">
                    <Button size="sm" variant={d.isActive ? "destructive" : "outline"} disabled={actingOn === d.id} onClick={() => toggleActive(d)}>
                      {d.isActive ? "Deactivate" : "Activate"}
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
