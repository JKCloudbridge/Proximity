import { sql } from "npm:drizzle-orm";

import { db } from "./db.ts";

// Sprint 9 -- the thin TS wrapper around rpc_assign_rider (migrations/039).
// Two callers, deliberately different failure handling for the SAME RPC and
// the SAME thrown error (see migrations/039's own header for the full
// "when does this fire" decision):
//   * lib/orderConfirmation.ts's confirmPaymentAndGenerateInvoices --
//     automatic, best-effort, one order among possibly several in a group.
//     A NO_RIDER_AVAILABLE (or any other) failure here must not undo the
//     payment confirmation that already committed, and must not block a
//     sibling shop's own invoice/assignment -- caught and logged there, not
//     here, same "best-effort per order" shape invoice generation already
//     uses.
//   * routes/shopOrders.ts's POST .../assign-rider -- an explicit shop
//     action expecting a real, typed error response (e.g. "no riders
//     available nearby right now") when this throws -- that route maps
//     ASSIGN_RIDER_ERRORS itself, the same PLACE_ORDER_ERRORS-table pattern
//     checkout.ts already established for rpc_place_order's error codes.

export interface RiderAssignment {
  orderId: string;
  riderId: string;
  riderFullName: string;
  riderPhone: string;
}

interface RawAssignRiderRow {
  order_id: string;
  rider_id: string;
  rider_full_name: string;
  rider_phone: string;
}

export async function assignRider(orderId: string): Promise<RiderAssignment> {
  const rows = (await db.execute(
    sql`SELECT * FROM public.rpc_assign_rider(${orderId}::uuid)`,
  )) as unknown as RawAssignRiderRow[];
  const row = rows[0];
  return {
    orderId: row.order_id,
    riderId: row.rider_id,
    riderFullName: row.rider_full_name,
    riderPhone: row.rider_phone,
  };
}
