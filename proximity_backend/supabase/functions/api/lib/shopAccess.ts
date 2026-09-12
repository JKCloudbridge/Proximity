import { and, eq } from "npm:drizzle-orm";

import { db } from "./db.ts";
import { shopTeamMembers } from "../db/schema.ts";

// Shop-team membership isn't a global role (§1.2), so it can't be checked
// with requireRole() the way admin routes are -- it's "is this user a
// member of *this specific* shop, with *this* member_role." Every
// shop-scoped route asks this same question, so it lives here once instead
// of being re-derived per route. This is a plain query against the
// service-role connection, not RLS -- consistent with SPRINT_PLANNING.md
// §5.1 (RLS is a backstop, the Edge Function is the trust boundary).
//
// JWT-embedded shop_id/member_role claims (mentioned as a future
// optimization in §3.5) aren't built yet -- not required for MVP
// correctness, per that same section, and this DB round trip is cheap
// enough at Sprint 2's scale.

export type MemberRole = "owner" | "staff" | "delivery";

export async function getShopMembership(userId: string, shopId: string): Promise<MemberRole | null> {
  const [row] = await db
    .select({ memberRole: shopTeamMembers.memberRole })
    .from(shopTeamMembers)
    .where(and(eq(shopTeamMembers.shopId, shopId), eq(shopTeamMembers.userId, userId)))
    .limit(1);
  return (row?.memberRole as MemberRole | undefined) ?? null;
}

export async function isShopOwner(userId: string, shopId: string): Promise<boolean> {
  return (await getShopMembership(userId, shopId)) === "owner";
}

// §5.3's "Add/edit catalog" row -- owner AND staff can write the catalog
// (sub-categories, products, variants, images); only `delivery` is excluded.
// Sprint 3's first consumer (routes/catalog.ts); pulled out here rather than
// re-inlining the same ["owner","staff"].includes(...) check in every
// catalog route, same reasoning this file's header gives for existing once.
export async function isShopWriter(userId: string, shopId: string): Promise<boolean> {
  const role = await getShopMembership(userId, shopId);
  return role === "owner" || role === "staff";
}

// Sprint 9 -- §5.3's "View orders & accept/advance status" row: ALL three
// member_roles (owner/staff/delivery) get this right, unlike isShopWriter's
// owner-or-staff-only catalog gate. routes/shopOrders.ts's order list and
// advance-status route use this; the rider-assignment trigger route uses
// isShopWriter instead (deliberately narrower -- see that route's own
// comment for why handing an order to the platform's rider network is an
// owner/staff-level operational call, not a delivery-role action).
export async function isShopMember(userId: string, shopId: string): Promise<boolean> {
  return (await getShopMembership(userId, shopId)) !== null;
}

export async function shopIdsForUser(userId: string): Promise<string[]> {
  const rows = await db.select({ shopId: shopTeamMembers.shopId }).from(shopTeamMembers).where(eq(shopTeamMembers.userId, userId));
  return rows.map((r) => r.shopId);
}
