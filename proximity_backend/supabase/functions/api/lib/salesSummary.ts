import { sql } from "npm:drizzle-orm";

import { db } from "./db.ts";

// Sprint 12 -- §8.4's "sales summary aggregation views," §11's own exit
// criteria: "a shopkeeper can see their own real revenue numbers." A live,
// bounded query (a fixed day-range, grouped once), same "documented, not
// unlimited" scope cut recommendations.ts (Sprint 6) and repeatPurchases.ts/
// frequentlyBoughtGroups.ts (Sprint 10) each made for their own aggregate
// queries -- not a materialized view or scheduled rollup table, revisit only
// once a real shop's order volume makes a live scan over `days` actually
// expensive, which nothing about this project's current (zero) real order
// volume suggests yet.
//
// "Revenue" here means `orders.total` -- this shop's own share of whatever
// the buyer paid or owes for this order (§4.8: already net of that shop's
// own discount allocation, inclusive of any delivery fee that shop's own
// order carries) -- summed only over orders that reached at least
// 'confirmed' (a still-'pending' unpaid placement was never a real sale;
// same exclusion rule repeatPurchases.ts's own header already established
// for "previously bought," reused here for consistency rather than
// inventing a second definition of "did this order actually happen").
// `cancelled` is excluded from revenue but reported as its own count, since
// a shopkeeper reading "how did my week go" needs to see cancellations, not
// have them silently vanish from the picture.
const CONFIRMED_OR_LATER = sql`status NOT IN ('pending', 'cancelled')`;

export type DailySalesPoint = { date: string; orderCount: number; revenuePaise: number };

export type ShopSalesSummary = {
  rangeDays: number;
  orderCount: number;
  cancelledOrderCount: number;
  grossRevenuePaise: number;
  commissionOwedPaise: number;
  averageOrderValuePaise: number;
  daily: DailySalesPoint[];
};

export async function getShopSalesSummary(shopId: string, rangeDays: number): Promise<ShopSalesSummary> {
  const [totals] = (await db.execute(sql`
    SELECT
      COUNT(*) FILTER (WHERE ${CONFIRMED_OR_LATER})::integer AS order_count,
      COUNT(*) FILTER (WHERE status = 'cancelled')::integer AS cancelled_order_count,
      COALESCE(SUM(total) FILTER (WHERE ${CONFIRMED_OR_LATER}), 0)::bigint AS gross_revenue,
      -- Same ROUND(subtotal * platform_commission_pct / 100.0) formula
      -- rpc_confirm_payment (migrations/036) actually charges -- this is a
      -- read-only re-derivation of that same math for display, not a second
      -- source of truth (the real obligation always lives in
      -- shop_ledger_entries, lib/ledger.ts).
      COALESCE(SUM(ROUND(subtotal * platform_commission_pct / 100.0)) FILTER (WHERE ${CONFIRMED_OR_LATER}), 0)::bigint AS commission_owed
    FROM orders
    WHERE shop_id = ${shopId}::uuid AND created_at >= now() - (${rangeDays}::text || ' days')::interval
  `)) as unknown as { order_count: number; cancelled_order_count: number; gross_revenue: string; commission_owed: string }[];

  const dailyRows = (await db.execute(sql`
    SELECT
      to_char(date_trunc('day', created_at), 'YYYY-MM-DD') AS day,
      COUNT(*)::integer AS order_count,
      COALESCE(SUM(total), 0)::bigint AS revenue
    FROM orders
    WHERE shop_id = ${shopId}::uuid
      AND created_at >= now() - (${rangeDays}::text || ' days')::interval
      AND ${CONFIRMED_OR_LATER}
    GROUP BY 1
    ORDER BY 1
  `)) as unknown as { day: string; order_count: number; revenue: string }[];

  const orderCount = totals?.order_count ?? 0;
  const grossRevenuePaise = Number(totals?.gross_revenue ?? 0);

  return {
    rangeDays,
    orderCount,
    cancelledOrderCount: totals?.cancelled_order_count ?? 0,
    grossRevenuePaise,
    commissionOwedPaise: Number(totals?.commission_owed ?? 0),
    averageOrderValuePaise: orderCount > 0 ? Math.round(grossRevenuePaise / orderCount) : 0,
    daily: dailyRows.map((r) => ({ date: r.day, orderCount: r.order_count, revenuePaise: Number(r.revenue) })),
  };
}

// §8.6's platform-wide counterpart -- the same shape, no shop_id filter, plus
// a per-shop breakdown for the admin's own "who's actually driving revenue"
// question. Bounded the same way (a fixed day-range), same reasoning as
// above.
export type PlatformSalesSummary = ShopSalesSummary & {
  byShop: { shopId: string; shopName: string; orderCount: number; grossRevenuePaise: number }[];
};

export async function getPlatformSalesSummary(rangeDays: number): Promise<PlatformSalesSummary> {
  const [totals] = (await db.execute(sql`
    SELECT
      COUNT(*) FILTER (WHERE ${CONFIRMED_OR_LATER})::integer AS order_count,
      COUNT(*) FILTER (WHERE status = 'cancelled')::integer AS cancelled_order_count,
      COALESCE(SUM(total) FILTER (WHERE ${CONFIRMED_OR_LATER}), 0)::bigint AS gross_revenue,
      COALESCE(SUM(ROUND(subtotal * platform_commission_pct / 100.0)) FILTER (WHERE ${CONFIRMED_OR_LATER}), 0)::bigint AS commission_owed
    FROM orders
    WHERE created_at >= now() - (${rangeDays}::text || ' days')::interval
  `)) as unknown as { order_count: number; cancelled_order_count: number; gross_revenue: string; commission_owed: string }[];

  const dailyRows = (await db.execute(sql`
    SELECT
      to_char(date_trunc('day', created_at), 'YYYY-MM-DD') AS day,
      COUNT(*)::integer AS order_count,
      COALESCE(SUM(total), 0)::bigint AS revenue
    FROM orders
    WHERE created_at >= now() - (${rangeDays}::text || ' days')::interval AND ${CONFIRMED_OR_LATER}
    GROUP BY 1
    ORDER BY 1
  `)) as unknown as { day: string; order_count: number; revenue: string }[];

  const byShopRows = (await db.execute(sql`
    SELECT o.shop_id, s.name AS shop_name,
           COUNT(*)::integer AS order_count,
           COALESCE(SUM(o.total), 0)::bigint AS gross_revenue
    FROM orders o
    JOIN shops s ON s.id = o.shop_id
    WHERE o.created_at >= now() - (${rangeDays}::text || ' days')::interval AND ${CONFIRMED_OR_LATER}
    GROUP BY o.shop_id, s.name
    ORDER BY gross_revenue DESC
  `)) as unknown as { shop_id: string; shop_name: string; order_count: number; gross_revenue: string }[];

  const orderCount = totals?.order_count ?? 0;
  const grossRevenuePaise = Number(totals?.gross_revenue ?? 0);

  return {
    rangeDays,
    orderCount,
    cancelledOrderCount: totals?.cancelled_order_count ?? 0,
    grossRevenuePaise,
    commissionOwedPaise: Number(totals?.commission_owed ?? 0),
    averageOrderValuePaise: orderCount > 0 ? Math.round(grossRevenuePaise / orderCount) : 0,
    daily: dailyRows.map((r) => ({ date: r.day, orderCount: r.order_count, revenuePaise: Number(r.revenue) })),
    byShop: byShopRows.map((r) => ({
      shopId: r.shop_id,
      shopName: r.shop_name,
      orderCount: r.order_count,
      grossRevenuePaise: Number(r.gross_revenue),
    })),
  };
}
