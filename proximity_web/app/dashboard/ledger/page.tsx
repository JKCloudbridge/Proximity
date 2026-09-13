import { requireShop } from "@/lib/auth";
import { apiFetch } from "@/lib/api";
import type { LedgerEntry, ShopLedgerBalance } from "@/lib/types";
import { LedgerClient } from "./ledger-client";

// Sprint 12 -- §8.4's "a real ledger view (§8.4) on ... the shopkeeper
// dashboard," §11's own exit criteria: "a shopkeeper can see their own ...
// outstanding ledger balance." lib/ledger.ts's own balance formula (net of
// migrations/046's reversal rows) is what `balance` below already is --
// this page never re-derives it client-side.
export default async function LedgerPage() {
  const { shop } = await requireShop();
  const { data } = await apiFetch<{ data: { balance: ShopLedgerBalance; entries: LedgerEntry[] } }>(
    `/v1/shop/shops/${shop.id}/ledger`,
  );
  return <LedgerClient shopId={shop.id} initialBalance={data.balance} initialEntries={data.entries} />;
}
