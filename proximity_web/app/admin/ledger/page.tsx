import { apiFetch } from "@/lib/api";
import type { PlatformLedgerRow } from "@/lib/types";
import { AdminLedgerClient } from "./admin-ledger-client";

// Sprint 12 -- §8.6's "a platform-wide ledger view across all shops
// (aggregate payout_due/commission_due)" -- now genuinely net of
// migrations/046's reversal rows (lib/ledger.ts's shared balance formula),
// not just a raw sum of still-pending rows the way it would have had to be
// before Sprint 12 built the reversal mechanism at all.
export default async function AdminLedgerPage() {
  const { data } = await apiFetch<{ data: { balances: PlatformLedgerRow[] } }>("/v1/admin/ledger");
  return <AdminLedgerClient initialBalances={data.balances} />;
}
