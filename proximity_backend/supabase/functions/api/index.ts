import { Hono } from "npm:hono";
import { cors } from "npm:hono/cors";

import { healthRoute } from "./routes/health.ts";
import { authRoute } from "./routes/auth.ts";
import { addressesRoute } from "./routes/addresses.ts";
import { categoriesRoute } from "./routes/categories.ts";
import { shopsRoute } from "./routes/shops.ts";
import { ridersRoute } from "./routes/riders.ts";
import { adminRoute } from "./routes/admin.ts";
import { catalogRoute } from "./routes/catalog.ts";
import { wishlistRoute } from "./routes/wishlist.ts";
import { cartRoute } from "./routes/cart.ts";
import { recommendationsRoute } from "./routes/recommendations.ts";
import { checkoutRoute } from "./routes/checkout.ts";
import { paymentsRoute, paymentsWebhookRoute } from "./routes/payments.ts";
import { invoicesRoute } from "./routes/invoices.ts";
import { shopOrdersRoute } from "./routes/shopOrders.ts";

// Deployed as one Edge Function (`supabase functions deploy api`), reachable
// at https://<ref>.supabase.co/functions/v1/api/v1/... -- same shape as
// Baker Ally's index.ts. Flutter's API_BASE_URL points at the `.../api`
// part (see proximity_app/lib/core/config/env.dart).
const app = new Hono().basePath("/api");

// Only proximity_web (Sprint 2's shopkeeper dashboard/admin) is ever
// browser-called -- Flutter never triggers a CORS preflight, and
// /v1/rider/* is mobile-only, so it's deliberately not in this allowlist.
// Explicit origin allowlist, not "*", since these routes carry real bearer
// tokens. Unset ADMIN_WEB_ORIGIN still degrades gracefully (no CORS
// headers at all) until proximity_web's deployed origin is known.
const adminWebOrigin = Deno.env.get("ADMIN_WEB_ORIGIN");
if (adminWebOrigin) {
  app.use("/v1/shop/*", cors({ origin: adminWebOrigin, allowHeaders: ["Authorization", "Content-Type"] }));
  app.use("/v1/admin/*", cors({ origin: adminWebOrigin, allowHeaders: ["Authorization", "Content-Type"] }));
}

app.route("/v1", healthRoute);
app.route("/v1", authRoute);
app.route("/v1", addressesRoute);
app.route("/v1", categoriesRoute);
app.route("/v1", shopsRoute);
app.route("/v1", ridersRoute);
app.route("/v1", adminRoute);
app.route("/v1", catalogRoute);
app.route("/v1", wishlistRoute);
app.route("/v1", cartRoute);
app.route("/v1", recommendationsRoute);
app.route("/v1", checkoutRoute);
app.route("/v1", paymentsRoute);
app.route("/v1", invoicesRoute);
app.route("/v1", shopOrdersRoute);
// Not under authMiddleware, not CORS-restricted -- Razorpay's own server
// calls this directly (server-to-server), never a browser or this app's own
// Flutter client. paymentsRoute (above) still gates its own /order-groups/*
// paths; this stays a separate export specifically so it's obvious at this
// call site that it carries no auth middleware, rather than one route file
// mixing "gated" and "ungated" paths under one easy-to-miss exception.
app.route("/v1", paymentsWebhookRoute);

app.onError((err, c) => {
  console.error(err);
  return c.json({ error: { code: "INTERNAL_ERROR", message: "Something went wrong" } }, 500);
});

Deno.serve(app.fetch);
