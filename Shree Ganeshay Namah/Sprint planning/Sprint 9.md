# Sprint 9 — Rider Network Live

**Status: development complete, `deno check`/`flutter analyze`-verified, not yet run against a live Supabase project, a physical device, or a real Razorpay account.**
Same honest line every prior sprint has drawn, unchanged in every particular: checked again at the start of this sprint (`supabase projects list` against the linked account, and a search for any `proximity_backend/.env`/`proximity_app/.env` with real values) — still no Supabase project named for this app (only `ChefAndBaker`/`MindScape`/`PiCode`/`LLV`, all pre-existing, unrelated projects in the same account) and still no real Razorpay credentials, so Sprint 8's own payment flow has never executed and this sprint's rider-assignment work — which depends on an order actually reaching `confirmed` — inherits that same gap rather than closing it. This sprint adds five new migrations (`038`–`042`) on top of the still-unconfirmed `000`–`037` (Sprint 8.md's own list — nothing in this session's history shows that changing). No Android device or emulator is attached to this session either (unchanged since Sprint 4); Sprint 0's `cmdline-tools`/licensing gap is still open too.

Written for a future LLM session (or you) to pick this project back up — if you're that session, start here, then `SPRINT_PLANNING.md` §11's Sprint 9 entry and §5.4/§7.5/§8.5 (and the two new paragraphs this sprint added to §5.1 and §13), then `Sprint 8.md` for the payment confirmation this sprint's rider assignment chains off of, and for that file's own closing note (`rpc_shop_advance_order_status` has no scheduled sprint) which this sprint answers directly.

This sprint touches `migrations/`, `proximity_backend/` (new lib + two new route files, extensions to three existing ones), and `proximity_app/` (mobile) — `proximity_web` is explicitly out of scope, unchanged since Sprint 3. One deliberate scope expansion beyond §11's own two-line Sprint 9 entry, decided and documented rather than silently added: see "The two decisions this sprint was explicitly asked to make" below.

## Goal (from SPRINT_PLANNING.md §11)

> `rpc_assign_rider` (nearest-available), rider app touchpoint (§8.5) — accept, status ladder, location updates. Buyer-side order tracking (§7.5) via Supabase Realtime, per-shop-card live status. Exit criteria: a `platform`-mode shop's delivery order gets auto-assigned to a real test rider, and the buyer sees live status changes with no polling.

## The two decisions this sprint was explicitly asked to make

### 1. `rpc_shop_advance_order_status` — brought into this sprint's scope, not deferred again

Sprint 8.md's own closing section flagged this RPC (§5.4) as having no scheduled sprint anywhere in §11's plan, and asked this sprint to decide explicitly rather than leave the gap open a second time. Checked directly, not assumed: §11's own Sprint 9 entry (quoted above) names `rpc_assign_rider` and the rider's own status ladder by name, but never this one, and `migrations/028`'s own comment (Sprint 7) had already predicted "Sprint 9" for it without that actually being scheduled anywhere.

**Decision: build it now.** This isn't scope creep — it's a load-bearing dependency the rider ladder cannot work without. `rpc_rider_update_status`'s own `picked_up` step requires an order to already be `ready_for_pickup`; with no RPC anywhere in this codebase able to move an order past `confirmed`, no platform-rider order could ever legally reach the point where a rider's own ladder even starts, and this sprint's exit criteria ("the buyer sees live status changes") would have had nothing to show beyond the one rider-assignment event. Full ladder logic, including the one real bug this sprint's own second verification pass caught in it, is in [migrations/040_rpc_shop_advance_order_status.sql](../../migrations/040_rpc_shop_advance_order_status.sql)'s header and in "Bugs caught" below.

### 2. §8.5's "push, via `rpc_assign_rider`" — checked, found not built, Realtime is the documented fallback

§8.5's own prose names push as the incoming-assignment mechanism. Checked directly before assuming otherwise: grepping this entire repo for `firebase`/`fcm`/`apns`/`push_token`/`flutter_local_notifications` turns up nothing but `users.fcm_token` (migrations/001), a placeholder column added in Sprint 1 specifically for Sprint 11 and never read or written by any route since. `proximity_app/pubspec.yaml` has no `firebase_messaging` dependency. §11's own plan puts "FCM (Android) + APNs (iOS) push wiring" in Sprint 11 — two sprints away.

**Decision: a Supabase Realtime subscription**, the same primitive §7.5 already specifies for buyer tracking — a rider's app subscribes to `orders` filtered to `rider_id = their own id`, and any change (an assignment, or a status another party set) triggers a REST re-fetch. This surfaced a real, previously undocumented architectural point, now captured in `SPRINT_PLANNING.md` §5.1: Realtime's "Postgres Changes" feature authorizes itself against the *client's own* Supabase Auth session, not the Edge Function's service-role connection — the one place in this whole project where RLS is live enforcement, not a backstop. `migrations/038` exists because that was checked and found to matter: `orders`/`order_status_history` had no rider-facing SELECT policy at all before this sprint, which would have made the subscription see nothing, silently.

**Honest, disclosed limitation:** a rider only receives this while the app is open and the subscription is alive — no background/killed-app delivery, unlike real push. Sprint 11's job to close, not this sprint's to paper over.

## A third, smaller decision: live tracking needed a way back in

§7.5's tracking view was, through Sprint 7/8, reachable only as a one-time push straight off a just-completed checkout — nothing in the app could navigate back to an order placed earlier and then backgrounded or closed. Rather than build straight into a screen nothing could reach later, this sprint added the minimum real fix: `GET /v1/order-groups` (a flat, unfiltered, most-recent-first list — deliberately NOT §11's own Sprint 10 "Order history / Order Again," which still owns reorder/filtering/pagination) and a "My Orders" tile in `proximity_app`'s account screen. Tapping a row lands on the exact same `GET /order-groups/:id` + Realtime subscription this sprint already built; Sprint 10 can replace or extend the list without touching the tracking screen it feeds.

## What was built

### Migrations (`migrations/`)

| File | Purpose |
|---|---|
| [migrations/038_add_rider_order_rls.sql](../../migrations/038_add_rider_order_rls.sql) | `orders_select_rider` / `order_status_history_select_rider` — the RLS gap decision #2 above found. §5.2 named this ownership class back in Sprint 1 ("Rider-own data ... assigned orders, read + status update only") without it ever being implemented; this is that, closed the moment a real consumer (Realtime) needed it. |
| [migrations/039_rpc_assign_rider.sql](../../migrations/039_rpc_assign_rider.sql) | `rpc_assign_rider(order_id)` — nearest available/verified rider via the `<->` KNN operator on `riders.current_location` vs. `shops.location` (same PostGIS family `GET /v1/shops/near` already established, Sprint 4), `FOR UPDATE SKIP LOCKED` so two concurrent assignments never double-book a rider. Idempotent (an already-assigned order returns that assignment). Full "when does this fire" reasoning in its own header. |
| [migrations/040_rpc_shop_advance_order_status.sql](../../migrations/040_rpc_shop_advance_order_status.sql) | `rpc_shop_advance_order_status(order_id, user_id, new_status)` — the forward-only ladder `confirmed → preparing → ready_for_pickup → (completed \| out_for_delivery → completed)`, branching on `fulfillment_type`/`delivery_fulfilled_by`, refusing to let a shop advance past `ready_for_pickup` on a `platform_rider` order (that's the rider's own ladder from here). See decision #1 above for why this exists this sprint at all. |
| [migrations/041_rpc_rider_accept_order.sql](../../migrations/041_rpc_rider_accept_order.sql) | `rpc_rider_accept_order(rider_user_id, order_id)` — §8.5's "Accept" step, made real: a small, separate, idempotent RPC (riders.status has no fourth "assigned but not yet accepted" value to hang this off, so it lives entirely in `order_status_history`) that `rpc_rider_update_status` (042) actually gates its own first ladder step on, not just a UI affordance. |
| [migrations/042_rpc_rider_update_status.sql](../../migrations/042_rpc_rider_update_status.sql) | `rpc_rider_update_status(rider_user_id, order_id, new_status)` — the `picked_up → out_for_delivery → delivered` ladder. Its own header spells out the real vocabulary mismatch with `orders.status`'s CHECK-constrained enum (`picked_up`/`delivered` were never legal `orders.status` values and migrations/028 stays untouched) and exactly how each step maps: `picked_up` moves `orders.status` to `out_for_delivery`; the ladder's own `out_for_delivery` step is a re-ping with no further column change; `delivered` moves it to `completed` and frees the rider back to `available`. |

**Not yet run** against the live Supabase project — same "apply in order via the Supabase SQL editor" workflow as every prior migration. See "What you need to run" below.

### Backend (`proximity_backend/`)

| File | Purpose |
|---|---|
| [proximity_backend/supabase/functions/api/lib/riderAssignment.ts](../../proximity_backend/supabase/functions/api/lib/riderAssignment.ts) | New. Thin wrapper around `rpc_assign_rider` — one implementation, two callers with deliberately different failure handling (best-effort/logged from the automatic path, a real typed error from the manual retry route) for the exact same thrown error, same shape `PaymentGatewayNotConfiguredError` already gets in Sprint 8. |
| [proximity_backend/supabase/functions/api/lib/orderConfirmation.ts](../../proximity_backend/supabase/functions/api/lib/orderConfirmation.ts) | Extended: `confirmPaymentAndGenerateInvoices` now also attempts rider assignment per order (best-effort, logged not thrown) after invoice generation, for every order with `delivery_fulfilled_by='platform_rider'`. In practice a no-op on the `pay_at_shop` path (§1.4 already refuses that combination at placement) — not dead code kept out, just naturally inert there. |
| [proximity_backend/supabase/functions/api/lib/shopAccess.ts](../../proximity_backend/supabase/functions/api/lib/shopAccess.ts) | Added `isShopMember` (any `member_role` — §5.3's "view orders/advance status" row), alongside the existing owner-or-staff-only `isShopWriter`. |
| [proximity_backend/supabase/functions/api/routes/riders.ts](../../proximity_backend/supabase/functions/api/routes/riders.ts) | Extended: the online/offline `PATCH .../status` now refuses to change status while `on_delivery` (a real guard, not just UI — that state is system-owned, only `rpc_rider_update_status`'s own `delivered` step returns a rider to `available`). New: `PATCH .../location` (raw `ST_SetSRID`/`ST_MakePoint` write, same idiom `shops.ts`'s own location PATCH established in Sprint 2), `GET .../orders` (the rider's own active assignments, each annotated with `riderLadderStep` — the most recent of the rider's own ladder words logged for that order, since `orders.status` alone can't distinguish `picked_up` from the `out_for_delivery` re-ping, per migrations/042's own header), `POST .../orders/:id/accept`, `POST .../orders/:id/status`. |
| [proximity_backend/supabase/functions/api/routes/shopOrders.ts](../../proximity_backend/supabase/functions/api/routes/shopOrders.ts) | New. `GET /shop/shops/:shopId/orders` (any member_role), `POST .../advance-status` (any member_role, `rpc_shop_advance_order_status`), `POST .../assign-rider` (owner/staff only — the documented manual retry for "no rider was available at confirmation time," migrations/039's own header). |
| [proximity_backend/supabase/functions/api/routes/checkout.ts](../../proximity_backend/supabase/functions/api/routes/checkout.ts) | Added `GET /order-groups` (the minimal list, see "A third, smaller decision" above) — registered before `/order-groups/:id`, and with its own exact-path `authMiddleware` registration alongside the existing `/order-groups/*` wildcard (the same "`/*` doesn't match the bare collection route" gap this file's own pre-existing `/orders` + `/orders/*` pair from Sprint 7 already existed to close — caught by noticing that precedent, not independently rediscovered). |
| [proximity_backend/supabase/functions/api/index.ts](../../proximity_backend/supabase/functions/api/index.ts) | Wired `shopOrdersRoute` in. |

**Verified:** `deno check supabase/functions/api/index.ts` passes clean (re-run after every substantive change). `deno lint` on every new/changed file surfaces only the same pre-existing, codebase-wide `npm:`-import-version warning Sprint 3/6/8 already documented as not a regression.
**Not verified:** never deployed, never received a real request, never run against a real database — same standing gap every prior sprint's backend work has carried. The KNN `<->` operator's actual query plan/behavior against `idx_riders_location`, the `FOR UPDATE SKIP LOCKED` race behavior under real concurrent assignment, and every RLS policy in migrations/038 have all been reasoned through against Postgres/PostGIS/Supabase documentation, never executed.

### Mobile app (`proximity_app/`)

New feature folder `shop_orders`; extensions to `rider` and `checkout`; one new shared file under `core/realtime`.

| File | Purpose |
|---|---|
| [proximity_app/lib/core/realtime/order_status_channel.dart](../../proximity_app/lib/core/realtime/order_status_channel.dart) | New. §7.5's live tracking — a Supabase Realtime "Postgres Changes" subscription on `order_status_history`, filtered (`inFilter`) to one order-group's child order ids, keyed by a stable joined-string (not a `List`, which never compares `==` to another instance of the same content — would resubscribe every rebuild otherwise). API confirmed live against the actually-installed `realtime_client` 2.13.0 source before writing this (`channel().onPostgresChanges(...).subscribe()`, `PostgresChangeFilter(type: inFilter, ...)`), not assumed from memory — this project's standing rule for anything Realtime-specific. |
| [proximity_app/lib/features/rider/data/rider_assignment_channel.dart](../../proximity_app/lib/features/rider/data/rider_assignment_channel.dart) | New. §8.5's Realtime fallback (decision #2 above) — a plain function, not a provider itself, because the actually-resolved `riverpod` (3.4.2, checked directly in the pub cache) only exposes a `.future` modifier, not Riverpod 2.x's `.stream` companion, so "wait for the rider's own id, then subscribe" has no clean provider-to-provider forwarding seam here; `riderAssignmentPingForSelfProvider` (rider_providers.dart) calls it directly and owns the channel's lifecycle itself. |
| [proximity_app/lib/features/rider/data/rider_location_pinger.dart](../../proximity_app/lib/features/rider/data/rider_location_pinger.dart) | New. §8.5's periodic location updates while `on_delivery`, reusing `geolocator` (already a Sprint 1 dependency, per the standing "don't add a second location package" instruction) — `Geolocator.getPositionStream` with a 50m `distanceFilter`, confirmed against the actually-installed `geolocator` 14.0.3 source, not assumed. |
| [proximity_app/lib/features/rider/data/models/rider_order.dart](../../proximity_app/lib/features/rider/data/models/rider_order.dart) | Mirrors `GET /rider/riders/me/orders`, including the new `riderLadderStep` field. |
| [proximity_app/lib/features/rider/data/rider_repository.dart](../../proximity_app/lib/features/rider/data/rider_repository.dart) | Added `setStatus`, `updateLocation`, `getMyOrders`, `acceptOrder`, `updateOrderStatus`. |
| [proximity_app/lib/features/rider/presentation/providers/rider_providers.dart](../../proximity_app/lib/features/rider/presentation/providers/rider_providers.dart) | Added `riderOrdersProvider`, `riderAssignmentPingForSelfProvider`, `riderLocationPingerProvider`. |
| [proximity_app/lib/features/rider/presentation/screens/rider_home_screen.dart](../../proximity_app/lib/features/rider/presentation/screens/rider_home_screen.dart) | New. The real working-rider screen: online/offline toggle (disabled while `on_delivery`), the live assignment list (re-fetched on every Realtime ping), Accept, and the status-ladder button — exactly one action shown at a time, chosen from `riderLadderStep`, not `status` alone. Starts/stops the location pinger reactively based on the rider's own `status`. |
| [proximity_app/lib/features/rider/presentation/screens/rider_onboarding_screen.dart](../../proximity_app/lib/features/rider/presentation/screens/rider_onboarding_screen.dart) | Sprint 2's static "verified" placeholder card is now `RiderHomeScreen` once `profile.isVerified` — same screen, same branch-on-data-presence shape, just a real destination for the verified case now. |
| [proximity_app/lib/features/shop_orders/data/models/my_shop.dart](../../proximity_app/lib/features/shop_orders/data/models/my_shop.dart), [shop_order.dart](../../proximity_app/lib/features/shop_orders/data/models/shop_order.dart) | New. Mirror `GET /shop/shops/mine` (a minimal id/name slice, Sprint 2's route) and `GET /shop/shops/:shopId/orders`. |
| [proximity_app/lib/features/shop_orders/data/shop_orders_repository.dart](../../proximity_app/lib/features/shop_orders/data/shop_orders_repository.dart) | New. `getMyShops`, `getOrders`, `advanceStatus`, `assignRider`. |
| [proximity_app/lib/features/shop_orders/presentation/providers/shop_orders_providers.dart](../../proximity_app/lib/features/shop_orders/presentation/providers/shop_orders_providers.dart) | New. `myShopsProvider` (also backs account_screen.dart's tile visibility), `shopOrdersProvider`. |
| [proximity_app/lib/features/shop_orders/presentation/screens/shop_orders_screen.dart](../../proximity_app/lib/features/shop_orders/presentation/screens/shop_orders_screen.dart) | New. §2's "lightweight in-app views for shop-order-notifications (shopkeepers/staff)," finally built — a shop picker (only shown for a multi-shop team member) over a per-order card with exactly one next action, mirroring RiderHomeScreen's own shape. Deliberately in `proximity_app`, not `proximity_web` — see §2's own system map and "Not yet built" below. |
| [proximity_app/lib/features/checkout/data/models/order_group_summary.dart](../../proximity_app/lib/features/checkout/data/models/order_group_summary.dart) | New. Mirrors `GET /v1/order-groups`'s deliberately thin shape (not `OrderGroup`'s full per-item nesting). |
| [proximity_app/lib/features/checkout/data/checkout_repository.dart](../../proximity_app/lib/features/checkout/data/checkout_repository.dart) | Added `getOrderGroups`. |
| [proximity_app/lib/features/checkout/presentation/providers/checkout_providers.dart](../../proximity_app/lib/features/checkout/presentation/providers/checkout_providers.dart) | Added `myOrderGroupsProvider`. |
| [proximity_app/lib/features/checkout/presentation/screens/my_orders_screen.dart](../../proximity_app/lib/features/checkout/presentation/screens/my_orders_screen.dart) | New — see "A third, smaller decision" above. |
| [proximity_app/lib/features/checkout/presentation/screens/order_confirmation_screen.dart](../../proximity_app/lib/features/checkout/presentation/screens/order_confirmation_screen.dart) | Now subscribes to `orderStatusEventsProvider` for the whole group's order ids on build. Any event both (a) appends to a per-order, client-accumulated "live updates" feed rendered directly on that shop's card (raw ladder words like `rider_assigned`/`picked_up` turned into buyer-readable text — words that never touch `orders.status` at all, migrations/039/041/042's own headers explain why) and (b) invalidates `orderGroupProvider` so the top-level status chip/payment status/totals stay correct for the events that DO change `orders.status`. Honestly scoped: the feed starts empty on open and only shows what happens while the screen is open, not a full history backfill (no REST route for that exists yet). |
| [proximity_app/lib/features/account/presentation/account_screen.dart](../../proximity_app/lib/features/account/presentation/account_screen.dart) | Added "My Orders" (always) and "Shop Orders" (only when `myShopsProvider` is non-empty — same "don't show a section with nothing under it" rule Home's Recommended-for-you section established in Sprint 6). |
| [proximity_app/lib/core/router/app_router.dart](../../proximity_app/lib/core/router/app_router.dart) | Added `/orders`, `/shop-orders` (both `_protectedPaths`). |

**Verified:** `flutter analyze` — 0 errors, 0 warnings; 22 info-level style lints, all in the two categories every prior sprint has accepted (`prefer_initializing_formals`, `use_null_aware_elements`) plus new instances in this sprint's own files, same consistency reasoning every prior sprint gave. No new dependencies added — `supabase_flutter`/`geolocator` were both already present; both had their exact resolved versions (2.17.2 / 14.0.3, with `realtime_client` 2.13.0 and `supabase` 2.16.1 underneath) checked directly in the pub cache before writing any Realtime or location code against them, per this project's standing rule.
**Not verified:** never run on an emulator or physical device (none attached this session, same gap every sprint since Sprint 4 has carried), never connected to a real backend/database, the entire Realtime subscription flow (both channels), the location pinger, and the online/offline `on_delivery` guard have all been read and reasoned through against real, checked API shapes but never actually exercised against a running Supabase Realtime server.

## Bugs caught and fixed during implementation

1. **A real mislabeled-error bug in `rpc_shop_advance_order_status`, caught by this sprint's own second verification pass, not left in.** The first draft's `out_for_delivery` branch folded two different refusal reasons into one `IF` condition (`fulfillment_type <> 'delivery' OR delivery_fulfilled_by = 'platform_rider'`) and raised `PLATFORM_RIDER_HANDLES_REMAINING_STATUS` for both — which is correct for the platform_rider case but actively misleading for a **pickup** order (there's no rider involved in a pickup at all; the buyer-facing message "a Proximity rider handles this order from here" would have been simply wrong). Split into two separate checks, `INVALID_STATUS_TRANSITION` for "this isn't a delivery order" and `PLATFORM_RIDER_HANDLES_REMAINING_STATUS` only for the actual platform-rider case. Fixed in [migrations/040](../../migrations/040_rpc_shop_advance_order_status.sql) before this was called done, not after.
2. **A route middleware gap that would have let two collection-style GET routes execute completely unauthenticated**, caught by noticing this project's own prior precedent for exactly this shape, not independently rediscovered from scratch. `checkoutRoute.use("/order-groups/*", authMiddleware)` (Sprint 7) only matches paths with something *after* `/order-groups/` — this file's own pre-existing `.use("/orders", ...)` + `.use("/orders/*", ...)` pair (also Sprint 7) already shows this project knew a bare `/*` wildcard doesn't cover the collection route itself. This sprint's new `GET /order-groups` (no trailing id) would have shipped with no auth check at all had that precedent not been spotted while wiring it in — fixed by adding the matching exact-path `.use("/order-groups", authMiddleware)`. The analogous new file, `routes/shopOrders.ts`, was written from scratch with a single broad `.use("/shop/shops/*", authMiddleware)` (matching `shops.ts`'s own broad-prefix convention) specifically to avoid needing this same fix a second time.
3. **`AsyncValue.valueOrNull` doesn't exist in this project's actually-resolved `riverpod` (3.4.2)** — renamed to a plain nullable `.value` getter, confirmed by reading the installed source directly (`async_value.dart`) after `flutter analyze` flagged both call sites (`account_screen.dart`, `rider_onboarding_screen.dart`) as undefined-getter errors. Same "riverpod 3.x reorganized something Riverpod 2.x training data would get wrong" pattern Sprint 1's `StateNotifier` relocation already hit.
4. **`StreamProvider` has no `.stream` companion modifier in this project's actually-resolved `riverpod` either** — confirmed by reading the package source directly (only a `.future` modifier file exists under `core/modifiers/`, no `stream.dart`), after the first draft of `riderAssignmentPingForSelfProvider` tried to compose "await the rider's own id via one FutureProvider, then forward another StreamProvider's `.stream`" the Riverpod-2.x way and `flutter analyze` caught the undefined getter. Redesigned so the Realtime channel is opened by a plain function (`rider_assignment_channel.dart`) called directly from inside the one provider that needs it, rather than composed across two providers.

## Exit criteria check

| Criterion | Status |
|---|---|
| A `platform`-mode shop's delivery order gets auto-assigned to a real test rider | `rpc_assign_rider` is called automatically from `confirmPaymentAndGenerateInvoices` the moment such an order reaches `confirmed`; code-complete, traced by hand against every branch, `deno check`-verified. **Cannot execute** until migrations `000`–`042` are live, a real approved `platform`/`both`-mode shop and a real verified/available rider both exist, and — per Sprint 8's own still-open gap — a real Razorpay test payment (or nothing, since this specific path only needs a confirmed order) actually reaches `rpc_confirm_payment`. |
| The buyer sees live status changes with no polling | `order_status_channel.dart`'s Realtime subscription is wired into `OrderConfirmationScreen`; every ladder-advancing RPC this sprint built (`rpc_shop_advance_order_status`, `rpc_rider_accept_order`, `rpc_rider_update_status`, plus `rpc_assign_rider`'s own `rider_assigned` log entry) writes to `order_status_history`, the table the subscription watches. Code-complete, `flutter analyze`-verified. **Cannot execute** until a live Supabase project exists (Realtime included) and a physical device or emulator is available to actually watch a screen update — neither exists in this session, unchanged since Sprint 4. |

**Bottom line: Sprint 9 is development-complete and internally verified at every layer this project has tooling for** (`deno check`, `flutter analyze`) — same as every prior sprint, the remaining gap is that nothing here has touched a live Supabase project or a real device, and this sprint's exit criteria specifically depend on Realtime, which has never been exercised against a real server in this project before now.

## What's genuinely unverified (worth being specific about, same treatment prior sprints gave their own centerpiece work)

- **Every RPC this sprint added** (`rpc_assign_rider`, `rpc_shop_advance_order_status`, `rpc_rider_accept_order`, `rpc_rider_update_status`) has never executed against real Postgres — the same standing caveat every RPC since Sprint 1 carries, but worth restating because this sprint's ladder logic is genuinely branchy (migrations/040's five-way `IF`/`ELSIF` on `p_new_status`, cross-referenced against two other columns each time).
- **The `<->` KNN operator's actual behavior against `idx_riders_location`** — reasoned correct against PostGIS's documented KNN-index-scan semantics for `GEOGRAPHY` columns, never run against a real query planner.
- **`FOR UPDATE SKIP LOCKED`'s race behavior under real concurrent `rpc_assign_rider` calls** — reasoned through against Postgres's documented row-locking semantics, never actually raced.
- **The entire Realtime path, both directions** — no Postgres Changes subscription in this project has ever received a real event. The RLS policies in migrations/038 are reasoned correct by re-deriving the exact same subquery shape `orders_select_shop_team` already uses successfully (as far as `deno check`-level reasoning can confirm; RLS itself has never been exercised against a live PostgREST/Realtime connection in this project at all, per every prior sprint's own standing caveat about §5.1's "backstop" policies).
- **`Geolocator.getPositionStream`'s actual behavior on a real device** — the API shape was checked against the installed package source, but no emulator or device exists in this session to confirm it fires, respects the distance filter, or survives backgrounding.

None of this changes the sprint's status honestly — every prior sprint has carried some version of "unverified against live infra." This sprint's honest difference, following Sprint 8's, is that its exit criteria depend on TWO things this project has never had at once: a live Supabase project (Realtime included) and a physical device to watch the result on.

## Not yet built (by design, deferred to the sprint that actually needs it)

- **Real push notifications for rider assignment** — decision #2 above. Sprint 11's job; the Realtime fallback this sprint builds is a genuine, working substitute while the app is open, not a permanent one.
- **A radius cap on `rpc_assign_rider`'s search** — finds the globally nearest available verified rider, however far. Worth revisiting once a real deployment spans more than one service area; not named anywhere in §5.4's own wording as required.
- **Rider decline/reassignment** — §8.5 only names "Accept," never "Decline." A rider who wants to reject an assignment has no path to do so this sprint; building one meant either inventing an unscoped riders.status value or a reassignment flow neither §5.4 nor this sprint's brief asked for.
- **Cancellation-triggered ledger/assignment reversal** — still blocked on the same "no cancellation flow exists anywhere in this project" gap Sprint 7/8 both flagged and left open. An order cancelled after rider assignment leaves the rider `on_delivery` indefinitely; not addressed this sprint.
- **A `proximity_web` shop-order-management dashboard** — `routes/shopOrders.ts`'s backend surface is real and complete, but the only consumer built this sprint is `proximity_app`'s lightweight touchpoint (§2's own system map), matching every sprint since Sprint 3's "proximity_web stays out of scope" convention. Nothing stops a future sprint building a web view against these exact same routes.
- **A live map pin for rider tracking** — §10's own backlog item, explicitly still Phase 2. `riders.current_location` is now actually written to (this sprint's own point), which is what makes that backlog item cheap whenever it's picked up — the buyer-facing surface this sprint built is still text-status-only, per §8.5's own MVP framing.
- **Full order history / Order Again** — MyOrdersScreen is deliberately minimal (see "A third, smaller decision" above); Sprint 10 (§11) still owns reorder, filtering, and pagination.
- **A full history backfill on the buyer's live-tracking feed** — `order_confirmation_screen.dart`'s new "live updates" list starts empty and only shows events received while the screen is open; no REST route exists yet to fetch an order's complete `order_status_history` for backfill. A real, disclosed scope cut, not a bug — adding one is a small, independent follow-up whenever it's asked for.

## What you need to run

Same list Sprint 3–8.md carried, plus five new files:

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
038_add_rider_order_rls.sql             -- Sprint 9, new
039_rpc_assign_rider.sql                -- Sprint 9, new
040_rpc_shop_advance_order_status.sql   -- Sprint 9, new
041_rpc_rider_accept_order.sql          -- Sprint 9, new
042_rpc_rider_update_status.sql         -- Sprint 9, new
```

If `000`–`037` are already confirmed applied, only **`038`–`042`** are new and need running, in that order (`038` before any of the RPCs, since `039`'s own successful operation depends on the rider being able to see its own assignment via Realtime once one exists — not a hard dependency for the SQL itself, but there's no reason to run them out of order).

**Given this sprint's exit criteria needs a real confirmed platform-rider order to test against, and Sprint 8's own exit criteria (a real test-mode payment) still hasn't been attempted at all** — getting a Razorpay test account and a real Supabase project remains the single highest-leverage unblock across both sprints, unchanged from Sprint 8.md's own closing recommendation.

## What Sprint 10 needs from you before it can be verified either

Same shape as every prior sprint, unchanged: Sprint 10 (order history / Order Again, Frequently-Bought) can be written without live infrastructure, but proving any of it — this sprint's rider network and live tracking included — needs the migrations actually applied, real approved shops/riders, a physical device or working emulator, and (new, cumulative from Sprint 8) a real Razorpay test account for any order that's supposed to already be paid. One more thing worth deciding before Sprint 10, not this sprint's call to make silently: rider decline/reassignment and cancellation-triggered reversal (both named under "Not yet built" above) still have no scheduled sprint anywhere in §11 — flagging this now, the same way Sprint 8 flagged `rpc_shop_advance_order_status`, rather than letting a third sprint rediscover it.

---

**Waiting for your go-ahead before starting Sprint 10**, per your instruction to stop at sprint boundaries.
