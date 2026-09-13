import { Hono } from "npm:hono";
import { zValidator } from "npm:@hono/zod-validator";
import { z } from "npm:zod";
import { eq } from "npm:drizzle-orm";

import { authMiddleware, type AuthEnv } from "../middleware/auth.ts";
import { db } from "../lib/db.ts";
import { users } from "../db/schema.ts";

// Sprint 11 -- the route that finally reads/writes users.fcm_token
// (migrations/001), an unused placeholder column since Sprint 1. Own-user
// data (§5.2), same authenticated-only shape as wishlist.ts -- there's no
// meaningful guest version of "register this device's push token."
export const pushRoute = new Hono<AuthEnv>();

pushRoute.use("/push/*", authMiddleware);

const registerTokenSchema = z.object({ fcmToken: z.string().min(1) });

// Called once after FirebaseMessaging.instance.requestPermission() grants
// access and getToken() resolves (push_service.dart), and again from
// onTokenRefresh -- Firebase can rotate a device's token at any time (app
// reinstall, Firebase-initiated refresh), and a stale token left in
// users.fcm_token would just silently stop receiving pushes with no error
// anywhere to notice it by. Plain last-write-wins (no per-device token
// list) -- one user signed into two devices will only receive pushes on
// whichever registered most recently; §11's own scope (one recurring-list
// reminder, one rider-assignment ping) doesn't need multi-device fan-out,
// and `users.fcm_token` is a single TEXT column, not a table, per its own
// Sprint 1 DDL -- building multi-device support would need a real schema
// change, not something to half-do inside this route.
pushRoute.post("/push/token", zValidator("json", registerTokenSchema), async (c) => {
  const authUser = c.get("user");
  const { fcmToken } = c.req.valid("json");

  await db.update(users).set({ fcmToken, updatedAt: new Date() }).where(eq(users.id, authUser.id));
  return c.json({ data: { registered: true } });
});

// Called on sign-out (auth_provider.dart) -- a device that's no longer
// signed in as this user shouldn't keep receiving their pushes. Clears
// unconditionally rather than checking the token matches the caller's own
// current value first -- the caller is already proven to be this user via
// authMiddleware, and there's no multi-device list to accidentally clear
// someone else's entry from (see the single-column note above).
pushRoute.delete("/push/token", async (c) => {
  const authUser = c.get("user");
  await db.update(users).set({ fcmToken: null, updatedAt: new Date() }).where(eq(users.id, authUser.id));
  return c.json({ data: { registered: false } });
});
