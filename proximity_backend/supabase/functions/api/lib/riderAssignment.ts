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
