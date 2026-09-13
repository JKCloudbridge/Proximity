import { sql } from "npm:drizzle-orm";

// Sprint 12 -- thin wrapper around rpc_cancel_order (migrations/047), same
// "one RPC, typed callers map its error codes" shape lib/riderAssignment.ts
// already established for rpc_assign_rider. Two callers: routes/checkout.ts
// (buyer-initiated, POST /v1/orders/:orderId/cancel) and
// routes/shopOrders.ts (shop-initiated, POST .../orders/:orderId/cancel) --
// both pass a different `actorType` into the SAME RPC rather than each
// re-implementing the state-machine/ledger-reversal/rider-release logic,
// same "one implementation, every caller shares it" reasoning
// lib/orderConfirmation.ts's own header gives for
// confirmPaymentAndGenerateInvoices.
import { db } from "./db.ts";

export type CancelOrderActorType = "buyer" | "shop";

export const CANCEL_ORDER_ERRORS: Record<string, { status: 400 | 403 | 404 | 409; message: string }> = {
  INVALID_ACTOR_TYPE: { status: 400, message: "Invalid cancellation actor" },
  ORDER_NOT_FOUND: { status: 404, message: "Order not found" },
  ORDER_ALREADY_CANCELLED: { status: 409, message: "This order is already cancelled" },
  ORDER_ALREADY_COMPLETED: { status: 409, message: "This order is already completed" },
  ORDER_OUT_FOR_DELIVERY: { status: 409, message: "This order is already out for delivery and can no longer be cancelled" },
  NOT_ORDER_OWNER: { status: 403, message: "This isn't your order" },
  BUYER_CANCEL_WINDOW_CLOSED: {
    status: 409,
    message: "The shop has already started preparing this order -- contact the shop to cancel",
  },
  NOT_SHOP_MANAGER: { status: 403, message: "Only the shop owner or staff can cancel an order" },
};

export async function cancelOrder(orderId: string, actorType: CancelOrderActorType, actorUserId: string, reason?: string) {
  const rows = (await db.execute(
    sql`SELECT * FROM public.rpc_cancel_order(${orderId}::uuid, ${actorType}, ${actorUserId}::uuid, ${reason ?? null})`,
  )) as unknown as Record<string, unknown>[];
  return rows[0];
}
