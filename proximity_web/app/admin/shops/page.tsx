import { apiFetch } from "@/lib/api";
import type { Shop } from "@/lib/types";
import { ShopsClient } from "./shops-client";

// §8.6's shop approval queue. Server-fetches the full list on load (no
// query param yet -- ShopsClient re-fetches per status tab client-side via
// GET /v1/admin/shops?status=, routes/admin.ts's optional filter) so the
// first paint already has data instead of a loading flash.
export default async function AdminShopsPage() {
  const { data: shops } = await apiFetch<{ data: Shop[] }>("/v1/admin/shops");
  return <ShopsClient initialShops={shops} />;
}
