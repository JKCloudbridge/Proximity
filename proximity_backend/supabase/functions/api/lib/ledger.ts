import { desc, eq, sql } from "npm:drizzle-orm";

import { db } from "./db.ts";
import { shopLedgerEntries, shops } from "../db/schema.ts";

// Sprint 12 -- §8.4/§8.6's "real ledger view," both the shop-side one and
// the platform-wide admin one, share this one balance formula rather than
// each re-deriving it. migrations/046's own header is the actual design
// decision this implements: a reversal is always a NEW row (payout_reversal/
// commission_reversal), never a mutation of the original -- so "what's the
// real outstanding balance" is always this same subtraction, regardless of
// whether a cancelled order's original entry was already 'settled' or still
// 'pending' at cancellation time. Never special-cases `status` for that
// reason: `status` tracks whether Phase 2 settlement automation (still not
// built, §4.9) has actually paid a row out, not whether it's still owed.
export type ShopLedgerBalance = {
  shopId: string;
  // Positive = platform still owes the shop this many paise (online orders,
  // plus any discount-absorption reimbursement, minus anything reversed by
  // a cancellation).
  netPayoutDuePaise: number;
  // Positive = the shop still owes the platform this many paise (pay_at_shop
  // commission, minus anything reversed by a cancellation).
  netCommissionDuePaise: number;
};

async function ledgerBalanceRows(shopIdFilter?: string): Promise<ShopLedgerBalance[]> {
  const rows = (await db.execute(sql`
    SELECT
      shop_id,
      COALESCE(SUM(CASE WHEN entry_type = 'payout_due' THEN amount ELSE 0 END), 0)
        - COALESCE(SUM(CASE WHEN entry_type = 'payout_reversal' THEN amount ELSE 0 END), 0) AS net_payout_due,
      COALESCE(SUM(CASE WHEN entry_type = 'commission_due' THEN amount ELSE 0 END), 0)
        - COALESCE(SUM(CASE WHEN entry_type = 'commission_reversal' THEN amount ELSE 0 END), 0) AS net_commission_due
    FROM shop_ledger_entries
    ${shopIdFilter ? sql`WHERE shop_id = ${shopIdFilter}::uuid` : sql``}
    GROUP BY shop_id
  `)) as unknown as { shop_id: string; net_payout_due: string; net_commission_due: string }[];

  // SUM(integer) comes back as bigint -> a JS string through postgres.js
  // (same landmine recommendations.ts's own trend-score column hit in
  // Sprint 6) -- cast down explicitly rather than trust an implicit
  // string-to-number coercion at every call site.
  return rows.map((r) => ({
    shopId: r.shop_id,
    netPayoutDuePaise: Number(r.net_payout_due),
    netCommissionDuePaise: Number(r.net_commission_due),
  }));
}

export async function getShopLedgerBalance(shopId: string): Promise<ShopLedgerBalance> {
  const [row] = await ledgerBalanceRows(shopId);
  return row ?? { shopId, netPayoutDuePaise: 0, netCommissionDuePaise: 0 };
}

export type PlatformLedgerRow = ShopLedgerBalance & { shopName: string };

// §8.6's "platform-wide ledger view across all shops (aggregate payout_due/
// commission_due)" -- now genuinely net-of-reversals, not just a raw sum of
// still-pending due rows the way a pre-Sprint-12 version would have had to
// be (no reversal mechanism existed before migrations/046).
export async function getPlatformLedgerBalances(): Promise<PlatformLedgerRow[]> {
  const balances = await ledgerBalanceRows();
  if (balances.length === 0) return [];

  const shopIds = balances.map((b) => b.shopId);
  const shopRows = await db.select({ id: shops.id, name: shops.name }).from(shops);
  const nameById = new Map(shopRows.map((s) => [s.id, s.name]));

  return balances
    .filter((b) => shopIds.includes(b.shopId))
    .map((b) => ({ ...b, shopName: nameById.get(b.shopId) ?? "Unknown shop" }))
    .sort((a, b) => b.netPayoutDuePaise - a.netPayoutDuePaise);
}

export type LedgerEntryRow = {
  id: string;
  shopId: string;
  orderId: string | null;
  entryType: string;
  amount: number;
  status: string;
  reversesEntryId: string | null;
  createdAt: Date;
};

// The itemized feed underneath a balance -- one shop's own view
// (routes/shopAnalytics.ts) or, with no shopId, every entry platform-wide
// (routes/admin.ts). Most-recent-first, plain offset pagination -- same
// "minimum that makes the exit criteria true" scope discipline every public
// list route in this project starts with (Sprint 3/4/5's own precedent);
// revisit with keyset pagination once a real shop has thousands of rows.
export async function listLedgerEntries({
  shopId,
  limit = 50,
  offset = 0,
}: {
  shopId?: string;
  limit?: number;
  offset?: number;
}): Promise<LedgerEntryRow[]> {
  const query = db.select().from(shopLedgerEntries);
  const rows = await (shopId ? query.where(eq(shopLedgerEntries.shopId, shopId)) : query)
    .orderBy(desc(shopLedgerEntries.createdAt))
    .limit(limit)
    .offset(offset);

  return rows.map((r) => ({
    id: r.id,
    shopId: r.shopId,
    orderId: r.orderId,
    entryType: r.entryType,
    amount: r.amount,
    status: r.status,
    reversesEntryId: r.reversesEntryId,
    createdAt: r.createdAt,
  }));
}
