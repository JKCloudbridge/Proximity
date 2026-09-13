import { eq } from "npm:drizzle-orm";

import { db } from "../db.ts";
import { users } from "../../db/schema.ts";
import { sendPush, type PushMessage, FcmNotConfiguredError } from "./fcm.ts";

export { FcmNotConfiguredError } from "./fcm.ts";
export type { PushMessage } from "./fcm.ts";

export type SendPushToUserResult =
  | { sent: true }
  | { sent: false; reason: "no_token" | "not_configured" | "send_failed" };

/**
 * The one entry point every feature that needs to push a user should call
 * -- reads `users.fcm_token` (migrations/001's long-unused placeholder,
 * finally read for real), sends via lib/push/fcm.ts, and clears the token
 * on an `unregistered` result so a dead token doesn't get retried forever
 * (an uninstalled app, a token Firebase itself invalidated). Two real
 * callers this sprint: routes/internal.ts's recurring-reminder handler,
 * and lib/riderAssignment.ts's rider-assignment ping (§11's own "does the
 * rider path move to real push too" decision -- see Sprint 11.md for the
 * full reasoning, short version: yes, as a supplement to Sprint 9's
 * Realtime subscription, not a replacement).
 *
 * Never throws for an expected "can't deliver" outcome (no token on file,
 * FCM not configured, FCM itself rejected the send) -- every caller here
 * treats a push as best-effort exactly the way lib/riderAssignment.ts's own
 * rider-assignment RPC call already does for the same reason: a failed
 * notification is never a reason to fail the business operation it's
 * attached to.
 */
export async function sendPushToUser(userId: string, message: PushMessage): Promise<SendPushToUserResult> {
  const [user] = await db.select({ fcmToken: users.fcmToken }).from(users).where(eq(users.id, userId)).limit(1);
  if (!user?.fcmToken) return { sent: false, reason: "no_token" };

  try {
    const result = await sendPush(user.fcmToken, message);
    if (result.ok) return { sent: true };

    if (result.unregistered) {
      await db.update(users).set({ fcmToken: null, updatedAt: new Date() }).where(eq(users.id, userId));
    }
    return { sent: false, reason: "send_failed" };
  } catch (err) {
    if (err instanceof FcmNotConfiguredError) return { sent: false, reason: "not_configured" };
    throw err;
  }
}
