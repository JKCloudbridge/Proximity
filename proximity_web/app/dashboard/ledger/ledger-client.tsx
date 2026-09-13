"use client";

import { useState } from "react";
import { toast } from "sonner";
import { apiFetchClient, ApiError } from "@/lib/api-client";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import type { LedgerEntry, ShopLedgerBalance } from "@/lib/types";

const fmt = (paise: number) => `₹${(paise / 100).toFixed(2)}`;

const ENTRY_LABEL: Record<LedgerEntry["entryType"], string> = {
  payout_due: "Platform owes you",
  commission_due: "You owe platform",
  payout_reversal: "Payout reversed (order cancelled)",
  commission_reversal: "Commission reversed (order cancelled)",
};

const ENTRY_VARIANT: Record<LedgerEntry["entryType"], "default" | "destructive" | "accent"> = {
  payout_due: "default",
  commission_due: "destructive",
  payout_reversal: "accent",
  commission_reversal: "accent",
};

export function LedgerClient({
  shopId,
  initialBalance,
  initialEntries,
}: {
  shopId: string;
  initialBalance: ShopLedgerBalance;
  initialEntries: LedgerEntry[];
}) {
  const [balance, setBalance] = useState(initialBalance);
  const [entries, setEntries] = useState(initialEntries);
  const [offset, setOffset] = useState(0);
  const [loading, setLoading] = useState(false);
  const pageSize = 50;

  async function loadMore() {
    setLoading(true);
    try {
      const nextOffset = offset + pageSize;
      const { data } = await apiFetchClient<{ data: { balance: ShopLedgerBalance; entries: LedgerEntry[] } }>(
        `/v1/shop/shops/${shopId}/ledger?offset=${nextOffset}&limit=${pageSize}`,
      );
      setEntries((prev) => [...prev, ...data.entries]);
      setBalance(data.balance);
      setOffset(nextOffset);
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Could not load more entries");
    } finally {
      setLoading(false);
    }
  }

  const net = balance.netPayoutDuePaise - balance.netCommissionDuePaise;

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <div className="grid gap-4 sm:grid-cols-3">
        <Card>
          <CardHeader>
            <CardDescription>Platform owes you</CardDescription>
            <CardTitle className="text-2xl">{fmt(balance.netPayoutDuePaise)}</CardTitle>
          </CardHeader>
        </Card>
        <Card>
          <CardHeader>
            <CardDescription>You owe platform</CardDescription>
            <CardTitle className="text-2xl">{fmt(balance.netCommissionDuePaise)}</CardTitle>
          </CardHeader>
        </Card>
        <Card>
          <CardHeader>
            <CardDescription>Net outstanding balance</CardDescription>
            <CardTitle className={net >= 0 ? "text-2xl text-primary" : "text-2xl text-destructive"}>
              {net >= 0 ? `+${fmt(net)}` : `-${fmt(Math.abs(net))}`}
            </CardTitle>
          </CardHeader>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Entries</CardTitle>
          <CardDescription>
            Every row is permanent -- a cancelled order&rsquo;s obligation is reversed with a new offsetting row, never edited
            in place.
          </CardDescription>
        </CardHeader>
        <CardContent>
          {entries.length === 0 ? (
            <p className="text-sm text-muted-foreground">No ledger entries yet.</p>
          ) : (
            <div className="overflow-x-auto rounded-lg border">
              <table className="w-full text-sm">
                <thead className="bg-muted text-left text-muted-foreground">
                  <tr>
                    <th className="px-4 py-2 font-medium">Date</th>
                    <th className="px-4 py-2 font-medium">Type</th>
                    <th className="px-4 py-2 font-medium">Amount</th>
                    <th className="px-4 py-2 font-medium">Status</th>
                  </tr>
                </thead>
                <tbody>
                  {entries.map((e) => (
                    <tr key={e.id} className="border-t">
                      <td className="px-4 py-2 text-muted-foreground">{new Date(e.createdAt).toLocaleDateString()}</td>
                      <td className="px-4 py-2">
                        <Badge variant={ENTRY_VARIANT[e.entryType]}>{ENTRY_LABEL[e.entryType]}</Badge>
                      </td>
                      <td className="px-4 py-2 tabular-nums">{fmt(e.amount)}</td>
                      <td className="px-4 py-2 capitalize text-muted-foreground">{e.status}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          {entries.length >= pageSize && entries.length === offset + pageSize && (
            <div className="mt-4 text-center">
              <Button variant="outline" size="sm" disabled={loading} onClick={loadMore}>
                {loading ? "Loading…" : "Load more"}
              </Button>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
