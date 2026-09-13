# Sprint 11 — Organizer

**Status: development complete, `deno check`/`flutter analyze`-verified, not yet run against a live Supabase project, a real Firebase project, or a physical device.**
Same honest line every prior sprint has drawn, plus this sprint's own exit criteria ("a scheduled recurring list fires a real push notification that deep-links into a pre-filled cart at the right time") is the first in this project to depend on THREE things at once that this session has never had: a live Supabase project for `pg_cron`/`pg_net` to actually run against, a real Firebase project + APNs Auth Key for a push to actually be sendable, and a physical device or emulator to receive one on. Checked directly, not assumed, at the start of this sprint: `supabase projects list` against the linked account still shows only `ChefAndBaker`/`MindScape`/`PiCode`/`LLV` (no Proximity project), no `FCM_SERVICE_ACCOUNT_JSON`/Firebase config exists anywhere in this repo, no `google-services.json`/`GoogleService-Info.plist` exists, and `flutter devices` still has no Android/iOS target (unchanged since Sprint 4). This sprint adds three new migrations (`043`–`045`) on top of the still-unconfirmed `000`–`042`.

Written for a future LLM session (or you) to pick this project back up — if you're that session, start here, then `SPRINT_PLANNING.md` §11's Sprint 11 entry and §4.10, then `Sprint 10.md` for the Order Again "Previously Bought" feed this sprint's own item picker reuses directly, and for the one real bug this sprint's required independent re-review found in it (see below).

This sprint touches `migrations/`, `proximity_backend/` (new lib modules + three new route files, one extended lib file), and `proximity_app/` (mobile) — `proximity_web` is explicitly out of scope, unchanged since Sprint 3.

## Goal (from SPRINT_PLANNING.md §11)

> `recurring_lists`/`recurring_list_items`, `pg_cron` reminder job (reminder + pre-filled-cart mode only, per your confirmed decision), FCM (Android) + APNs (iOS) push wiring. Exit criteria: a scheduled recurring list fires a real push notification that deep-links into a pre-filled cart at the right time.

## Before any of this: the independent re-review of Sprint 10 this sprint's own instructions required

Not just trusting Sprint 10.md's own write-up — re-read the actual new/changed backend routes and lib modules and the new mobile Order Again/Home code with fresh eyes, same discipline every sprint since Sprint 6 has applied to the one before it. **This found one real, genuine bug, not a style nit:**

- **`lib/repeatPurchases.ts`'s `getRepeatProducts` grouped by `pv.id` (variant), not `p.id` (product), while its own header and every caller treat the result as "distinct products."** A product re-ordered under two different variants (e.g. 200g and 500g of the same item, each independently bought on ≥2 separate orders) came back as TWO rows — which let Home's own "≥3 qualifying products" gate (`routes/home.ts`) fire off only 2 real distinct products, directly contradicting Sprint 10's own exit criteria ("an account with fewer does not [see the section]"). It also meant a buyer could see the same product twice in "Previously Bought," once per variant. **Fixed** (before any Sprint 11 code was built on top of it): the query now aggregates at the product level first (a `per_product` CTE, counting `DISTINCT order_id` per product regardless of which variant was in each order), then picks one representative variant per product — the variant actually used on that product's own most recent qualifying order (`DISTINCT ON (product_id) ... ORDER BY created_at DESC`), so "Add to cart" still adds a real, specific variant. `deno check` re-verified clean after the fix. Full before/after reasoning is in the file's own updated comment.
- Everything else re-read clean: `lib/frequentlyBoughtGroups.ts`'s signature-based grouping, `routes/orderAgain.ts`/`routes/home.ts`'s own query shapes, `routes/checkout.ts`'s `GET /order-groups` cursor-pagination fix from Sprint 10's own second pass, and the mobile Order Again/Home screens all held up against the actually-installed APIs their own headers cite. No other issues found.

## What Baker Ally *actually* has for Organizer — checked before writing anything, per the standing rule

§4.10 said `recurring_lists`/`recurring_list_items` "carry over unchanged from v1" — checked directly in `C:\Users\hemin\Desktop\Android Project` before believing that, not assumed:

- **No `recurring_list`/organizer migration, route, or screen exists anywhere in Baker Ally's actual working tree.** Grepped the whole reference project, case-insensitive, for `recurring_list`/`organizer`/`RecurringList` — zero matches in code. Unlike Order Again (`03_order_again_tab.md`), there isn't even a prose spec to design against — nothing beyond §4.10's own two-word gloss ("organizer, reminder-mode") exists anywhere, for this project or Baker Ally.
- `firebase_messaging`/`firebase_core`/`firebase_crashlytics`/`firebase_analytics` ARE pinned in Baker Ally's `pubspec.yaml`, same as `razorpay_flutter` was in Sprint 8 — **checked directly, and confirmed another unused dependency pin**: `grep -ril "firebase_messaging\|FirebaseMessaging"` over `baker_ally_flutter/lib` returns zero matches. Nothing to port from the Flutter side either.
- **One real, proven pattern WAS found and reused**: `migrations/024_AP_restock_notify_trigger.sql` (Baker Ally, read-only reference) is a real, working `pg_net`-calls-an-internal-Edge-Function-route pattern with its shared secret in Supabase Vault — this project's own `migrations/000` had already named this exact pattern as the intended mechanism for "the Organizer reminder job" back in Sprint 0/1. Reused directly (`migrations/045`'s own `net.http_post` call, `routes/internal.ts`), with the same Vault-secret manual step — **note the one thing NOT reused**: Baker Ally's own trigger calls an internal route (`/v1/internal/notify-restock`) that, checked directly, **was never actually implemented anywhere in `baker_ally_backend`** — the trigger SQL is real, the receiving route is not. This project's own `routes/internal.ts` is a real, complete handler, not a second unimplemented stub.

§4.10 itself has been corrected in `SPRINT_PLANNING.md` (the "carries over unchanged" line), same "revisit the reuse map against reality" discipline Sprint 6/8/10 each applied to a different false claim.

## The schema design decision (§4.10 gives no literal DDL, same situation Sprint 3/5/6/7/8 each hit for a different table)

Full reasoning is in `migrations/043`'s own header; short version:
- `recurring_lists`: `name`, `cadence` (`daily`/`weekly`/`biweekly`/`monthly`/`custom_days`), `interval_days` (only for `custom_days`, CHECK-enforced), `time_of_day`, a **materialized, indexed `next_run_at`** (not computed on read — the cron job needs one cheap `WHERE next_run_at <= now() AND is_active` query), `last_run_at`, `is_active`.
- `recurring_list_items`: scoped to a `variant_id` (not a bare product, unlike wishlists) — this list's whole point is pre-filling a real cart via `rpc_add_to_cart`, which needs a variant, not a product.
- Deliberately NOT built: a multi-day-of-week schedule ("every Mon and Thu"). §11's scope is "reminder + pre-filled-cart mode only, no other mode" — a single cadence anchor already covers more scheduling concepts than anything else in this project; a real Phase-2 refinement, not required for the exit criteria.

## What "fires a reminder" means end to end, decided explicitly (§11 asked for this precisely)

1. `pg_cron` invokes `process_due_recurring_lists()` every 10 minutes.
2. Every due list (`next_run_at <= now() AND is_active`) is locked `FOR UPDATE SKIP LOCKED` (two overlapping cron ticks can't double-process one list).
3. **"Pre-filled cart" is real**: every item on the list is upserted into the buyer's own actual `cart_items` via the same `rpc_add_to_cart` (024) the PDP's "Add to cart" button calls — same stock check, same idempotent upsert. One item failing (out of stock, deleted) doesn't stop the rest or the reminder itself, same best-effort-per-item contract `routes/cart.ts`'s own batch-add already established in Sprint 10.
4. `next_run_at` is advanced from its OWN previous value (converted to IST wall-clock, one cadence step added, converted back), **never from `now()`** — so a late-running or backlogged cron tick can't drag a buyer's chosen time-of-day later and later.
5. One `net.http_post` per fired list reaches `routes/internal.ts`'s `POST /v1/internal/send-recurring-reminder`, authenticated by a shared secret (Supabase Vault), which calls `lib/push/fcm.ts` and sends a real FCM v1 push with `data: {type, recurringListId, route: "/cart"}`.

**Accepted trade-off, same one Baker Ally's own restock-notify trigger documented**: `pg_net` is fire-and-forget, no retry. If the Edge Function is down, that tick's reminder is lost — `next_run_at` has already advanced, so it is NOT retried next tick either. Accepted because a missed reminder is a buyer inconvenience, not a money/correctness bug (unlike `rpc_confirm_payment`, which Sprint 8 deliberately wired to BOTH a client path and a webhook because that one can't afford to be lost).

## The timezone convention, decided explicitly

Two different "what time is it in India" approaches already exist in this codebase — `lib/slots.ts` (Sprint 4) hardcodes `+5:30`; `rpc_place_order` (Sprint 7) used `AT TIME ZONE 'Asia/Kolkata'`, flagged there as unconfirmed against a live Postgres tzdata install. This sprint's new `to_ist`/`ist_to_utc`/`ist_now` helpers (`migrations/044`) use the **hardcoded `+5:30` offset** — the dominant, already-multiply-used convention, and India has had no DST since 1945 so a fixed offset isn't an approximation that can go wrong the way it would almost anywhere else. Not re-litigating Sprint 7's own still-unconfirmed bet, just not building a second thing on top of it either.

## The rider-assignment-notification decision (named by Sprint 9.md, answered now)

Sprint 9's own decision #2 built a Supabase Realtime subscription as an explicitly temporary stand-in for rider-assignment notifications, calling out Sprint 11's real push wiring as the sprint that would close the gap — "the honest, disclosed limitation ... not this sprint's job to paper over." Now that real FCM/APNs push exists for the organizer reminder job, the explicit call:

**Decided: real push SUPPLEMENTS the Realtime subscription. It does not replace it.** `lib/riderAssignment.ts`'s `assignRider()` now also calls `sendPushToUser` (best-effort, never throws) on every successful assignment — on BOTH its callers (the automatic post-payment path in `lib/orderConfirmation.ts`, and the shop's manual retry in `routes/shopOrders.ts`), since the notification lives inside the one shared function both already call, not duplicated at each call site. Reasoning:
- Real push is what actually closes Sprint 9's own disclosed gap — "no background/killed-app delivery" — a rider who isn't looking at the app right now is exactly the case that matters for a time-sensitive delivery assignment.
- Realtime stays, deliberately, as the lower-latency channel for a rider who already has the app open, and it's still what drives every status update AFTER the initial assignment (accept, pickup, out-for-delivery) — none of that moved to push this sprint, only the one-time assignment ping gained a second delivery path.
- The token/send infrastructure this decision needs (`users.fcm_token` actually being populated, `sendPushToUser`) didn't exist before this sprint — there was no cheaper way to close this gap earlier, and no new reason surfaced to defer it again now that the infrastructure exists.

## Why manual `FirebaseOptions`, not the FlutterFire CLI

`push_service.dart` builds `FirebaseOptions` from five `.env` values and passes them straight to `Firebase.initializeApp(options: ...)` — no `google-services.json`, no `GoogleService-Info.plist`, no Gradle `google-services` plugin, no Xcode change. Decided, not defaulted to: `flutterfire configure` needs a live `firebase login` session and a real Firebase project, neither of which exists on this machine; and adding the Gradle plugin with no matching `google-services.json` to back it would break the next Android Gradle build for a reason that has nothing to do with any Dart code in this sprint — a much worse failure mode than "push doesn't work yet" given this project has never once run a real Android build. Manual `FirebaseOptions` is a fully supported, documented `firebase_core` path (confirmed by reading the actually-installed 4.14.0 source, not assumed) that needs neither file and costs nothing once real config does land — same five env vars just stop being empty strings.

## What was built

### Migrations (`migrations/`)

| File | Purpose |
|---|---|
| [migrations/043_create_recurring_lists.sql](../../migrations/043_create_recurring_lists.sql) | `recurring_lists`/`recurring_list_items` — fresh design against §4.10's thin prose (no recoverable original anywhere, per above). Own-user RLS, same shape as wishlists. |
| [migrations/044_rpc_recurring_list_crud.sql](../../migrations/044_rpc_recurring_list_crud.sql) | `to_ist`/`ist_to_utc`/`ist_now` (shared IST helpers), `rpc_create_recurring_list` (atomic list+items, computes the first `next_run_at`), `rpc_replace_recurring_list_items` (atomic item-set replace), `rpc_update_recurring_list_schedule` (recomputes `next_run_at` on a cadence/time edit). |
| [migrations/045_rpc_process_due_recurring_lists.sql](../../migrations/045_rpc_process_due_recurring_lists.sql) | `process_due_recurring_lists()` — the cron job itself (pre-fills carts, advances `next_run_at` from its own previous value, fires `net.http_post`) — plus the `cron.schedule(...)` call, every 10 minutes. |

**Not yet run** against a live Supabase project — same standing gap every migration since `000` carries. **Manual step required**, same precedent as `004`'s JWT hook and Baker Ally's own restock trigger: two Supabase Vault secrets (`internal_notify_secret`, `internal_api_base_url`) — full instructions in `migrations/045`'s own header.

### Backend (`proximity_backend/`)

| File | Purpose |
|---|---|
| [lib/push/fcm.ts](../../proximity_backend/supabase/functions/api/lib/push/fcm.ts) | New. The real FCM v1 adapter — OAuth2 JWT-bearer token exchange (Web Crypto RS256 signing, no `google-auth-library`/SDK dependency, same "fetch + Web Crypto instead of the full SDK" call Sprint 8 made for Razorpay), `sendPush(token, message)`. Delivers to both Android and iOS through this one call once an APNs Auth Key is uploaded to the Firebase console — no separate APNs code path. |
| [lib/push/index.ts](../../proximity_backend/supabase/functions/api/lib/push/index.ts) | New. `sendPushToUser(userId, message)` — the one entry point every feature pushes through; reads `users.fcm_token`, clears it on an `UNREGISTERED` result. |
| [lib/riderAssignment.ts](../../proximity_backend/supabase/functions/api/lib/riderAssignment.ts) | Extended — `assignRider()` now also sends a push to the assigned rider (see the decision above). |
| [lib/repeatPurchases.ts](../../proximity_backend/supabase/functions/api/lib/repeatPurchases.ts) | Fixed — see "Before any of this" above; product-level grouping, not variant-level. |
| [routes/push.ts](../../proximity_backend/supabase/functions/api/routes/push.ts) | New. `POST/DELETE /v1/push/token` — finally reads/writes `users.fcm_token` (migrations/001, unused since Sprint 1). |
| [routes/recurringLists.ts](../../proximity_backend/supabase/functions/api/routes/recurringLists.ts) | New. Full CRUD: `GET /v1/recurring-lists`, `GET/PATCH/DELETE /v1/recurring-lists/:id`, `POST /v1/recurring-lists`, `PUT /v1/recurring-lists/:id/items`. |
| [routes/internal.ts](../../proximity_backend/supabase/functions/api/routes/internal.ts) | New. `POST /v1/internal/send-recurring-reminder` — no `authMiddleware`, shared-secret-gated, same trust-boundary shape as `routes/payments.ts`'s webhook route. |
| [db/schema.ts](../../proximity_backend/supabase/functions/api/db/schema.ts) | Added `recurringLists`, `recurringListItems`. |
| [index.ts](../../proximity_backend/supabase/functions/api/index.ts) | Wired `pushRoute`/`recurringListsRoute`/`internalRoute` in. |
| [.env.example](../../proximity_backend/.env.example) | Added `FCM_SERVICE_ACCOUNT_JSON`, `INTERNAL_NOTIFY_SECRET` — both unset (no real Firebase project exists). |

**Verified:** `deno check supabase/functions/api/index.ts` passes clean (re-run after every substantive change, including after both real bugs below were fixed).
**Not verified:** never deployed, never received a real request, never run against a real database. **Never called Firebase's actual servers even once** — no `FCM_SERVICE_ACCOUNT_JSON` exists, same "code-complete, reasoned against real docs, zero bytes exchanged with the real service" gap Sprint 8's Razorpay adapter carried at this same stage.

### Mobile app (`proximity_app/`)

New feature folders `push`, `organizer`.

| File | Purpose |
|---|---|
| [pubspec.yaml](../../proximity_app/pubspec.yaml) | Added `firebase_core: ^4.14.0`, `firebase_messaging: ^16.6.0` (both verified live against pub.dev, and their actually-installed source read directly before writing any code against them — the method signatures this sprint relies on were confirmed, not assumed), `intl: ^0.20.2` (was already resolved transitively; promoted to direct now that `organizer_screen.dart` imports it). |
| [.env.example](../../proximity_app/.env.example), [.env](../../proximity_app/.env) | Added the five Firebase config fields, all client-safe, all unset. |
| [lib/core/config/env.dart](../../proximity_app/lib/core/config/env.dart) | Added the five envied fields; `env.g.dart` regenerated. |
| [lib/core/push/push_service.dart](../../proximity_app/lib/core/push/push_service.dart) | New. `FirebaseOptions` builder, `registerCurrentDevice`/`unregisterCurrentDevice`, notification-tap → in-app-route wiring (`onMessageOpenedApp`/`getInitialMessage`, reading `message.data['route']`), the top-level background handler. |
| [lib/features/push/data/push_repository.dart](../../proximity_app/lib/features/push/data/push_repository.dart), [presentation/providers/push_providers.dart](../../proximity_app/lib/features/push/presentation/providers/push_providers.dart) | New. Mirror `/v1/push/token`; `pushServiceProvider` wires tap-handling on first read. |
| [lib/main.dart](../../proximity_app/lib/main.dart) | `Firebase.initializeApp` (defensively try/caught — never crashes startup on missing config) + background-handler registration before `runApp`. |
| [lib/features/auth/presentation/auth_provider.dart](../../proximity_app/lib/features/auth/presentation/auth_provider.dart) | `AuthNotifier` now registers the push token on the false→true sign-in transition, unregisters on sign-out (before the session itself is torn down). |
| [lib/features/organizer/data/models/recurring_list.dart](../../proximity_app/lib/features/organizer/data/models/recurring_list.dart), [organizer_repository.dart](../../proximity_app/lib/features/organizer/data/organizer_repository.dart) | New. Mirror `/v1/recurring-lists*`. |
| [lib/features/organizer/presentation/providers/organizer_providers.dart](../../proximity_app/lib/features/organizer/presentation/providers/organizer_providers.dart) | New. |
| [lib/features/organizer/presentation/widgets/item_picker_sheet.dart](../../proximity_app/lib/features/organizer/presentation/widgets/item_picker_sheet.dart) | New. Reuses Order Again's own `previouslyBoughtProvider`/"Previously Bought" feed (Sprint 10) as the item-selection source, rather than building a second product-search surface for one screen — see that file's header for why. |
| [lib/features/organizer/presentation/screens/organizer_screen.dart](../../proximity_app/lib/features/organizer/presentation/screens/organizer_screen.dart), [recurring_list_form_screen.dart](../../proximity_app/lib/features/organizer/presentation/screens/recurring_list_form_screen.dart), [recurring_list_detail_screen.dart](../../proximity_app/lib/features/organizer/presentation/screens/recurring_list_detail_screen.dart) | New. List, create, and detail (pause/resume, edit items, delete) screens — no UI spec existed anywhere to port, a fresh design against §4.10's schema-only prose. |
| [lib/core/router/app_router.dart](../../proximity_app/lib/core/router/app_router.dart) | Added `/organizer`, `/organizer/new`, `/organizer/:id` (all `_protectedPaths`). |
| [lib/features/account/presentation/account_screen.dart](../../proximity_app/lib/features/account/presentation/account_screen.dart) | Added a "Recurring Lists" tile — same "no bottom-nav tab of its own" entry-point shape My Wishlist already uses. |
| [android/app/src/main/AndroidManifest.xml](../../proximity_app/android/app/src/main/AndroidManifest.xml) | Added `POST_NOTIFICATIONS` (Android 13+ requires this declared before `requestPermission()` can prompt for it). |
| [ios/Runner/Info.plist](../../proximity_app/ios/Runner/Info.plist) | Added `UIBackgroundModes: remote-notification` — a plain, safe plist edit. **Does NOT enable push on iOS by itself** — see "Not yet built" below for the real Xcode-capability gap this doesn't close. |

**Verified:** `flutter pub get` (checked `firebase_core 4.14.0`/`firebase_messaging 16.6.0`/`intl 0.20.2` actually landed in `pubspec.lock`, not just a success exit code — this machine's standing "verify, don't trust the exit code" rule). `flutter analyze` — 0 errors, 0 warnings; all info-level lints in the same two pre-existing accepted categories every prior sprint has carried (`prefer_initializing_formals`, `use_null_aware_elements`) — one new category (`prefer_final_fields`) surfaced and was fixed outright rather than added to the accepted list, since it was a trivial, real fix (the field in question is never reassigned, only mutated in place).
**Not verified:** never run on an emulator or physical device (none attached this session, unchanged since Sprint 4), never connected to a real backend/database, and — new this sprint — **`Firebase.initializeApp` has never actually succeeded even once**, since every `FIREBASE_*` env value is an empty string; every call site that depends on it (permission request, token fetch, the background handler) is reasoned through against the real installed API but has never executed past the point where `initializeApp` would normally have thrown.

## Bugs caught and fixed during implementation

1. **The Sprint 10 carry-forward bug** — see "Before any of this" above (`lib/repeatPurchases.ts` grouping by variant instead of product). Caught by the required independent re-review, before any Sprint 11 code was built on the feature it affects (Order Again's own item picker, reused directly by this sprint's Organizer item-picker sheet).
2. **A real money/logic bug in `routes/recurringLists.ts`'s own `PATCH` handler, caught by re-reading the file after first writing it, not left in.** The first draft gated `intervalDays` on `body.cadence === "custom_days" || existing.cadence === "custom_days"` — which is wrong the moment a PATCH moves cadence FROM `custom_days` TO something else (e.g. `weekly`) without the caller separately clearing `intervalDays`: the OR condition would still evaluate true (because the OLD cadence was `custom_days`), carrying the stale `intervalDays` value forward into a row whose NEW cadence isn't `custom_days` at all — which `migrations/043`'s own CHECK constraint (`cadence <> 'custom_days' AND interval_days IS NULL`) would then reject outright, a 500 on an otherwise-valid-looking edit. Fixed: gated on the FINAL resolved `cadence` value only (`cadence === "custom_days" ? ... : null`), traced against all four transition directions (custom→custom, custom→other, other→custom, other→other) before calling this fixed.
3. **A silently-broken deep link, caught by checking the actual router before trusting a route string typed from memory.** `lib/riderAssignment.ts`'s first draft pointed the rider-assignment push's `route` field at `/rider` — which isn't a real route in `app_router.dart` at all (only `/rider/onboarding` is registered; it branches internally into `RiderHomeScreen` once the rider is verified, Sprint 9's own design). Checked directly against the actual router file rather than assumed, and fixed before this was called done — `go_router` wouldn't have crashed the app on this (it renders its own unmatched-route page), but the notification tap would have silently failed to reach the rider's assignment screen, exactly the kind of gap this project's own cross-deployable route-reference discipline exists to catch.

## Exit criteria check

| Criterion | Status |
|---|---|
| A scheduled recurring list fires a real push notification | **Cannot be attempted.** No real Firebase project/service-account exists (checked directly, not assumed) and no Supabase project exists to run `pg_cron`/`pg_net` against. Every piece of the chain — schema, cron scheduling logic, the FCM v1 call shape, the shared-secret internal route — is code-complete and reasoned through against real, checked APIs and documentation, but no byte of this has ever executed against a live cron tick or a real Firebase server. |
| ...that deep-links into a pre-filled cart | The cart-prefill step (`rpc_add_to_cart` calls inside `process_due_recurring_lists`) and the notification-tap → `/cart` routing (`push_service.dart`) are both code-complete and traced by hand; the routing half is the one piece of this exit criteria that's checkable by reasoning alone and was (bug #3 above is exactly that check paying off). The cart-prefill half needs a live database to actually prove. |
| ...at the right time | The "advance from the previous `next_run_at`, never from `now()`" logic (migrations/045) was traced by hand against several worked schedules (on-time ticks, a backlogged catch-up, a paused-then-resumed list) — never run against a real `pg_cron` schedule actually firing. |

**What is and isn't checkable by reading/reasoning alone, stated plainly (§11 asked for this explicitly):**
- **Checkable now, and checked:** schema correctness (CHECK constraints traced by hand against every cadence transition, bug #2 above is exactly this kind of trace paying off), the cron-scheduling math (advance-from-previous-value, IST conversion), the deep-link routing logic (bug #3), the FCM v1 request/response shape and OAuth2 JWT construction (checked against Firebase's own current docs, table in Sprint 11's own backend section).
- **Blocked on real infrastructure this session doesn't have:** whether `pg_cron`/`cron.schedule` actually executes this SQL as written on whatever Postgres/pg_cron version the eventual Supabase project runs; whether the hand-rolled RS256 JWT signature is actually accepted by Google's OAuth2 token endpoint; whether a real push actually arrives on a real Android/iOS device and the tap actually opens the app to a pre-filled cart. None of these three can be exercised by reading code, no matter how carefully.

**Bottom line: Sprint 11 is development-complete and internally verified at every layer this project has tooling for** (`deno check`, `flutter analyze`, `flutter pub get` with landed-version verification) — same as every prior sprint, except this one's own exit criteria is uniquely blocked on three different pieces of missing real infrastructure at once, not one.

## What's genuinely unverified (worth being specific about, same treatment every prior sprint's centerpiece work got)

- **`process_due_recurring_lists()` and every RPC this sprint added** have never executed against real Postgres — the standing caveat every RPC since Sprint 1 carries, but worth restating because this one is the first to combine a `FOR UPDATE SKIP LOCKED` loop, a nested per-item exception handler, and a `net.http_post` call inside one function body.
- **The hand-rolled RS256 JWT signing (`lib/push/fcm.ts`)** — built against Web Crypto's documented `RSASSA-PKCS1-v1_5` API and Google's own documented JWT-bearer grant shape, never actually exchanged for a real access token.
- **`FirebaseOptions`-based manual initialization** — confirmed as a real, documented `firebase_core` code path by reading the installed 4.14.0 source directly, never actually completed once (every env value is empty).
- **Android's `POST_NOTIFICATIONS` runtime-permission flow and iOS's whole push pipeline** — neither has ever been exercised on a device; the iOS half additionally has no `Push Notifications` capability/entitlements file at all yet (see "Not yet built").
- **The "pre-filled cart by the time the push is tapped" ordering** — traced by hand (the cart upsert happens before the `net.http_post` call inside the same function, migrations/045), never observed end to end.

## Not yet built (by design, deferred to the sprint that actually needs it, or genuinely Sprint 14's job)

- **The real iOS "Push Notifications" capability (Runner.entitlements + provisioning profile).** Checked directly: no `.entitlements` file exists anywhere in this project yet. This can only be added correctly via Xcode against a real Apple Developer account/provisioning profile — neither exists on this machine. `Info.plist`'s `UIBackgroundModes` key (a plain, safe XML edit, done this sprint) is necessary but nowhere near sufficient; the actual capability toggle is Sprint 14's job, same as every other Xcode-only step this project has already deferred there (§1.1).
- **Multi-day-of-week cadence** ("every Mon and Thu") — a real Phase-2 refinement on top of this sprint's single-cadence-anchor design, not required by §11's own "reminder + pre-filled-cart mode only" scope.
- **A "save this cart/bundle as a recurring list" shortcut** from the Cart or Order Again screens. The create flow exists and is real (`/organizer/new`), but nothing pre-fills it from an existing cart or Order Again group yet — a natural, cheap follow-up once this sprint's own CRUD surface is live, not built this sprint for time.
- **Multi-device push.** `users.fcm_token` is a single column (migrations/001's own original shape) — last-write-wins across devices, same limitation `routes/push.ts`'s own header documents. A real multi-device feature needs an actual `user_push_tokens` table, a genuine schema change, not something to half-build inside this sprint's scope.
- **Foreground notification display via `flutter_local_notifications`.** Every push this project sends carries a `notification` payload, which the OS renders automatically while backgrounded/terminated — the one gap is a push arriving while the app is already open in the foreground, which (per `firebase_messaging`'s own documented behavior) shows nothing without an additional local-notifications package. Not added this sprint — `FirebaseMessaging.onMessage` is available for a future sprint to wire an in-app banner/snackbar to, but doing so wasn't required for this sprint's own exit criteria (a recurring-list reminder is overwhelmingly a backgrounded-app event by its very nature — that's the case this sprint's architecture actually optimizes for).
- **A `recurring_list_runs` audit/ledger table.** Deliberately not built — `next_run_at`/`last_run_at` on `recurring_lists` itself are enough for correctness (a row already fired this tick won't be re-selected, since `next_run_at` has already advanced past `now()`), and §11's own named scope was two tables, not three.

## What you need to run

Same list Sprint 3–10.md carried, plus three new files:

```
000_enable_extensions.sql
001_create_users.sql
002_create_addresses.sql
003_create_categories.sql
004_create_custom_jwt_claims_hook.sql   -- plus its one manual step: Authentication -> Hooks -> select custom_access_token_hook
005_rpc_set_default_address.sql
006_create_shops.sql
007_create_shop_team_members.sql
008_create_shop_business_hours.sql
009_create_shop_media.sql
010_create_shop_sub_categories.sql
011_create_riders.sql
012_create_platform_settings.sql
013_create_shop_blackout_dates.sql
014_rpc_create_shop.sql
015_rpc_create_rider_profile.sql
016_create_rider_documents_bucket.sql
017_create_products.sql
018_create_product_variants.sql
019_create_product_images.sql
020_create_product_images_bucket.sql
021_create_wishlists.sql
022_create_carts.sql
023_create_cart_items.sql
024_rpc_add_to_cart.sql
025_create_product_cross_sell.sql
026_create_discounts.sql
027_create_order_groups.sql
028_create_orders.sql
029_create_order_items.sql
030_create_order_status_history.sql
031_create_shop_ledger_entries.sql
032_rpc_place_order.sql
033_add_shops_invoice_seq.sql
034_create_invoices.sql
035_create_invoices_bucket.sql
036_rpc_confirm_payment.sql
037_rpc_generate_invoice.sql
038_add_rider_order_rls.sql
039_rpc_assign_rider.sql
040_rpc_shop_advance_order_status.sql
041_rpc_rider_accept_order.sql
042_rpc_rider_update_status.sql
043_create_recurring_lists.sql          -- Sprint 11, new
044_rpc_recurring_list_crud.sql         -- Sprint 11, new
045_rpc_process_due_recurring_lists.sql -- Sprint 11, new
```

If `000`–`042` are already confirmed applied, only **`043`–`045`** are new and need running, strictly in that order — plus the two Supabase Vault secrets `045`'s own header lists (`internal_notify_secret`, `internal_api_base_url`), and setting `INTERNAL_NOTIFY_SECRET`/`FCM_SERVICE_ACCOUNT_JSON` as Edge Function secrets once a real Firebase service account exists.

**Given this sprint's exit criteria cannot be attempted at all without a real Supabase project (for `pg_cron`) AND a real Firebase project (for the push to send) AND a physical device (to receive it) — all three together, not just one — getting all three is now the single highest-leverage unblock across this entire project, more than any prior sprint's own version of this recommendation.**

## What Sprint 12 needs from you before it can be verified either

Same shape as every prior sprint: Sprint 12 (shopkeeper analytics, ledger, admin completion, cancellation & reversal — per Sprint 10's own scheduling decision) can be written without any live infrastructure, but proving any of it — this sprint's Organizer work included — needs the migrations actually applied, a real Firebase project + APNs key, real Razorpay test credentials (still outstanding since Sprint 8), and a physical device or working emulator this session still doesn't have access to.

---

**Waiting for your go-ahead before starting Sprint 12**, per your instruction to stop at sprint boundaries.
