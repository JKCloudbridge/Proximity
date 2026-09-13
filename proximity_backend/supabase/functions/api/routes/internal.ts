import { Hono } from "npm:hono";

import { timingSafeEqual } from "../lib/payments/crypto.ts";
import { sendPushToUser } from "../lib/push/index.ts";

// Sprint 11 -- the one route migrations/045's pg_net call reaches, same
// "a different trust boundary for a different kind of caller" shape
// routes/payments.ts's own webhook route already established (§5.1):
// no authMiddleware -- Postgres's own net.http_post call never carries a
// Supabase user JWT, and isn't meant to -- the shared-secret header check
// below IS this route's authentication. Deliberately its own file/export
// (not folded into routes/payments.ts, which already has exactly one
// no-auth webhook route for a different caller) so "this route group
// carries no authMiddleware" stays obvious at the mount site in index.ts,
// same reason that file's own header names the webhook route a separate
// export in the first place.
//
// The shared secret itself is never generated or stored by this codebase --
// migrations/045's own header documents the one manual step (a Vault
// secret + a matching `supabase secrets set INTERNAL_NOTIFY_SECRET=...`)
// that makes this route (and the pg_net call that hits it) actually work.
// Until INTERNAL_NOTIFY_SECRET is set, every request here is rejected --
// fails closed, not open.
export const internalRoute = new Hono();

type SendRecurringReminderBody = {
  recurringListId?: string;
  userId?: string;
  listName?: string;
};

internalRoute.post("/internal/send-recurring-reminder", async (c) => {
  const configuredSecret = Deno.env.get("INTERNAL_NOTIFY_SECRET");
  const providedSecret = c.req.header("x-internal-secret");
  if (!configuredSecret || !providedSecret || !timingSafeEqual(providedSecret, configuredSecret)) {
    return c.json({ error: { code: "UNAUTHORIZED", message: "Invalid or missing internal secret" } }, 401);
  }

  const body = (await c.req.json().catch(() => null)) as SendRecurringReminderBody | null;
  if (!body?.userId || !body?.recurringListId) {
    return c.json({ error: { code: "INVALID_BODY", message: "userId and recurringListId are required" } }, 400);
  }

  // Best-effort, same contract sendPushToUser's own header documents --
  // this route always returns 200 with the outcome in the body rather than
  // a 4xx/5xx for "no token on file" or "FCM rejected it," since net.http_post
  // (migrations/045) is fire-and-forget and never inspects the response
  // beyond "did the HTTP call itself go through."
  const result = await sendPushToUser(body.userId, {
    title: "Time to restock",
    body: body.listName ? `Your "${body.listName}" items are waiting in your cart.` : "Your usual items are waiting in your cart.",
    data: { type: "recurring_list_reminder", recurringListId: body.recurringListId, route: "/cart" },
  });

  return c.json({ data: result });
});
