"use client";

import { useState } from "react";
import { toast } from "sonner";
import { apiFetchClient, ApiError } from "@/lib/api-client";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import type { LedgerEntry, PlatformLedgerRow } from "@/lib/types";

const fmt = (paise: number) => `₹${(paise / 100).toFixed(2)}`;

export function AdminLedgerClient({ initialBalances }: { initialBalances: PlatformLedgerRow[] }) {
  const [expandedShop, setExpandedShop] = useState<string | null>(null);
  const [entriesByShop, setEntriesByShop] = useState<Record<string, LedgerEntry[]>>({});
  const [loading, setLoading] = useState<string | null>(null);

  const totalPayoutDue = initialBalances.reduce((sum, b) => sum + b.netPayoutDuePaise, 0);
  const totalCommissionDue = initialBalances.reduce((sum, b) => sum + b.netCommissionDuePaise, 0);

  async function toggleShop(shopId: string) {
    if (expandedShop === shopId) {
      setExpandedShop(null);
      return;
    }
    setExpandedShop(shopId);
    if (entriesByShop[shopId]) return;

    setLoading(shopId);
    try {
      const { data } = await apiFetchClient<{ data: LedgerEntry[] }>(`/v1/admin/ledger/entries?shopId=${shopId}`);
      setEntriesByShop((prev) => ({ ...prev, [shopId]: data }));
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Could not load entries");
    } finally {
      setLoading(null);
    }
  }

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <div className="grid gap-4 sm:grid-cols-2">
        <Card>
          <CardHeader>
            <CardDescription>Total platform owes shops</CardDescription>
            <CardTitle className="text-2xl">{fmt(totalPayoutDue)}</CardTitle>
          </CardHeader>
        </Card>
        <Card>
          <CardHeader>
            <CardDescription>Total shops owe platform</CardDescription>
            <CardTitle className="text-2xl">{fmt(totalCommissionDue)}</CardTitle>
          </CardHeader>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>By shop</CardTitle>
          <CardDescription>Net of any cancellation reversals -- expand a shop to see its itemized entries.</CardDescription>
        </CardHeader>
        <CardContent>
          {initialBalances.length === 0 ? (
            <p className="text-sm text-muted-foreground">No ledger activity yet.</p>
          ) : (
            <div className="space-y-2">
              {initialBalances.map((b) => (
                <div key={b.shopId} className="rounded-lg border">
                  <button
                    onClick={() => toggleShop(b.shopId)}
                    className="flex w-full items-center justify-between px-4 py-3 text-left text-sm"
                  >
                    <span className="font-medium">{b.shopName}</span>
                    <span className="flex gap-4 text-muted-foreground">
                      <span>Owed to shop: {fmt(b.netPayoutDuePaise)}</span>
                      <span>Owed by shop: {fmt(b.netCommissionDuePaise)}</span>
                    </span>
                  </button>
                  {expandedShop === b.shopId && (
                    <div className="border-t px-4 py-3">
                      {loading === b.shopId ? (
                        <p className="text-sm text-muted-foreground">Loading…</p>
                      ) : (
                        <ul className="space-y-1 text-sm">
                          {(entriesByShop[b.shopId] ?? []).map((e) => (
                            <li key={e.id} className="flex justify-between">
                              <span className="capitalize text-muted-foreground">{e.entryType.replace(/_/g, " ")}</span>
                              <span className="tabular-nums">{fmt(e.amount)}</span>
                            </li>
                          ))}
                          {(entriesByShop[b.shopId] ?? []).length === 0 && (
                            <li className="text-muted-foreground">No entries.</li>
                          )}
                        </ul>
                      )}
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
