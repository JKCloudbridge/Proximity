import { apiFetch } from "@/lib/api";
import type { Discount } from "@/lib/types";
import { DiscountsClient } from "./discounts-client";

// Sprint 12 -- §11's Sprint 12 entry: "discount authoring UI (discounts
// exists since Sprint 7 with one seeded code and no admin UI to add more)."
export default async function AdminDiscountsPage() {
  const { data: discounts } = await apiFetch<{ data: Discount[] }>("/v1/admin/discounts");
  return <DiscountsClient initialDiscounts={discounts} />;
}
