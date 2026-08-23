import { Hono } from "npm:hono";
import { cors } from "npm:hono/cors";

import { healthRoute } from "./routes/health.ts";
import { authRoute } from "./routes/auth.ts";
import { addressesRoute } from "./routes/addresses.ts";
import { categoriesRoute } from "./routes/categories.ts";

// Deployed as one Edge Function (`supabase functions deploy api`), reachable
// at https://<ref>.supabase.co/functions/v1/api/v1/... -- same shape as
// Baker Ally's index.ts. Flutter's API_BASE_URL points at the `.../api`
// part (see proximity_app/lib/core/config/env.dart).
const app = new Hono().basePath("/api");

// Only proximity_web (Sprint 2+, shopkeeper dashboard/admin) is ever
// browser-called -- Flutter never triggers a CORS preflight. Explicit
// origin allowlist, not "*", since these routes carry real bearer tokens.
// Unset ADMIN_WEB_ORIGIN is fine for Sprint 1 -- nothing under /v1/shop/*
// or /v1/admin/* exists yet.
const adminWebOrigin = Deno.env.get("ADMIN_WEB_ORIGIN");
if (adminWebOrigin) {
  app.use("/v1/shop/*", cors({ origin: adminWebOrigin, allowHeaders: ["Authorization", "Content-Type"] }));
  app.use("/v1/admin/*", cors({ origin: adminWebOrigin, allowHeaders: ["Authorization", "Content-Type"] }));
}

app.route("/v1", healthRoute);
app.route("/v1", authRoute);
app.route("/v1", addressesRoute);
app.route("/v1", categoriesRoute);

app.onError((err, c) => {
  console.error(err);
  return c.json({ error: { code: "INTERNAL_ERROR", message: "Something went wrong" } }, 500);
});

Deno.serve(app.fetch);
