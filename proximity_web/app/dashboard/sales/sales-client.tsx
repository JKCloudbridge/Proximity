"use client";

import { useState } from "react";
import { toast } from "sonner";
import { apiFetchClient, ApiError } from "@/lib/api-client";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { cn } from "@/lib/utils";
import type { ShopSalesSummary } from "@/lib/types";

const RANGES = [
  { days: 7, label: "7 days" },
  { days: 30, label: "30 days" },
  { days: 90, label: "90 days" },
];

const fmt = (paise: number) => `₹${(paise / 100).toFixed(2)}`;

export function SalesClient({ shopId, initialSummary }: { shopId: string; initialSummary: ShopSalesSummary }) {
  const [days, setDays] = useState(30);
  const [summary, setSummary] = useState(initialSummary);
  const [loading, setLoading] = useState(false);

  async function loadRange(next: number) {
    setDays(next);
    setLoading(true);
    try {
      const { data } = await apiFetchClient<{ data: ShopSalesSummary }>(
        `/v1/shop/shops/${shopId}/analytics/sales-summary?days=${next}`,
      );
      setSummary(data);
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Could not load sales summary");
    } finally {
      setLoading(false);
    }
  }

  const maxDailyRevenue = Math.max(1, ...summary.daily.map((d) => d.revenuePaise));

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <div className="flex gap-1 border-b">
        {RANGES.map((r) => (
          <button
            key={r.days}
            onClick={() => loadRange(r.days)}
            className={cn(
              "border-b-2 border-transparent px-3 py-2 text-sm font-medium text-muted-foreground",
              days === r.days && "border-primary text-foreground",
            )}
          >
            {r.label}
          </button>
        ))}
      </div>

      <div className={cn("grid gap-4 sm:grid-cols-2 lg:grid-cols-4", loading && "opacity-60")}>
        <Card>
          <CardHeader>
            <CardDescription>Gross revenue</CardDescription>
            <CardTitle className="text-2xl">{fmt(summary.grossRevenuePaise)}</CardTitle>
          </CardHeader>
        </Card>
        <Card>
          <CardHeader>
            <CardDescription>Orders</CardDescription>
            <CardTitle className="text-2xl">{summary.orderCount}</CardTitle>
          </CardHeader>
        </Card>
        <Card>
          <CardHeader>
            <CardDescription>Average order value</CardDescription>
            <CardTitle className="text-2xl">{fmt(summary.averageOrderValuePaise)}</CardTitle>
          </CardHeader>
        </Card>
        <Card>
          <CardHeader>
            <CardDescription>Cancelled orders</CardDescription>
            <CardTitle className="text-2xl">{summary.cancelledOrderCount}</CardTitle>
          </CardHeader>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Daily revenue</CardTitle>
          <CardDescription>
            Commission owed on this revenue over the period: {fmt(summary.commissionOwedPaise)} -- see the Ledger tab for
            your real, outstanding balance.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {summary.daily.length === 0 ? (
            <p className="text-sm text-muted-foreground">No confirmed orders in this range yet.</p>
          ) : (
            <div className="flex h-40 items-end gap-1 overflow-x-auto">
              {summary.daily.map((d) => (
                <div key={d.date} className="flex min-w-6 flex-1 flex-col items-center gap-1" title={`${d.date}: ${fmt(d.revenuePaise)} (${d.orderCount} orders)`}>
                  <div
                    className="w-full rounded-t bg-primary"
                    style={{ height: `${Math.max(4, (d.revenuePaise / maxDailyRevenue) * 100)}%` }}
                  />
                  <span className="text-[10px] text-muted-foreground">{d.date.slice(5)}</span>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
