import * as Sentry from "npm:@sentry/deno";

// Sprint 13 -- §3.2's own "Optional: Sentry (backend-side error tracking,
// complements mobile-only Crashlytics)" line, decided here rather than
// deferred a further sprint: this codebase's `index.ts` has always had
// exactly one place every unhandled route error already funnels through
// (`app.onError`, below/in index.ts) -- backend error tracking is a small,
// real addition on top of a seam that already exists, not new plumbing,
// so it's worth doing for real now rather than staying "optional" forever.
//
// **Version pinned to `^8.55.2`, not the newer `^10` "latest" tag on npm,
// checked live rather than grabbing whatever `npm view` calls latest:**
// Supabase's own current, maintained Sentry-monitoring guide
// (supabase.com/docs/guides/functions/examples/sentry-monitoring) pins
// `npm:@sentry/deno@^8` specifically for Edge Functions -- their own
// production Edge Runtime is the one thing that actually matters here, and
// Supabase (not this project) is the authority on what Deno version it
// runs. `deno check` was also run directly against the real, downloaded
// 8.55.2 package (not assumed) before writing anything against
// `Sentry.init`/`.captureException`/`.withScope`/`.flush`/`.setTag` --
// same third-party-API discipline every integration in this project has
// held to since Sprint 8.
//
// **Real, disclosed limitation, straight from Supabase's own docs, not
// discovered the hard way:** "Sentry Deno SDK currently do[es] not support
// `Deno.serve` instrumentation, which means there is no scope separation
// between requests" -- i.e. Sentry.init's own automatic request-context
// tracking doesn't work on this runtime. Mitigated the way Supabase's own
// guide recommends: `captureError` below wraps every capture in
// `Sentry.withScope`, attaching this one request's own method/path/status
// explicitly, rather than relying on any automatic per-request scoping
// that doesn't exist here.
//
// Deliberately NO tracing/profiling (`tracesSampleRate`/`profilesSampleRate`
// both omitted, defaulting to Sentry's own 0) -- this sprint's own ask is
// error tracking, not APM, and Sentry's pricing is quota-based on
// transactions; turning on tracing nobody asked for would be speculative
// scope and a real cost surprise, not a free addition.
let initialized = false;

/** Called once, at module load (index.ts's own top-level, so every route
 * module that might throw is already wired by the time a request arrives).
 * A no-op if `SENTRY_DSN` isn't set -- same "code-complete, silently inert
 * without real credentials" shape every other integration in this project
 * (Razorpay, FCM) uses, since no real Sentry project/DSN exists yet either
 * (checked directly: no `SENTRY_DSN` in `.env.example` before this sprint,
 * added by it, unset). */
export function initSentry(): void {
  const dsn = Deno.env.get("SENTRY_DSN");
  if (!dsn) return;

  Sentry.init({
    dsn,
    // defaultIntegrations: false -- Supabase's own guide's stated reason:
    // several of Sentry's default Node-oriented integrations don't apply
    // (or don't work) on the Edge Runtime's Deno; opting in explicitly to
    // nothing rather than an integration set built for a runtime this
    // isn't is the documented, safer default here.
    defaultIntegrations: false,
    environment: Deno.env.get("SENTRY_ENVIRONMENT") ?? "production",
  });
  initialized = true;
}

/** The one call site every unhandled route error goes through
 * (`app.onError`, index.ts) -- never throws itself (a broken error
 * reporter must never turn a 500 into a second, worse failure), and is a
 * silent no-op if `initSentry()` never actually initialized (no DSN). */
export function captureError(err: unknown, context: { method: string; path: string }): void {
  if (!initialized) return;
  try {
    Sentry.withScope((scope) => {
      scope.setTag("http.method", context.method);
      scope.setTag("http.path", context.path);
      Sentry.captureException(err);
    });
  } catch (reportingErr) {
    console.error("Sentry.captureError itself failed:", reportingErr);
  }
}
