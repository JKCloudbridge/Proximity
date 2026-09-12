"use client";

import { useState } from "react";
import { toast } from "sonner";
import { apiFetchClient, ApiError } from "@/lib/api-client";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import type { Shop, ShopStatus } from "@/lib/types";

const TABS: { value: ShopStatus | "all"; label: string }[] = [
  { value: "pending", label: "Pending" },
  { value: "approved", label: "Approved" },
  { value: "suspended", label: "Suspended" },
  { value: "all", label: "All" },
];

const STATUS_VARIANT = { pending: "accent", approved: "default", suspended: "destructive" } as const;

export function ShopsClient({ initialShops }: { initialShops: Shop[] }) {
  const [tab, setTab] = useState<ShopStatus | "all">("pending");
  const [shops, setShops] = useState(initialShops);
  const [loading, setLoading] = useState(false);
  const [actingOn, setActingOn] = useState<string | null>(null);

  async function loadTab(next: ShopStatus | "all") {
    setTab(next);
    setLoading(true);
    try {
      const query = next === "all" ? "" : `?status=${next}`;
      const { data } = await apiFetchClient<{ data: Shop[] }>(`/v1/admin/shops${query}`);
      setShops(data);
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Could not load shops");
    } finally {
      setLoading(false);
    }
  }

  async function act(shopId: string, action: "approve" | "suspend") {
    setActingOn(shopId);
    try {
      await apiFetchClient(`/v1/admin/shops/${shopId}/${action}`, { method: "POST" });
      toast.success(action === "approve" ? "Shop approved" : "Shop suspended");
      await loadTab(tab);
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Action failed");
    } finally {
      setActingOn(null);
    }
  }

  return (
    <div>
      <div className="mb-4 flex gap-1 border-b">
        {TABS.map((t) => (
          <button
            key={t.value}
            onClick={() => loadTab(t.value)}
            className={cn(
              "border-b-2 border-transparent px-3 py-2 text-sm font-medium text-muted-foreground",
              tab === t.value && "border-primary text-foreground",
            )}
          >
            {t.label}
          </button>
        ))}
      </div>

      {loading ? (
        <p className="text-sm text-muted-foreground">Loading…</p>
      ) : shops.length === 0 ? (
        <p className="text-sm text-muted-foreground">No shops here.</p>
      ) : (
        <div className="overflow-x-auto rounded-lg border">
          <table className="w-full text-sm">
            <thead className="bg-muted text-left text-muted-foreground">
              <tr>
                <th className="px-4 py-2 font-medium">Shop</th>
                <th className="px-4 py-2 font-medium">Location</th>
                <th className="px-4 py-2 font-medium">Delivery mode</th>
                <th className="px-4 py-2 font-medium">Status</th>
                <th className="px-4 py-2 font-medium" />
              </tr>
            </thead>
            <tbody>
              {shops.map((shop) => (
                <tr key={shop.id} className="border-t">
                  <td className="px-4 py-2 font-medium">{shop.name}</td>
                  <td className="px-4 py-2">{shop.city}</td>
                  <td className="px-4 py-2 capitalize">{shop.deliveryMode}</td>
                  <td className="px-4 py-2">
                    <Badge variant={STATUS_VARIANT[shop.status]} className="capitalize">
                      {shop.status}
                    </Badge>
                  </td>
                  <td className="px-4 py-2 text-right">
                    <div className="flex justify-end gap-2">
                      {shop.status !== "approved" && (
                        <Button size="sm" disabled={actingOn === shop.id} onClick={() => act(shop.id, "approve")}>
                          Approve
                        </Button>
                      )}
                      {shop.status !== "suspended" && (
                        <Button size="sm" variant="destructive" disabled={actingOn === shop.id} onClick={() => act(shop.id, "suspend")}>
                          {shop.status === "pending" ? "Reject" : "Suspend"}
                        </Button>
                      )}
                    </div>
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
