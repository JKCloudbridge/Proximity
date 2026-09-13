# Sprint 12 — Shopkeeper Analytics, Ledger, Admin Completion, Cancellation & Reversal

**Status: development complete, `deno check`/`flutter analyze`/`npm run build`+`lint`+`audit`-verified, not yet run against a live Supabase project, a physical device, or a real Razorpay/Firebase account.**
Same honest line every prior sprint has drawn. Checked directly at the start of this sprint, not assumed: `supabase projects list` against the linked account still shows only `ChefAndBaker`/`MindScape`/`PiCode`/`LLV` (no Proximity project); no `proximity_backend/.env` exists; no `google-services.json`/`GoogleService-Info.plist` exists; `flutter devices` still lists only Windows-desktop/Chrome/Edge (this project's `android`/`ios`-only `flutter create` target means none of those three count as a real device anyway). Nothing about any of that has changed since Sprint 11.md's own check. This sprint adds four new migrations (`046`–`049`) on top of the still-unconfirmed `000`–`045`.

Written for a future LLM session (or you) to pick this project back up — if you're that session, start here, then `SPRINT_PLANNING.md` §11's Sprint 12 entry and §8.4/§8.6, then `Sprint 11.md` for the Organizer/push work this sprint's own required re-review re-confirmed (below) and for the exact gap (rider decline/reassignment + cancellation-triggered ledger reversal) Sprint 9/10 each flagged and Sprint 10 gave this sprint its own named line for.

This sprint touches `migrations/`, `proximity_backend/` (new lib modules + extensions to five route files), `proximity_web/` (new dashboard/admin pages — the first `proximity_web` work since Sprint 3's catalog dashboard), and `proximity_app/` (mobile — buyer/shop/rider cancellation and decline UI).

## Goal (from SPRINT_PLANNING.md §11)

> Sales summary aggregation views, a real ledger view (§8.4) on both proximity_web's shopkeeper dashboard and a platform-wide admin view, admin: platform_settings editor UI (delivery fee/slot window, §4.6/§8.6), per-shop platform_commission_pct override, discount authoring UI. A real cancellation flow — buyer-initiated (before a shop accepts) and shop-initiated (before dispatch/handoff) — a legal orders.status transition into cancelled from more than just rpc_place_order's own pre-payment paths. shop_ledger_entries reversal for both payment paths — design and document exactly how a reversal entry is represented. Rider decline/reassignment — design the decline/timeout/reassignment flow explicitly. Exit criteria: a shopkeeper can see their own real revenue numbers and outstanding ledger balance; admin can change the platform delivery fee and see it reflected on the next new order; a cancelled order (buyer- or shop-initiated, at least one of each payment mode) leaves correct, reversed ledger entries and — if a rider was involved — a rider who's actually back to available, not stuck on_delivery.

## The independent re-review of Sprint 11 this sprint's own instructions required

Re-read the actual new push/organizer backend routes and lib modules and the new mobile push/organizer code with fresh eyes, not just Sprint 11.md's own self-report — same discipline every sprint since Sprint 6 has applied to the one before it:

- **`lib/push/fcm.ts`, `lib/push/index.ts`, `routes/internal.ts`, `routes/recurringLists.ts`, `migrations/044`/`045`** — read in full. All hold up: the FCM v1 request shape and OAuth2 JWT-bearer construction are correct against the cited docs; `process_due_recurring_lists()`'s per-list/per-item exception isolation, `FOR UPDATE SKIP LOCKED`, and "advance from the previous value, never `now()`" logic are all structurally sound; `routes/recurringLists.ts`'s cadence-transition PATCH logic (the Sprint 11 bug it fixed) is correctly gated on the FINAL resolved cadence, re-verified by tracing all four transition directions again. No new issues found.
- **`lib/riderAssignment.ts`, `lib/repeatPurchases.ts`** — the Sprint 10 carry-forward bug fix (product-level, not variant-level, grouping) still holds on re-read; the Sprint 11 rider-push addition correctly wraps its own push call in a try/catch that never masks the underlying assignment. **One real, if minor, doc/code drift found**: `push_service.dart`'s own header comment said the rider-assignment push's `route` field is `/rider` — but the actual code (`lib/riderAssignment.ts`) already correctly used `/rider/onboarding` (Sprint 11's own bug #3 fix). The comment was simply never updated after that fix landed. Not a live bug (the comment doesn't execute), but exactly the kind of drift that misleads a future reader — fixed as part of this sprint's own edits to that file's neighborhood (`riderAssignment.ts`'s header now states the real route explicitly, matching the code).
- **Mobile organizer/push screens** (`organizer_screen.dart`, `recurring_list_form_screen.dart`, `recurring_list_detail_screen.dart`, `push_service.dart`, `item_picker_sheet.dart`) — read cleanly against the actually-installed `firebase_core`/`firebase_messaging` APIs those files' own headers cite. No new issues found.

Nothing here contradicts Sprint 11.md's own write-up — this re-review confirms it (plus one harmless doc-drift fix), same as Sprint 10's own re-review of Sprint 9 came back clean.

## The three design decisions this sprint was explicitly asked to make

### 1. How a ledger reversal is represented — a new offsetting row, never a status mutation on the original

Full reasoning is in [migrations/046](../../migrations/046_add_shop_ledger_reversal.sql)'s own header; short version: two new `entry_type` values (`payout_reversal`/`commission_reversal`), a nullable self-referencing `reverses_entry_id` naming exactly which original row a reversal cancels, and a CHECK tying the two together. **Never** a mutation of the original `payout_due`/`commission_due` row's `amount` or `status` — this project's own established convention (`order_items`, `invoices` — both immutable snapshots, never edited after the fact) extends here for the same reason: a real ledger reverses via a contra-entry, not by rewriting history, and a `status='settled'` row that's later cancelled needs to record a claw-back obligation, not have its own past falsified. The outstanding balance is always `SUM(due) - SUM(reversal)` — one formula ([lib/ledger.ts](../../proximity_backend/supabase/functions/api/lib/ledger.ts)), no special-casing whether the original had already settled.

### 2. The cancellation state machine — buyer window vs. shop window, precisely

Full reasoning in [migrations/047](../../migrations/047_rpc_cancel_order.sql)'s own header. This schema has no distinct "shop accepted" status (`orders.status` moves `pending → confirmed` automatically the instant payment resolves, for both payment paths — migrations/036). So "before a shop accepts" is defined as: **before the shop's first real action, `preparing`.**

| Actor | Legal window | Refused |
|---|---|---|
| Buyer | `pending`, `confirmed` | `preparing`+ (go through the shop), `out_for_delivery`, `completed`, `cancelled` |
| Shop (`owner`/`staff` only, not `delivery`) | `pending`, `confirmed`, `preparing`, `ready_for_pickup` | `out_for_delivery` (dispatched), `completed`, `cancelled` |

Both actors are refused with a distinct, typed error once already `cancelled`/`completed`/`out_for_delivery` — never a silent idempotent no-op, same "tell the truth about what already happened" choice `rpc_shop_advance_order_status`'s own `ORDER_ALREADY_FINAL` makes. Authorization is checked **before** any status check (fixed during this sprint's own second pass — see "Bugs caught" below) — same ordering `rpc_shop_advance_order_status` already established, and the reason matters: checking status first would tell an unauthorized caller whether someone else's order is already cancelled before ever telling them they have no business asking.

Cancellation is deliberately per-`orders` row (one shop's own sub-order), never per-`order_groups` — §4.8's redesign never gave a multi-shop checkout a single shared lifecycle, so a buyer with a two-shop cart who wants out of both cancels twice, once per shop's card — the same "a group is one `orders` row" precedent Sprint 10's Order Again feature already established for this exact data shape.

### 3. Rider decline/timeout/reassignment — the full flow, and its real boundary

Full reasoning in [migrations/048](../../migrations/048_rider_decline_and_reassignment.sql)'s header. Three real questions, all answered explicitly:

- **Does a declined assignment retry `rpc_assign_rider` immediately?** Yes — a rider-initiated decline (`rpc_rider_decline_order`) frees the rider, logs `rider_declined`, and immediately calls `rpc_assign_rider` again with an exclusion list (a new `order_rider_declines` table, not parsed out of free-text history) so the same rider is never re-offered the order they just turned down.
- **Is there a rider-side timeout at all?** Yes, a real one — `rpc_expire_stale_rider_assignments` runs on `pg_cron` every 2 minutes, finds any order assigned for more than 5 minutes with no `rider_accepted` history row, and handles it via the exact same decline-and-reassign path (logged as `rider_assignment_timed_out`, a distinct word from `rider_declined` so the two stay distinguishable after the fact).
- **Does the order fall back to the shop's manual `assign-rider` retry when reassignment finds nobody?** Yes — unchanged from Sprint 9's own documented fallback; a decline or timeout that can't immediately find a replacement just leaves `rider_id = NULL`, exactly the state the existing manual retry already knows how to recover from.

**The one thing explicitly NOT solved, and why:** once a rider has genuinely picked up an order (`orders.status = 'out_for_delivery'`), neither a decline, a timeout, nor the shop's own `force`-flagged manual reassign (extended this sprint to also work on an already-assigned, not-yet-dispatched order) can do anything — a *different* rider has nothing to collect from the shop once the original one already has the package. That failure mode is a real-world logistics escalation (call the rider, send someone after them) with no software fix this schema can express; inventing a staleness threshold for "the rider might be stuck in traffic vs. unreachable" would be guessing at an SLA nobody specified. Named here plainly as the actual boundary of this sprint's own scope, not left to surface as a surprise `409` later.

## What was built

### Migrations (`migrations/`)

| File | Purpose |
|---|---|
| [migrations/046_add_shop_ledger_reversal.sql](../../migrations/046_add_shop_ledger_reversal.sql) | `shop_ledger_entries` gets `reverses_entry_id` + two new `entry_type` values (`payout_reversal`/`commission_reversal`) + a shape CHECK + a partial unique index (at most one reversal per original entry). Design decision #1 above, in full. |
| [migrations/047_rpc_cancel_order.sql](../../migrations/047_rpc_cancel_order.sql) | `rpc_cancel_order(order_id, actor_type, actor_user_id, reason)` — the whole cancellation flow atomically: status transition, rider release, and ledger reversal (mirrors every existing `payout_due`/`commission_due` row for the order, never recomputes the commission/discount math from scratch). Design decision #2 above. |
| [migrations/048_rider_decline_and_reassignment.sql](../../migrations/048_rider_decline_and_reassignment.sql) | `order_rider_declines` table; `rpc_assign_rider` extended with an exclusion-list parameter (`DROP`+`CREATE`, not `CREATE OR REPLACE` — a new parameter changes the function's own identity); `rpc_rider_decline_order`. Design decision #3 above. |
| [migrations/049_rpc_expire_stale_rider_assignments.sql](../../migrations/049_rpc_expire_stale_rider_assignments.sql) | `rpc_expire_stale_rider_assignments()` — the timeout half of decision #3, `pg_cron`-scheduled every 2 minutes. |

**Not yet run.** See "What you need to run" below.

### Backend (`proximity_backend/`)

| File | Purpose |
|---|---|
| [lib/ledger.ts](../../proximity_backend/supabase/functions/api/lib/ledger.ts) | New. `getShopLedgerBalance`/`getPlatformLedgerBalances` (the one net-of-reversals balance formula, shared by both the shop and admin ledger views) + `listLedgerEntries` (the itemized feed underneath either). |
| [lib/salesSummary.ts](../../proximity_backend/supabase/functions/api/lib/salesSummary.ts) | New. `getShopSalesSummary`/`getPlatformSalesSummary` — live, bounded (`days`-windowed) aggregation, same "documented, not unlimited" scope cut every prior sprint's own aggregate query has made. Revenue = `orders.total` on orders that reached at least `confirmed`; commission-owed re-derives `rpc_confirm_payment`'s own formula for display only (the real obligation always lives in `shop_ledger_entries`). |
| [lib/cancellation.ts](../../proximity_backend/supabase/functions/api/lib/cancellation.ts) | New. Thin wrapper + typed error map around `rpc_cancel_order`, shared by both call sites (checkout.ts, shopOrders.ts). |
| [lib/riderAssignment.ts](../../proximity_backend/supabase/functions/api/lib/riderAssignment.ts) | Extended: `forceReassignRider`/`OrderNotReassignableError` — the shop's manual "find someone else" action on an order that already has a rider (design decision #3's own boundary). |
| [db/schema.ts](../../proximity_backend/supabase/functions/api/db/schema.ts) | Added `shopLedgerEntries.reversesEntryId`, `orderRiderDeclines`. |
| [routes/checkout.ts](../../proximity_backend/supabase/functions/api/routes/checkout.ts) | Added `POST /orders/:orderId/cancel` (buyer). |
| [routes/shopOrders.ts](../../proximity_backend/supabase/functions/api/routes/shopOrders.ts) | Added `POST .../orders/:orderId/cancel` (shop), `GET .../analytics/sales-summary`, `GET .../ledger`; extended `POST .../assign-rider` with an optional `force` flag. |
| [routes/riders.ts](../../proximity_backend/supabase/functions/api/routes/riders.ts) | Added `POST /rider/riders/me/orders/:orderId/decline`. |
| [routes/admin.ts](../../proximity_backend/supabase/functions/api/routes/admin.ts) | Added `GET/PATCH /admin/platform-settings`, `PATCH /admin/shops/:id/commission`, `GET/POST/PATCH /admin/discounts*`, `GET /admin/ledger`, `GET /admin/ledger/entries`, `GET /admin/analytics/sales-summary`. |

**Verified:** `deno check supabase/functions/api/index.ts` passes clean (re-run after every substantive change, including after the authorization-ordering fix below).
**Not verified:** never deployed, never received a real request, never run against a real database — same standing gap every prior sprint's backend work has carried. `rpc_cancel_order`/`rpc_rider_decline_order`/`rpc_expire_stale_rider_assignments` have never executed against real Postgres.

### Web app (`proximity_web/`) — its first new work since Sprint 3

| File | Purpose |
|---|---|
| [lib/types.ts](../../proximity_web/lib/types.ts) | Added `PlatformSetting`, `Discount`, `ShopLedgerBalance`, `PlatformLedgerRow`, `LedgerEntry`, `ShopSalesSummary`, `PlatformSalesSummary`. |
| [lib/nav.ts](../../proximity_web/lib/nav.ts) | Dashboard nav gains Sales/Ledger; admin nav gains Platform settings/Discounts/Ledger. |
| [app/dashboard/sales/page.tsx](../../proximity_web/app/dashboard/sales/page.tsx) + [sales-client.tsx](../../proximity_web/app/dashboard/sales/sales-client.tsx) | §8.4's sales summary — revenue/orders/AOV/cancellations, a daily bar chart, a 7/30/90-day range picker. |
| [app/dashboard/ledger/page.tsx](../../proximity_web/app/dashboard/ledger/page.tsx) + [ledger-client.tsx](../../proximity_web/app/dashboard/ledger/ledger-client.tsx) | §8.4's real ledger view — net payout/commission balance, itemized entries (reversal rows visibly labeled), load-more pagination. |
| [app/admin/settings/page.tsx](../../proximity_web/app/admin/settings/page.tsx) + [settings-client.tsx](../../proximity_web/app/admin/settings/settings-client.tsx) | §8.6's `platform_settings` editor — three per-key forms (delivery fee, slot window, default commission), not a raw-JSON editor, matching `routes/admin.ts`'s own per-key validation. |
| [app/admin/discounts/page.tsx](../../proximity_web/app/admin/discounts/page.tsx) + [discounts-client.tsx](../../proximity_web/app/admin/discounts/discounts-client.tsx) | §11's discount authoring UI — create + activate/deactivate (no hard delete, same precedent shop suspend/rider revoke already set). |
| [app/admin/ledger/page.tsx](../../proximity_web/app/admin/ledger/page.tsx) + [admin-ledger-client.tsx](../../proximity_web/app/admin/ledger/admin-ledger-client.tsx) | §8.6's platform-wide ledger — total owed each direction, expandable per-shop itemized entries. |
| [app/admin/shops/shops-client.tsx](../../proximity_web/app/admin/shops/shops-client.tsx) | Extended in place: an inline, per-row editable commission % field + Save (§11's "per-shop platform_commission_pct override") — lives alongside the existing approval queue rather than a new page, since it's one more field on the same shop row. |

**Verified:** `npm run build` (Next.js 16.3.5, Turbopack) — compiles, typechecks, generates all 20 routes including the six new Sprint 12 ones. `npm run lint` — clean (three `react/no-unescaped-entities` errors caught and fixed — see "Bugs caught"). `npm audit` — 0 vulnerabilities (no dependencies added or changed).
**Not verified:** never pointed at a real `.env.local`, never opened in a browser against a live backend — same standing gap every prior sprint's `proximity_web` work has carried.

### Mobile app (`proximity_app/`)

| File | Purpose |
|---|---|
| [lib/shared/errors/cancel_order_exception.dart](../../proximity_app/lib/shared/errors/cancel_order_exception.dart) | New. One shared exception type for `rpc_cancel_order`'s typed errors, reached from two different features (buyer checkout, shop orders) — lives in `shared/` specifically so neither feature imports the other's repository just to catch it. |
| [features/checkout/data/checkout_repository.dart](../../proximity_app/lib/features/checkout/data/checkout_repository.dart) | Added `cancelOrder` (buyer). |
| [features/checkout/presentation/screens/order_confirmation_screen.dart](../../proximity_app/lib/features/checkout/presentation/screens/order_confirmation_screen.dart) | Added a "Cancel order" action per shop-card, shown only inside the buyer's own legal window (`_buyerCanCancel`) — confirmation dialog first, same bar the cart screen's "Remove all from this shop" already set in Sprint 6. This is also what backs "come back later from Order History and cancel" — `OrderHistoryScreen` (Sprint 10) already routes into this exact screen. |
| [features/shop_orders/data/shop_orders_repository.dart](../../proximity_app/lib/features/shop_orders/data/shop_orders_repository.dart) | Added `cancelOrder` (shop); `assignRider` gained a `force` parameter and now always sends an explicit JSON body (see "Bugs caught" — the pre-Sprint-12 version sent none at all, which this sprint's own backend change would otherwise have silently broken). |
| [features/shop_orders/presentation/screens/shop_orders_screen.dart](../../proximity_app/lib/features/shop_orders/presentation/screens/shop_orders_screen.dart) | Added a "Cancel order" icon action (shown inside the shop's own legal window) and a "Find a different rider" action (shown only pre-pickup, design decision #3's own boundary). |
| [features/rider/data/rider_repository.dart](../../proximity_app/lib/features/rider/data/rider_repository.dart) | Added `declineOrder`. |
| [features/rider/presentation/screens/rider_home_screen.dart](../../proximity_app/lib/features/rider/presentation/screens/rider_home_screen.dart) | Added a "Decline" button alongside "Accept" (only shown pre-accept, matching `rpc_rider_decline_order`'s own gate) — confirmation dialog first. |

**Verified:** `flutter analyze` — 0 errors, 0 warnings; 33 info-level style lints (up from Sprint 11's own count), all in the same two pre-existing accepted categories every prior sprint has carried (`prefer_initializing_formals`, `use_null_aware_elements`) — not fixed here either, for the same consistency reasons every prior sprint gave. No new dependencies added.
**Not verified:** never run on an emulator or physical device (none attached this session, unchanged since Sprint 4), never connected to a real backend/database — the confirmation dialogs, the typed-error surfacing, and the buyer/shop legal-window gating were all read and reasoned through but never actually tapped on a running app.

## Bugs caught and fixed during implementation

1. **A real Dart syntax-error risk, caught before `flutter analyze` even ran, by recognizing Sprint 7's own documented pattern rather than rediscovering it from scratch.** The first draft of `CancelOrderException`'s construction read the backend's typed error as `data is Map ? data['error']?['code'] as String? : null` — the exact "a bare `?[...]` null-aware-index chain immediately as a ternary's true-branch" shape Sprint 7's own `_addToCart` bug hit (`product_detail_screen.dart`). Fixed by parenthesizing (`data is Map ? (data['error']?['code'] as String?) : null`) before this was ever run through the analyzer, in both `checkout_repository.dart` and `shop_orders_repository.dart`.
2. **A real, if latent, request-breaking change caught by re-reading the existing Dart call site before shipping the backend change that would have broken it.** `ShopOrdersRepository.assignRider` originally called `_dio.post(...)` with **no body at all**; this sprint's own `zValidator("json", assignRiderBodySchema)` addition to that route would have made every existing call fail outright (Hono's `c.req.json()` throws on a genuinely empty body, before validation even runs). Caught while wiring the new `force` parameter through, not after — the Dart method now always sends an explicit JSON body (`{'force': force}`), and every other new optional-body route this sprint added (`decline`, `cancel`) was written with an explicit non-empty body on the Dart side from the start, specifically because this was checked first.
3. **Authorization checked after, not before, the shared status checks in the first draft of `rpc_cancel_order`** — inconsistent with `rpc_shop_advance_order_status`'s own established ordering (migrations/040 checks shop-team membership before `ORDER_ALREADY_FINAL`), and a minor real information leak: an unauthorized caller could learn "this order is already cancelled/completed" before ever being told they have no standing to ask at all. Caught during this sprint's own re-read of the finished RPC against its own stated precedent, not left in — reordered so `NOT_ORDER_OWNER`/`NOT_SHOP_MANAGER` are always raised before any status-based exception.
4. **Three `react/no-unescaped-entities` ESLint errors**, caught by `npm run lint` before this was called done — plain apostrophes in JSX text (`shop's`, `order's`) needed `&rsquo;`. Fixed in `discounts-client.tsx`, `settings-client.tsx`, `ledger-client.tsx`; re-verified clean afterward.
5. **A stale doc comment, not a live bug** — `push_service.dart`'s header still said the rider-assignment push routes to `/rider`, though `lib/riderAssignment.ts` was already correctly fixed to `/rider/onboarding` in Sprint 11 itself (that sprint's own bug #3). Caught during this sprint's required independent re-review of Sprint 11; corrected in `riderAssignment.ts`'s own header rather than left to mislead a future reader into "fixing" the code back to the wrong route.

## Exit criteria check — explicit about reasoning-alone vs. real-infrastructure-blocked, as asked

| Criterion | Status |
|---|---|
| A shopkeeper can see their own real revenue numbers and outstanding ledger balance | `GET .../analytics/sales-summary` and `GET .../ledger` are code-complete, `deno check`-verified; the dashboard pages that render them are `npm run build`-verified. **Checkable by reasoning alone:** the revenue/balance *formulas* themselves (traced by hand against `rpc_confirm_payment`'s own commission math and migrations/046's reversal design) are correct as written. **Blocked on real infrastructure:** whether the query actually executes against real Postgres, and whether it renders anything meaningful without at least one real order having gone through checkout/payment first — inherits every prior sprint's own "no live database" gap. |
| Admin can change the platform delivery fee and see it reflected on the next new order | `PATCH /admin/platform-settings` is code-complete. **Checkable by reasoning alone, and actually checked:** `routes/checkout.ts`'s `readRiderFee()`/`readSlotWindow()` (Sprint 7, unchanged this sprint) already re-read `platform_settings` fresh on every `/checkout/config` and `/orders` call — there is no cache anywhere in that path to invalidate, so "reflected on the next order" is true by construction the moment the write lands, not something this sprint had to build additional plumbing for. **Blocked on real infrastructure:** actually writing the row and placing a real order to observe it, same standing gap. |
| A cancelled order (buyer- or shop-initiated, at least one of each payment mode) leaves correct, reversed ledger entries and a rider back to `available` | **Checkable by reasoning alone, and traced by hand for all four real combinations this sprint's own design covers:** (a) buyer cancels an unpaid online order at `pending` → zero ledger rows exist yet, reversal loop finds nothing, correct (nothing was ever owed); (b) buyer cancels a paid online order at `confirmed` → one `payout_due` row exists, reversed with one `payout_reversal`; (c) either actor cancels a `pay_at_shop` order (synchronously `confirmed` at placement, per Sprint 8) with no discount → one `commission_due` row, reversed; (d) either actor cancels a `pay_at_shop` order WITH a discount → both the `commission_due` and the discount-reimbursement `payout_due` rows exist, both reversed. Rider release: an online, `platform_rider`-fulfilled order can already have `rider_id` set the instant it reaches `confirmed` (`rpc_assign_rider` fires automatically off that same transition, Sprint 9) — `rpc_cancel_order` unconditionally checks and releases it regardless of which actor cancelled. **Blocked on real infrastructure:** every one of these four traced-by-hand cases needs a real placed, paid (or pay-at-shop-confirmed), platform-rider-assigned order to actually cancel and observe — this project has never placed a single real order of any kind. |

**Bottom line: Sprint 12 is development-complete and internally verified at every layer this project has tooling for** (`deno check`, `flutter analyze`, `npm run build`/`lint`/`audit`) — same as every prior sprint, the remaining gap is that nothing here has touched a live Supabase project, and this sprint's own centerpiece logic (the cancellation/reversal state machine, the rider decline/reassignment flow) has the same "traced by hand, never run" caveat Sprint 7's `rpc_place_order` and Sprint 8's `rpc_confirm_payment` each carried at this same stage — flagged explicitly here rather than folded into the standard one-line caveat, matching those two sprints' own precedent for their own centerpiece work.

## What's genuinely unverified (same treatment prior sprints gave their own centerpiece work)

- **`rpc_cancel_order`'s ledger-reversal loop** (`id NOT IN (SELECT reverses_entry_id ... WHERE reverses_entry_id IS NOT NULL)`) — reasoned correct against Postgres's own `NOT IN` semantics (the explicit `IS NOT NULL` filter in the subquery is what avoids the classic "`NOT IN` against a set containing `NULL`" trap), never run against a real query planner.
- **`rpc_assign_rider`'s new `p_exclude_rider_ids UUID[] DEFAULT NULL` parameter and the `<> ALL(...)` exclusion check** — reasoned correct against documented Postgres array-operator semantics, never executed.
- **`rpc_expire_stale_rider_assignments`'s `DISTINCT ON (order_id) ... ORDER BY order_id, changed_at DESC` latest-assignment CTE** — traced by hand the same way Sprint 7's largest-remainder CTE was, never against a running planner.
- **The `DROP FUNCTION` + `CREATE FUNCTION` replacement of `rpc_assign_rider`'s signature** — reasoned correct against Postgres's own documented function-identity rules (name + argument types; `CREATE OR REPLACE` cannot change that), never actually applied to a real function that has existing dependents to confirm nothing else breaks.
- **Every new web page's actual rendering** — `npm run build` proves it compiles and typechecks; no page has ever been opened in a browser against a live backend, so the daily-revenue bar chart's actual visual proportions, the ledger table's real column widths, and every loading/error state are unverified beyond "the code that would render them is correct as written."

## Not yet built (by design, deferred to the sprint that actually needs it, or genuinely out of scope)

- **Settlement automation** (actually moving money for a ledger balance) — unchanged Phase-2 reasoning from v1/§4.9, this sprint's ledger view makes the obligation visible, it doesn't pay it out.
- **Refunds.** A cancelled *online* order's `payout_due` is correctly reversed (the platform no longer owes the shop), but this sprint does **not** trigger an actual Razorpay refund back to the buyer — no real Razorpay account has ever existed for this project (unchanged since Sprint 8), and §11's own Sprint 12 scope names ledger reversal, not payment-gateway refund automation, as the deliverable. Flagged plainly: a real cancelled-and-paid online order today leaves the buyer's money still sitting wherever Razorpay put it, with only the internal ledger corrected. A real gap, worth its own line in a future sprint once a real gateway account exists to build a refund flow against.
- **Mid-delivery (post-pickup) rider unreachability** — design decision #3's own named boundary, not solved, for the reasons stated there.
- **A `recurring_list_runs`-style audit table for cancellations or reassignment attempts** — `order_status_history`'s own free-text notes (`rider_declined`, `rider_assignment_timed_out`, `rider_reassignment_forced`, `cancelled`) are the audit trail; no separate table was judged necessary, same "two tables was the named scope" restraint Sprint 11 applied to Organizer.
- **A settings-level admin control for the 5-minute rider-assignment timeout** — a documented SQL constant, not a `platform_settings` row; see migrations/049's own header for why (nothing in this project's requirements names it as something admin needs to tune yet).
- **Bulk/multi-order cancellation UI** — every cancel action in both the web admin panel (there isn't one — cancellation is buyer/shop-only, not an admin action anywhere in §8.6) and the mobile apps is per-`orders`-row, one at a time, matching the per-shop-card data model (§4.8) — never built or implied otherwise.

## What you need to run

Same list Sprint 3–11.md carried, plus four new files:

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
043_create_recurring_lists.sql
044_rpc_recurring_list_crud.sql
045_rpc_process_due_recurring_lists.sql
046_add_shop_ledger_reversal.sql        -- Sprint 12, new
047_rpc_cancel_order.sql                -- Sprint 12, new
048_rider_decline_and_reassignment.sql  -- Sprint 12, new
049_rpc_expire_stale_rider_assignments.sql -- Sprint 12, new
```

If `000`–`045` are already confirmed applied, only **`046`–`049`** are new and need running, strictly in that order (`046` before `047`, since `rpc_cancel_order` inserts reversal rows that need the new column/CHECK to exist; `048` before `049`, since the cron job calls `rpc_assign_rider`'s new signature and reads `order_rider_declines`).

**Given this sprint's exit criteria is the most infrastructure-dependent yet — a real placed, paid order to cancel, in each payment mode, with and without a rider — getting a real Supabase project (and, for the online-payment half of that matrix, real Razorpay test credentials, still outstanding since Sprint 8) remains the single highest-leverage unblock, unchanged from every prior sprint's own closing recommendation, now compounding across five sprints of untested centerpiece logic (`rpc_place_order`, `rpc_confirm_payment`, `rpc_assign_rider`, and now `rpc_cancel_order`/the decline-reassignment RPCs).**

## What Sprint 13 needs from you before it can be verified either

Same shape as every prior sprint: Sprint 13 (polish & hardening — design-system audit, accessibility, empty/error states, Crashlytics + Sentry, image caching/list virtualization) can be written without any live infrastructure, but proving any of it — this sprint's analytics/ledger/cancellation work included — needs the migrations actually applied, a real Firebase project + APNs key (still outstanding since Sprint 11), real Razorpay test credentials (still outstanding since Sprint 8), and a physical device or working emulator this session still doesn't have access to. One more thing worth deciding before Sprint 13, not this sprint's call to make silently: **refunds on a cancelled, already-paid online order** (this sprint's own "Not yet built" list) has no scheduled sprint anywhere in §11's plan — flagging this now, the same way Sprint 8 flagged `rpc_shop_advance_order_status` and Sprint 9/10 each flagged this very cancellation/reversal gap, rather than letting a future session rediscover it a fifth time.

---

**Waiting for your go-ahead before starting Sprint 13**, per your instruction to stop at sprint boundaries.
