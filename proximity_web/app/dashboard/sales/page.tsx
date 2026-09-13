import { requireShop } from "@/lib/auth";
import { apiFetch } from "@/lib/api";
import type { ShopSalesSummary } from "@/lib/types";
import { SalesClient } from "./sales-client";

// Sprint 12 -- §8.4's "sales summary aggregation views" on the shopkeeper
// dashboard, §11's own exit criteria: "a shopkeeper can see their own real
// revenue numbers." Server-fetches the default 30-day window on load, same
// "first paint already has data" pattern AdminShopsPage established --
// SalesClient re-fetches client-side when the range selector changes.
export default async function SalesPage() {
  const { shop } = await requireShop();
  const { data: summary } = await apiFetch<{ data: ShopSalesSummary }>(
    `/v1/shop/shops/${shop.id}/analytics/sales-summary?days=30`,
  );
  return <SalesClient shopId={shop.id} initialSummary={summary} />;
}
