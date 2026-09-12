import { redirect } from "next/navigation";
import { apiFetch, ApiError } from "./api";
import type { MeResponse, Shop } from "./types";

// Server-side re-check, on top of proxy.ts's edge-level gate (defense in
// depth, same two-layer shape as baker_ally_admin's lib/auth.ts). POST
// /v1/auth/me (routes/auth.ts, Sprint 1) is idempotent -- safe to call on
// every protected page load, doubles as "hydrate the users row" for a
// brand-new signup and "fetch my role" for a returning session.
export async function requireUser(): Promise<MeResponse["data"]> {
  try {
    return (await apiFetch<MeResponse>("/v1/auth/me", { method: "POST" })).data;
  } catch (err) {
    if (err instanceof ApiError) redirect("/login");
    throw err;
  }
}

export async function requireAdmin(): Promise<MeResponse["data"]> {
  const me = await requireUser();
  if (me.role !== "admin") redirect("/unauthorized");
  return me;
}

// A shop owner's *global* role flips to 'shop_owner' at shop-creation time
// (rpc_create_shop, migrations/014), but the real gate for "does this
// account have a shop yet" is shop_team_members membership, not the role
// column (§1.2 -- staff/delivery members never get a global role change at
// all). GET /v1/shop/shops/mine (routes/shops.ts) is the membership query,
// so this checks that directly rather than trusting `role`.
export async function requireShop(): Promise<{ me: MeResponse["data"]; shop: Shop }> {
  const me = await requireUser();
  const { data: shops } = await apiFetch<{ data: Shop[] }>("/v1/shop/shops/mine");
  if (shops.length === 0) redirect("/onboarding/shop");
  return { me, shop: shops[0] };
}
