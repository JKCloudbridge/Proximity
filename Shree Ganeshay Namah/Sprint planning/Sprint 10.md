# Sprint 10 — Order History & Personalization

**Status: development complete, `deno check`/`flutter analyze`-verified, not yet run against a live Supabase project or a physical device.**
Same honest line every prior sprint has drawn. This sprint adds **no new migrations** — everything it builds is computed live off tables `carts`/`order_groups`/`orders`/`order_items` (Sprints 6/7) already created; see "The one deliberate scope call this sprint makes" below for the same "no new migrations" pattern Sprint 4 established for exactly this reason. No Android device or emulator is attached to this session either (unchanged since Sprint 4); Sprint 0's still-open `cmdline-tools`/licensing gap is still open too. Nothing about this sprint's own dependency chain changed either: this sprint's whole premise (real order/repeat-purchase history) still ultimately depends on Sprint 7's `rpc_place_order` and Sprint 8's payment confirmation, neither of which has ever executed against a live database or a real Razorpay account — see "What's genuinely unverified" below for exactly what that means here specifically.

Written for a future LLM session (or you) to pick this project back up — if you're that session, start here, then `SPRINT_PLANNING.md` §11's Sprint 10 entry and §7.1/§7.6/§9, then `Sprint 9.md` for the "My Orders" stopgap and the rider network this sprint's own gap-scheduling decision follows on from.

This sprint touches `proximity_backend/` (new lib modules + two new route files, extensions to two existing ones) and `proximity_app/` (mobile) — `proximity_web` is explicitly out of scope, unchanged since Sprint 3. **No new migrations.**

## Goal (from SPRINT_PLANNING.md §11)

> Order history, Order Again tab (`group_tile`/`group_detail_sheet` port), Frequently-Bought engine + ≥3-groups Home gate. Exit criteria: a test account with ≥3 qualifying repeat-purchase patterns sees the Home section; an account with fewer does not.

## Before any of this: the independent re-review of Sprint 9 this sprint's own instructions required

Not just trusting Sprint 9.md's own write-up — re-read the actual SQL and mobile code with fresh eyes, same discipline every sprint since Sprint 6 has applied to the one before it:

- **Migrations 038–042** (rider-order RLS, `rpc_assign_rider`, `rpc_shop_advance_order_status`, `rpc_rider_accept_order`, `rpc_rider_update_status`) — read in full. All five hold up: the RLS policies correctly scope to the rider's own row via a subquery matching `orders_select_shop_team`'s established shape; `rpc_assign_rider`'s `FOR UPDATE SKIP LOCKED` and idempotency guard are both structurally sound; `rpc_shop_advance_order_status`'s five-way ladder correctly refuses a platform-rider order past `ready_for_pickup` and (post-Sprint-9's own second pass) correctly distinguishes "not a delivery order at all" from "a rider handles this now"; `rpc_rider_accept_order`/`rpc_rider_update_status`'s own accept-then-ladder gating (each step checks the previous one's own history row exists) is consistent and has no gap a rider could skip through by calling the status endpoint directly. No new issues found.
- **Mobile Realtime/rider/shop-orders code** — `core/realtime/order_status_channel.dart`, `features/rider/data/rider_assignment_channel.dart`, `features/rider/presentation/screens/rider_home_screen.dart`, `features/shop_orders/presentation/screens/shop_orders_screen.dart` all read cleanly against the actually-installed `realtime_client`/`riverpod` APIs those files' own headers already cite. The rider ladder's `riderLadderStep`-driven single-action-at-a-time UI and the shop-order card's own status-driven action set both correctly branch on `fulfillment_type`/`delivery_fulfilled_by`, matching the backend RPCs' own transition rules exactly. No new issues found.

Nothing here contradicts Sprint 9.md's own self-report — this re-review confirms it rather than correcting it, which is itself worth stating plainly rather than silently skipping the step because nothing turned up.

## What Baker Ally *actually* has for this feature — checked before writing anything, per the standing rule

§9's reuse map names `group_tile`/`group_detail_sheet` as the pattern to port. Checked directly in `C:\Users\hemin\Desktop\Android Project`, not assumed:

- **Neither file exists anywhere in that project.** Grepped the whole reference project, case-insensitive, for `group_tile`/`group_detail_sheet`/`GroupTile`/`GroupDetailSheet` — zero matches, in code or planning docs. `baker_ally_flutter/lib` itself holds only `main.dart` and `core/providers.dart` — no screens, no cart, nothing resembling a shipped Order Again tab. `profile_overlay_sheet.dart` (also named in §9) doesn't exist either, nor does `baker_ally_backend` have any route files of any kind beyond its `supabase/config.toml`.
- **What IS real:** `Planning docs/Architecture/03_order_again_tab.md` — a complete, detailed prose spec (page layout, group-tile design, group-detail bottom-sheet design, previously-bought tile design, empty states, API shape, backend pseudocode, Riverpod state shape) that documents a tab apparently never implemented as code.

This is the same "recoverable spec, not recoverable code" situation Sprint 6 hit for `carts`/`product_cross_sell` and Sprint 7 hit for `discounts` — except in those cases the *code* was real too (migrations existed) and only the top-level DDL needed re-deriving from prose; here, nothing beyond the design doc was ever built. `SPRINT_PLANNING.md` §9 has been updated to say so plainly (same "revisit the reuse map against reality" discipline Sprint 6 applied to the cart-trigger note and Sprint 8 applied to `checkout_repository.dart`). Everything in this sprint's Order Again tab is a fresh design against that prose, not a port.

## The one real data-model decision this forced: what "a group" means here

Baker Ally's own single-shop-cart/single-order model (which `03_order_again_tab.md` was written against) predates this project's Sprint 6/7 multi-shop-cart/`order_groups` redesign entirely — there, one order was the only unit "items ordered together" could mean. This project's checkout produces one `order_groups` row (the one charge, §4.8) containing N per-shop `orders` rows.

**Decided: a "group" is the item-set of one `orders` row — one shop's own sub-order — never one `order_groups` row.** `order_items` FKs to `orders`, not `order_groups`, so there is no group-level item-set at the `order_groups` layer without an extra flattening step that would silently blend multiple shops' items into one "group" — exactly the ambiguity §4.8's "never a single merged summary line" redesign exists to prevent. A group's own "Add All to Cart" action also only makes sense scoped to one shop. Full reasoning in [lib/frequentlyBoughtGroups.ts](../../proximity_backend/supabase/functions/api/lib/frequentlyBoughtGroups.ts)'s header.

## The other decision this sprint's own instructions required: Order History vs. Sprint 9's "My Orders"

**Decided: extend `GET /v1/order-groups` and the one screen that reads it, in place — not build a second, parallel surface.** The underlying data (the buyer's own `order_groups`, most-recent-first) was always exactly what a real Order History screen needs; Sprint 9's own stopgap was missing status filtering and real pagination, both of which are additive query params here, so nothing that already called the route (nothing did, outside this project's own mobile client) needed to change shape. `MyOrdersScreen` is renamed `OrderHistoryScreen` rather than kept alongside a second list screen with no stated relationship to it.

## A third decision, the same shape as Sprint 8/9's own gap-scheduling calls: rider decline/reassignment and cancellation-triggered ledger reversal

Sprint 9.md's own closing section re-flagged this as still having no scheduled sprint — the third sprint running to have to make this call (Sprint 8 did it for `rpc_shop_advance_order_status`, Sprint 9 did it for push-vs-Realtime). **Decided: not this sprint's scope (order history/personalization doesn't touch order lifecycle at all), but given a real, named line in Sprint 12's own §11 entry** — updated in `SPRINT_PLANNING.md` directly, not just noted here, so it can't be silently renamed and passed along a fourth time. Full reasoning in §13's "Decided in Sprint 10" entry.

## What was built

### Backend (`proximity_backend/`)

| File | Purpose |
|---|---|
| [lib/repeatPurchases.ts](../../proximity_backend/supabase/functions/api/lib/repeatPurchases.ts) | New. `getRepeatProducts` — one shared query behind both Order Again's "Previously Bought" section and Home's "Frequently Bought" gate, at two different repeat-count thresholds. **This file's own header is where "a qualifying repeat-purchase pattern" gets defined precisely** (§7.1 names the ">=3" threshold but never the unit): a product counts as previously-bought if it has an `order_items` row on any of the buyer's own `orders` that reached at least `confirmed` (excludes unpaid `pending` and `cancelled`); it "qualifies" (Home's own term) once that's happened on >=2 distinct such orders. |
| [lib/frequentlyBoughtGroups.ts](../../proximity_backend/supabase/functions/api/lib/frequentlyBoughtGroups.ts) | New. `getFrequentlyBoughtGroups` — Order Again's "Frequently Bought Together" bundles. Own-orders' item-sets first (ranked by recurrence, >=2 occurrences to "qualify"), platform-wide popular bundles (anonymised — the query never selects `user_id`) filling any remaining slots up to 10 total, per §3 of `03_order_again_tab.md`. Bounded, live-computed scan (`MAX_CANDIDATE_ORDERS_SCANNED`), same "documented, not unlimited" trade recommendations.ts's own `candidateCap` already makes — no admin curation/materialized-view layer exists for this any more than it does for `product_cross_sell`. |
| [routes/home.ts](../../proximity_backend/supabase/functions/api/routes/home.ts) | New. `GET /v1/home/frequently-bought` — §7.1/§11's own Home gate: `{ qualifies, products }`, authenticated only (no guest version of "your own repeat purchases" makes sense). Deliberately not location-filtered, unlike `recommendations.ts` — a genuine past purchase is relevant regardless of where the buyer is standing right now. |
| [routes/orderAgain.ts](../../proximity_backend/supabase/functions/api/routes/orderAgain.ts) | New. `GET /v1/order-again/frequently-bought` (wraps `getFrequentlyBoughtGroups`), `GET /v1/order-again/previously-bought?limit=&offset=` (infinite-scroll shape per `03_order_again_tab.md` §6, ported as `limit`/`offset` rather than that doc's own `page` — this codebase has no other page-numbered route anywhere to match). |
| [routes/cart.ts](../../proximity_backend/supabase/functions/api/routes/cart.ts) | Added `POST /v1/cart/items/batch` — §4/§5's "Add All to Cart" / "Add Selected Items to Cart," the exact path `03_order_again_tab.md` §9 names. Per-item best-effort (each call into `rpc_add_to_cart` is already its own atomic, idempotent upsert), not all-or-nothing — one stale item in an otherwise-good bundle shouldn't sink the whole add. |
| [routes/checkout.ts](../../proximity_backend/supabase/functions/api/routes/checkout.ts) | `GET /order-groups` extended in place (see decision above): optional `status` (`active`/`completed`/`cancelled`, derived server-side from child `orders` statuses — §4.8 never gave `order_groups` its own lifecycle column), `limit`, `cursor` (keyset, on `created_at`). A status filter over-fetches and filters in the app layer (documented trade — no materialized status column this MVP needs), so a filtered page can legitimately come back short of `limit` while `nextCursor` still points further back. |
| [index.ts](../../proximity_backend/supabase/functions/api/index.ts) | Wired `homeRoute`/`orderAgainRoute` in. |

**Verified:** `deno check supabase/functions/api/index.ts` passes clean. `deno lint` on every new/changed file surfaces only the same pre-existing, codebase-wide `npm:`-import-version warning Sprint 3/6/8/9 already documented as not a regression (this project gates on `deno check`).
**Not verified:** never deployed, never received a real request, never run against a real database — same standing gap every prior sprint's backend work has carried. Specifically unconfirmed: that `array_agg(... ORDER BY ...)` round-trips as a plain JS string array through this backend's raw `db.execute(sql...)` path the way every other array-adjacent query in this codebase has assumed (reasoned correct against documented postgres.js/PostGIS behavior, never run); that the `HAVING COUNT(DISTINCT ...)`/`GROUP BY` shapes in `repeatPurchases.ts` compile as written (every non-aggregated `SELECT` column was traced against its `GROUP BY` list by hand, same discipline Sprint 6/9 applied to their own aggregate queries, but never against a running query planner).

### Mobile app (`proximity_app/`)

New feature folder `order_again`; extensions to `home` and `checkout`.

| File | Purpose |
|---|---|
| [features/catalog/data/models/repeat_product.dart](../../proximity_app/lib/features/catalog/data/models/repeat_product.dart) | New. Mirrors both `GET /v1/home/frequently-bought`'s products and `GET /v1/order-again/previously-bought`'s rows — one shared model in this project's existing cross-feature browse-data home (`features/catalog`, per Sprint 5's own comment on that folder), since both callers read every field. |
| [features/order_again/data/models/frequently_bought_group.dart](../../proximity_app/lib/features/order_again/data/models/frequently_bought_group.dart) | New. Mirrors `GET /v1/order-again/frequently-bought`'s entries. |
| [features/order_again/data/order_again_repository.dart](../../proximity_app/lib/features/order_again/data/order_again_repository.dart) | New. `getFrequentlyBought`, `getPreviouslyBought`, `addItemsBatch`. |
| [features/order_again/presentation/providers/order_again_providers.dart](../../proximity_app/lib/features/order_again/presentation/providers/order_again_providers.dart) | New. `frequentlyBoughtGroupsProvider` (plain, `.autoDispose`); `previouslyBoughtProvider` — a `StateNotifier` (same shape `CheckoutDraftNotifier` established for real multi-step state), §6's own infinite-scroll rule, not numbered pages. |
| [features/order_again/presentation/widgets/group_tile.dart](../../proximity_app/lib/features/order_again/presentation/widgets/group_tile.dart) | New. §4's tile design — 2 images + overflow count, name from the first two product names, item count/price, "Add All to Cart." |
| [features/order_again/presentation/widgets/group_detail_sheet.dart](../../proximity_app/lib/features/order_again/presentation/widgets/group_detail_sheet.dart) | New. §5's bottom sheet — per-item qty steppers (default 1, `-` to 0 excludes), out-of-stock items disabled, live total, "Add Selected Items to Cart." |
| [features/order_again/presentation/widgets/previously_bought_tile.dart](../../proximity_app/lib/features/order_again/presentation/widgets/previously_bought_tile.dart) | New. §7's tile design — one **documented deviation**: an out-of-stock item gets a disabled "Out of Stock" state, not §7's "Notify Me" (that back-in-stock-email feature doesn't exist in this project at all, and per that same spec doc wasn't built in Baker Ally either — "blocked on choosing an email provider," its own words). |
| [features/order_again/presentation/screens/order_again_screen.dart](../../proximity_app/lib/features/order_again/presentation/screens/order_again_screen.dart) | New. The real fourth bottom-nav tab, replacing `PlaceholderScreen(title: 'Order Again')`. §8's empty states (brand-new buyer, no groups but has previously-bought, etc.); own-user data, same "gate the tab's content, not the tab itself" rule `CartScreen` established for `/cart`. |
| [features/home/data/home_repository.dart](../../proximity_app/lib/features/home/data/home_repository.dart) *(edited, not a new file)* | Added `getFrequentlyBought()`. |
| [features/home/presentation/providers/home_providers.dart](../../proximity_app/lib/features/home/presentation/providers/home_providers.dart) | Added `frequentlyBoughtGateProvider` — `qualifies: false` outright for a guest, no request made. |
| [features/home/presentation/widgets/frequently_bought_card.dart](../../proximity_app/lib/features/home/presentation/widgets/frequently_bought_card.dart) | New. Same restrained shape `RecommendedProductCard` established (tap-through only); shows "Ordered Nx before" in place of the shop name. |
| [features/home/presentation/screens/home_screen.dart](../../proximity_app/lib/features/home/presentation/screens/home_screen.dart) | Added the conditional Frequently Bought section, positioned per §7.1's own order (chips -> Frequently Bought -> Recommended -> Shops near you) — renders nothing at all, not even a heading, unless `qualifies` is true. |
| [features/checkout/data/models/order_group_summary.dart](../../proximity_app/lib/features/checkout/data/models/order_group_summary.dart) | Added `overallStatus`. |
| [features/checkout/data/checkout_repository.dart](../../proximity_app/lib/features/checkout/data/checkout_repository.dart) | `getOrderGroups` extended in place: `status`/`cursor`/`limit` params, returns `(items, nextCursor)`. |
| [features/checkout/presentation/providers/checkout_providers.dart](../../proximity_app/lib/features/checkout/presentation/providers/checkout_providers.dart) | Replaced the plain `myOrderGroupsProvider` `FutureProvider` with `orderHistoryProvider` — a `.family`-keyed (by status filter) `StateNotifier`, same infinite-scroll shape as Order Again's own `previouslyBoughtProvider`, with a bounded auto-continue for the case a status-filtered page comes back empty while more still exist further back. |
| [features/checkout/presentation/screens/order_history_screen.dart](../../proximity_app/lib/features/checkout/presentation/screens/order_history_screen.dart) | New (replaces `my_orders_screen.dart`, deleted). Status filter chips (All/Active/Completed/Cancelled) over the same tappable-row-into-live-tracking shape Sprint 9 built. |
| [features/account/presentation/account_screen.dart](../../proximity_app/lib/features/account/presentation/account_screen.dart) | "My Orders" tile relabelled "Order History" — same route (`/orders`), real feature now. |
| [core/router/app_router.dart](../../proximity_app/lib/core/router/app_router.dart) | `/orders` now builds `OrderHistoryScreen`; `/order-again` now builds `OrderAgainScreen`, replacing its `PlaceholderScreen`. |

**Verified:** `flutter analyze` — 0 errors, 0 warnings; 25 info-level style lints (up from Sprint 9's 22), all in the two categories every prior sprint has accepted (`prefer_initializing_formals`, `use_null_aware_elements`) — 3 new instances in this sprint's own new files, not fixed, for the same consistency reasons every prior sprint gave. No new dependencies added — `cached_network_image`/`go_router`/`flutter_riverpod` were all already present.
**Not verified:** never run on an emulator or physical device (none attached this session, same gap every sprint since Sprint 4 has carried), never connected to a real backend/database, the infinite-scroll auto-continue logic and the group-detail sheet's stepper/exclusion behavior were read and reasoned through but never actually tapped on a running app.

## Bugs caught and fixed during implementation

1. **A real, silent-data-loss pagination bug in `GET /order-groups`'s new status filter, caught on this sprint's own re-read before calling it done, not left in.** The first draft's `nextCursor` always walked off the *whole fetched batch's* last row whenever that batch came back full (`groups.length === fetchSize`) — correct for the unfiltered case, but wrong the moment a status filter was applied and the over-fetched batch held *more matches than fit on one page*: the leftover matching rows (already sitting in hand, just past the `pageSize` slice) would never be returned, because the next call's cursor skipped past the entire examined batch, matches and all. Concretely: a buyer with 45 `active` orders inside one 60-row over-fetched batch would see only the first 20 (`pageSize`), then the next page would silently start *after* all 60 examined rows — the remaining 25 matching orders gone for good, not just delayed. Fixed by cursoring off the **last item actually returned** whenever the page was truncated (so the next call re-scans, and this time returns, the leftover matches), and only cursoring off the whole batch's last row once every match in it had actually made it onto a page. Traced by hand against several worked examples (a batch entirely matching, a batch with no matches, a batch exactly `pageSize` matches) before treating this as fixed, the same "trace it, don't just believe the first version compiles" discipline Sprint 7's discount-apportionment bug and Sprint 9's `rpc_shop_advance_order_status` mislabeled-error bug were both caught the same way.
2. **A real compile error, caught by `flutter analyze` before this was called done, not left in.** `OrderHistoryNotifier.loadMore`'s first draft used a leading-underscore named parameter (`{int _autoContinueBudget = 5}`) as a "this is basically private" convention — Dart's actual rule is stricter than that: **named parameters can't start with an underscore at all** unless they genuinely bind to a field via `this.`, a real language rule this project hadn't hit before (every prior sprint's named-parameter conventions happened not to reach for a leading underscore). Fixed by dropping the underscore (`autoContinueBudget`) — cosmetic, not a design change, but a real error until fixed.

## Exit criteria check

| Criterion | Status |
|---|---|
| A test account with >=3 qualifying repeat-purchase patterns sees the Home section | `GET /v1/home/frequently-bought`'s `qualifies` gate is code-complete and traced by hand against `repeatPurchases.ts`'s own definition (>=2 distinct confirmed-or-later orders per product, >=3 such products). **Cannot execute** — same standing blocker every sprint since Sprint 3 has carried: migrations `000`–`042` are still unconfirmed against any live Supabase project, so no real order has ever been placed, let alone reordered, to test this gate against. |
| ...an account with fewer does not | Same code path, same execution blocker — `qualifies: false` and an empty `products` array is what the route returns whenever the count doesn't clear 3, traced by hand, not yet run for real. |

**Bottom line: Sprint 10 is development-complete and internally verified at every layer this project has tooling for** (`deno check`, `flutter analyze`) — same as every prior sprint, the remaining gap is that nothing here has touched a live Supabase project, and this sprint's own exit criteria specifically needs real seeded repeat-purchase history to check by tapping through it on a device, which this session has never had either.

## What's genuinely unverified (worth being specific about, same treatment prior sprints gave their own centerpiece work)

- **Every new query in `repeatPurchases.ts`/`frequentlyBoughtGroups.ts`** has never executed against real Postgres — traced by hand against documented `GROUP BY`/`HAVING`/`array_agg` semantics, same standing caveat every raw-SQL route since Sprint 4 carries, but worth restating because this sprint's frequently-bought-groups query is genuinely branchy (two full candidate scans, JS-side signature dedup, a fill-the-remainder merge step).
- **The whole "own account has real repeat-purchase history" precondition** — this sprint's exit criteria cannot be exercised at all without Sprint 7/8's own still-unverified checkout/payment flow actually producing confirmed orders first. This sprint inherits that gap rather than closing it (same as Sprint 9's rider-assignment work did for the same reason).
- **The batch-add-to-cart route's per-item failure reporting** — reasoned correct against `rpc_add_to_cart`'s own three error codes, never actually triggered against a real out-of-stock/deleted variant in a live database.
- **Order History's status-filter-then-cursor-pagination interaction** — the "over-fetch, filter, keep the batch's own last-row cursor regardless of how many survived the filter" logic was traced by hand against a few worked examples on paper, never run against a real, long, mixed-status order history.

## Not yet built (by design, deferred to the sprint that actually needs it)

- **Real cancellation, rider decline/reassignment, ledger reversal** — see the decision above; now a named line in Sprint 12's own §11 entry, not this sprint's job.
- **A materialized/cached aggregate for frequently-bought groups** — both new backend queries are bounded, live scans (`MAX_CANDIDATE_ORDERS_SCANNED`/`candidateCap`-style caps), same "documented, not unlimited" scope cut `recommendations.ts`'s own trend-score query already made for `product_cross_sell`'s absence — revisit once real order volume makes a live scan actually expensive, not a concern at this project's current (zero) real order volume.
- **Notify-me / back-in-stock alerts** on the Previously Bought tile — `03_order_again_tab.md`'s own spec names this, flagged there too as blocked on an email-provider decision that was never made even in Baker Ally. Not invented here; a disabled "Out of Stock" state stands in, honestly, rather than promising a feature this project has no `stock_notify_requests` table for.
- **`profile_overlay_sheet.dart`'s real port** — still nobody's job; `account_screen.dart` remains Sprint 2's placeholder screen. Flagged in §9 now as the same "named in the reuse map, not actually there" situation `group_tile`/`group_detail_sheet` turned out to be, rather than assumed fine for whenever a future sprint gets to it.
- **Pagination/backfill on Order History's own status-derivation cost** — every page still does one extra query (`orders` joined to `shops`) per batch of `order_groups` fetched, same "one query per joined table, not one per row" shape every list route in this codebase already uses; not a new cost, just restating that the derived-status filter didn't change this route's existing query shape, only added filtering on top of it.

## What you need to run

**Nothing new this sprint** — no migrations were added. Same full list every prior sprint's write-up has carried, unchanged:

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
```

**Given this sprint's own exit criteria needs real, seeded repeat-purchase history (>=3 qualifying products, ordered >=2 times each) to check against anything but hand-tracing** — getting a Razorpay test account and a real Supabase project remains the single highest-leverage unblock across Sprints 7 through 10 combined, unchanged from every prior sprint's own closing recommendation. This sprint's own exit criteria is arguably the *most* data-shape-dependent one yet (§11's own framing, quoted at the top of this file) — cheap to get definitively wrong without ever having tapped through a seeded account on a real device, same point Sprint 9's write-up already made about this exact gap.

## What Sprint 11 needs from you before it can be verified either

Same shape as every prior sprint, unchanged: Sprint 11 (Organizer — `recurring_lists`/`recurring_list_items`, `pg_cron` reminder job, FCM/APNs push wiring) can be written without live infrastructure, but proving any of it — this sprint's order history/personalization included — needs the migrations actually applied, real Razorpay test credentials, at least one seeded account with real repeat-purchase history, and a physical device or working emulator this session still doesn't have access to.

---

**Waiting for your go-ahead before starting Sprint 11**, per your instruction to stop at sprint boundaries.
