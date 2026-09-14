import { eq, sql } from "npm:drizzle-orm";

import { db } from "./db.ts";
import { riders } from "../db/schema.ts";
import { sendPushToUser } from "./push/index.ts";

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
//
// Sprint 11 addition -- the rider-assignment-notification decision named in
// SPRINT_PLANNING.md §13/Sprint 9.md's own closing section, now answered:
// a real push fires here too, on BOTH callers, supplementing (not
// replacing) Sprint 9's Realtime subscription -- see Sprint 11.md for the
// full reasoning. Pushing from inside this one function, not duplicated at
// each call site, is deliberate: both callers get the notification with no
// extra code at either, the same "one implementation, every caller shares
// it" shape lib/orderConfirmation.ts itself already is for
// confirmPaymentAndGenerateInvoices. Best-effort and self-contained -- a
// push failure (no token on file, FCM not configured, a transport error)
// never throws out of assignRider() and never undoes or masks the
// assignment itself, which already succeeded by the time this runs.

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
  const assignment: RiderAssignment = {
    orderId: row.order_id,
    riderId: row.rider_id,
    riderFullName: row.rider_full_name,
    riderPhone: row.rider_phone,
  };

  try {
    const [rider] = await db.select({ userId: riders.userId }).from(riders).where(eq(riders.id, assignment.riderId)).limit(1);
    if (rider) {
      await sendPushToUser(rider.userId, {
        title: "New delivery assigned",
        body: "You have a new order to pick up.",
        // `/rider` alone isn't a real route in app_router.dart -- only
        // `/rider/onboarding` is registered (it branches internally into
        // RiderHomeScreen once the rider is verified, per Sprint 9's own
        // design) -- checked directly against the actual router rather
        // than assumed, the same discipline every cross-deployable route
        // reference in this codebase is supposed to hold to.
        data: { type: "rider_assignment", orderId: assignment.orderId, route: "/rider/onboarding" },
      });
    }
  } catch (err) {
    // Same "never let the notification side-channel undo or mask the real
    // operation" rule this file's own header states -- the assignment
    // above already committed; a push failure here is logged, not thrown.
    console.error(`Rider-assignment push failed for order ${assignment.orderId}`, err);
  }

  return assignment;
}

// Sprint 12 -- §8.5's decline/timeout/reassignment gap (migrations/048's own
// header has the full design). Both the rider-initiated decline
// (routes/riders.ts's own new POST .../decline) and the system-initiated
// timeout (migrations/049's cron job) already do their own reassignment
// attempt entirely in SQL (rpc_rider_decline_order/
// rpc_expire_stale_rider_assignments both call rpc_assign_rider directly) --
// this function is NOT part of that path. It exists for the other half of
// migrations/048's design: the shop's own manual "this rider isn't
// responding, find someone else" action, which -- unlike a decline or a
// timeout -- can fire on an order whose rider HAS already accepted, as long
// as they haven't picked up yet (status still 'ready_for_pickup' -- see the
// guard below and migrations/048's header for why 'out_for_delivery' is
// refused outright: reassigning can't help once a different rider already
// physically holds the order). Releases the current rider (if any) back to
// 'available', clears the order's own rider_id, then delegates to
// assignRider() above for the actual search (and its own push
// notification) -- one implementation for "go find this order a rider,"
// not two.
export class OrderNotReassignableError extends Error {
  constructor(public code: string) {
    super(code);
    this.name = "OrderNotReassignableError";
  }
}

export async function forceReassignRider(orderId: string): Promise<RiderAssignment> {
  // Sprint 13 fix -- caught by this sprint's own required independent
  // re-review of Sprint 12, not left in. The pre-fix version ran its
  // read-then-release-then-clear-then-log sequence as four separate,
  // unwrapped `db.execute` statements -- the one cross-table mutation in
  // this entire codebase that wasn't atomic (every other one, from
  // rpc_place_order through rpc_cancel_order/rpc_rider_decline_order, is a
  // single SECURITY DEFINER SQL function for exactly this reason). Two
  // concurrent force-reassign calls on the same order could both read the
  // same `rider_id`, both attempt the release, and both log a
  // 'rider_reassignment_forced' row -- self-correcting in practice
  // (assignRider's own rpc_assign_rider call still serializes correctly via
  // its own FOR UPDATE lock, so no double-assignment could ever result) but
  // a real, disclosed race nonetheless, and an inconsistency with this
  // project's own established "cross-row atomicity is never left to
  // sequential application-code statements" rule. `db.transaction()` was
  // never used anywhere in this backend before this fix -- checked directly
  // against the actually-installed drizzle-orm@0.36.4/postgres-js pairing
  // (`session.js`'s `transaction()` delegates to `postgres`'s own
  // `client.begin()`) before relying on it, same standing rule every other
  // third-party API in this project is held to. It holds one pooled
  // connection for the whole callback, which is exactly what `lib/db.ts`'s
  // own Supavisor transaction-mode pooler is designed to support. The
  // subsequent `assignRider()` call is deliberately left OUTSIDE this
  // transaction -- it's already atomic on its own (rpc_assign_rider), and
  // it does a real HTTP call (the push notification); holding a DB
  // transaction open across an outbound HTTP request for no correctness
  // benefit would be a new, unrelated problem.
  const order = await db.transaction(async (tx) => {
    const orderRows = (await tx.execute(
      sql`SELECT status, delivery_fulfilled_by, rider_id FROM orders WHERE id = ${orderId}::uuid FOR UPDATE`,
    )) as unknown as { status: string; delivery_fulfilled_by: string | null; rider_id: string | null }[];
    const row = orderRows[0];

    if (!row) throw new OrderNotReassignableError("ORDER_NOT_FOUND");
    if (row.delivery_fulfilled_by !== "platform_rider") throw new OrderNotReassignableError("NOT_PLATFORM_RIDER_ORDER");
    if (["completed", "cancelled", "out_for_delivery"].includes(row.status)) {
      throw new OrderNotReassignableError("ORDER_NOT_REASSIGNABLE");
    }

    if (row.rider_id) {
      await tx.execute(sql`UPDATE riders SET status = 'available' WHERE id = ${row.rider_id}::uuid AND status = 'on_delivery'`);
      await tx.execute(sql`UPDATE orders SET rider_id = NULL, updated_at = now() WHERE id = ${orderId}::uuid`);
      await tx.execute(
        sql`INSERT INTO order_status_history (order_id, status, note) VALUES (${orderId}::uuid, 'rider_reassignment_forced', 'Shop requested a different rider')`,
      );
    }

    return row;
  });

  return assignRider(orderId);
}
