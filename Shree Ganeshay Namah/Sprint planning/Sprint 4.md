# Sprint 4 — Buyer Home

**Status: development complete, `deno check`/`flutter analyze`-verified, not yet run against a live Supabase project or a physical device.**
Same honest line every prior sprint has drawn: nothing in this project has touched a real, running system yet (Sprint 3.md's "What you need to run" list — migrations `000`–`020` — is still the full, unconfirmed list; this sprint adds **no new migrations**, see below). This sprint additionally has its own exit-criteria clause prior sprints didn't — "on a physical device" — and that specifically has not happened either: this session has no Android device or emulator attached (`flutter devices` shows only Windows-desktop/Chrome/Edge; Sprint 0's noted `cmdline-tools`/license gaps on this machine are still unresolved, so there's no emulator to fall back to here).

Written for a future LLM session (or you) to pick this project back up — if you're that session, start here, then `SPRINT_PLANNING.md` §11's Sprint 4 entry and §7.1/§7.2, then `Sprint 3.md` for the catalog schema this sprint's query depends on (`products.category_id` is what actually powers category filtering here — see that migration's own comment, it says so directly).

This sprint touches `proximity_backend/` (one new read route) and `proximity_app/` (mobile) only — `proximity_web` is explicitly out of scope per your instructions.

## Goal (from SPRINT_PLANNING.md §11)

> Top bar, category chip row, Shops-near-you (PostGIS query + `NextSlotBadge`, §7.2), category-click filtering across sections. Exit criteria: Home renders real nearby shops sorted by distance, filterable by category, on a physical device.

## A note on branch state before this sprint's own work

Sprint 3 is fully committed and merged: `origin/Sprint-3`'s `Sprint 3` commit was merged into `main` via PR #3, and you created `origin/Sprint-4` off that merged state on GitHub. This session's local `Sprint-4` branch now tracks it directly (`git checkout -b Sprint-4 origin/Sprint-4`) — no separate commit/merge step was needed on this session's part, and per your standing rule this session still never runs `git add`/`commit`/`push` itself. One pre-existing loose end, **not created by this sprint's work**: `Shree Ganeshay Namah/Sprint planning/Sprint 3.md` has an uncommitted local edit (a second, independent verification-pass writeup — items 5/6 in that file's "Bugs caught" section, plus a `deno lint` note) that was made before Sprint 3 was committed/pushed but never folded into that commit. It's sitting in the working tree now, carried over from `Sprint-3` onto `Sprint-4` when the branch was created; yours to commit whenever you handle git for this sprint too.

## The one deliberate scope call this sprint makes: no new migrations

Every prior sprint's write-up opens with a list of new migration files. This one doesn't have one — Sprint 4 is a **read-only** feature built entirely on tables Sprint 2/3 already created (`shops.location`/`service_radius_km`, `shop_business_hours`, `products.category_id`, `platform_settings.slot_window`) and the indexes that already exist on them (`idx_shops_location`, `idx_products_category_id`). Flagging this explicitly rather than leaving it to look like an oversight.

## The `NextSlotBadge`/fulfillment-slots judgment call (you asked me to document this)

§4.6 describes one endpoint — `GET /v1/shops/:id/fulfillment-slots?date=...&type=pickup|delivery` — that generates a full day's candidate slots (capacity, blackout dates, per-type). Building that endpoint now, for a Home badge that only ever needs "the next slot today," would mean guessing at capacity/blackout-date UX this sprint never specs and Sprint 7 (checkout) actually owns. So:

- **Built now:** a narrow helper (`lib/slots.ts`'s `computeNextSlot`) that returns the shop's current-or-next slot **for today only**, clipped to `shop_business_hours` for today's weekday, reading `platform_settings.slot_window` for the global 06:00–24:00/2-hour default. No blackout-date awareness, no next-day look-ahead — if a shop is closed today, hasn't set business hours, or every slot has already passed, it returns `null` and the badge simply doesn't render for that shop.
- **Deferred to Sprint 7, unchanged from the original plan:** the real `/fulfillment-slots` endpoint (multi-day, blackout-aware, capacity-aware) that checkout's slot picker actually needs.
- **A second, real judgment call inside that helper:** this codebase has no per-shop or per-platform timezone column anywhere, and every other date assumption in this project so far has implicitly meant India wall-clock time. Supabase Edge Functions run in UTC, so `lib/slots.ts` hardcodes a `+5:30` (IST) offset as the one interpretation of `slot_window`'s `"06:00"`/`"24:00"` strings and `shop_business_hours.opens_at`/`closes_at`. There is currently no data model for "which timezone" to do anything smarter — flagging this as a real, single-country assumption baked into the code, not a placeholder for a per-shop lookup that doesn't exist.
- **Architecture choice, not just a scope cut:** the server never renders "40 min" as a string — it returns `slotStart`/`slotEnd` timestamps, and the Flutter `NextSlotBadge` widget computes "now vs. upcoming" and formats the countdown itself, off the device's own clock, on a 30-second timer. A server-rendered string would go stale the instant a minute passed on a list that isn't re-fetched every second; this way the badge is genuinely live.

## What was built

### Backend (`proximity_backend/`)

| File | Purpose |
|---|---|
| [proximity_backend/supabase/functions/api/lib/slots.ts](../../proximity_backend/supabase/functions/api/lib/slots.ts) | New. `computeNextSlot` — the minimal, today-only, IST-hardcoded slot helper described above. |
| [proximity_backend/supabase/functions/api/routes/shops.ts](../../proximity_backend/supabase/functions/api/routes/shops.ts) | Added `GET /v1/shops/near` — public, unauthenticated (no `/shop/` prefix, same public/team split `routes/catalog.ts` already established). Query: `lat`, `lng` (required), `categoryId` (optional — filters to shops with ≥1 active product in that category, per `products.category_id`'s own file comment naming this as its purpose), `limit` (optional, default 30, capped 100). |

**What `/v1/shops/near` actually does, in order:**
1. One raw-SQL query (no clean Drizzle column type for `GEOGRAPHY`, same precedent as every other geo column in this codebase) computes `ST_Distance` from the buyer's point to every `status='approved'` shop, pre-filtered by `ST_DWithin(..., 50000)` to hit `idx_shops_location`'s GIST index before any exact per-shop cut — 50km is `createShopSchema`'s own `serviceRadiusKm` ceiling (this same file), so it can never exclude a shop that should qualify. The optional category filter is an `EXISTS` subquery against `products`.
2. Results are then cut to each shop's **own** `service_radius_km` (not a fixed platform radius — "near you" is defined by the shop's own delivery reach, per §4.4), sorted by distance, and capped at `limit`.
3. One shared `platform_settings` read (`slot_window`) + one shared `shop_business_hours` read (today's weekday, for exactly the shops in the result set) feed `computeNextSlot` per shop — not a per-shop round trip.
4. The response is hand-built into a plain camelCase object per shop — deliberately **not** returning `db.execute`'s raw rows directly, which come back snake_case straight from Postgres (the exact landmine this same file's `POST /shop/shops` comment already flags from Sprint 2; no reason to let it leak into a brand-new route).

**Verified:** `deno check supabase/functions/api/index.ts` passes clean.
**Not verified:** never deployed, never received a real request, never run against a real database — so the raw SQL (nested conditional `sql` fragments, `ST_DWithin`/`ST_Distance` argument order, the `time`-column string shape `computeNextSlot` assumes) is only checked at the TypeScript type level, not proven against real Postgres/PostGIS.

### Mobile app (`proximity_app/`)

| File | Purpose |
|---|---|
| [proximity_app/lib/features/home/data/models/category.dart](../../proximity_app/lib/features/home/data/models/category.dart) | Mirrors `GET /v1/categories` (already existed, unauthenticated, Sprint 1) |
| [proximity_app/lib/features/home/data/models/nearby_shop.dart](../../proximity_app/lib/features/home/data/models/nearby_shop.dart) | Mirrors `GET /v1/shops/near`'s shape, including `NextSlot { slotStart, slotEnd }` |
| [proximity_app/lib/features/home/data/home_repository.dart](../../proximity_app/lib/features/home/data/home_repository.dart) | `getCategories()`, `getNearbyShops({lat, lng, categoryId})` |
| [proximity_app/lib/features/home/presentation/providers/home_providers.dart](../../proximity_app/lib/features/home/presentation/providers/home_providers.dart) | `categoriesProvider`, `selectedCategoryIdProvider` (the shared category-filter state — see below), `buyerLocationProvider` (resolves the buyer's default address, falling back to a live GPS fix — reused by both Home and the top bar), `nearbyShopsProvider` |
| [proximity_app/lib/features/home/presentation/widgets/next_slot_badge.dart](../../proximity_app/lib/features/home/presentation/widgets/next_slot_badge.dart) | `NextSlotBadge` — §7.2's live countdown, verbatim to your worked example ("40 min", "Now – closes in Xh Ym") |
| [proximity_app/lib/features/home/presentation/widgets/category_chip_row.dart](../../proximity_app/lib/features/home/presentation/widgets/category_chip_row.dart) | §7.1's chip row — tapping a selected chip again clears back to "All" |
| [proximity_app/lib/features/home/presentation/widgets/shop_card.dart](../../proximity_app/lib/features/home/presentation/widgets/shop_card.dart) | The shops-near-you card — see "Not built" below on why it's a single cover image, not the spec'd photo carousel |
| [proximity_app/lib/features/home/presentation/screens/home_screen.dart](../../proximity_app/lib/features/home/presentation/screens/home_screen.dart) | The real Home tab — replaces Sprint 1's `PlaceholderScreen(title: 'Home')` |
| [proximity_app/lib/core/router/app_router.dart](../../proximity_app/lib/core/router/app_router.dart) | Wired `HomeScreen` into the `/` branch |
| [proximity_app/lib/shared/widgets/app_shell.dart](../../proximity_app/lib/shared/widgets/app_shell.dart) | Top bar now shows the resolved address (left, tappable → `/addresses`) instead of Sprint 1's placeholder search box — Sprint 1's own comment there said "no address label yet, that's Sprint 4, once there's a shops-near-you query that actually uses it." Search is now a plain icon (no search feature/backend is in this sprint's scope, per §11's entry — wired to an honest "coming soon" snackbar rather than a dead tap or a fake text field). |

**"Category-click filtering across sections"**: only one real section exists this sprint (Shops near you) — Frequently Bought and Recommended-for-you, §7.1's other two Home sections, are Sprint 6/10's job (their data sources, `product_cross_sell` and order history, don't exist yet). `selectedCategoryIdProvider` deliberately lives in its own provider file rather than as private state inside the shops-near-you widget specifically so those later sections can `ref.watch` the same selection once they exist, instead of Home needing to be restructured to introduce shared filter state then.

**Verified:** `flutter analyze` — 0 errors, 0 warnings; 12 info-level style lints, all `prefer_initializing_formals`/`use_null_aware_elements` — the same two categories Sprint 1/2 already established as accepted existing style, not fixed here either, for consistency (2 new instances of each, in this sprint's own new files).
**Not verified:** never run on an emulator or physical device (none attached this session — see the top of this file), never connected to a real backend/database, GPS permission flow (`LocationService.ensurePermission()`) never actually exercised end to end.

## Not yet built (by design, deferred to the sprint that actually needs it)

- **The auto-scrolling photo carousel** §7.1 specifies for each shop card — needs multiple photos per shop (`shop_media`), and that table still has no route (Sprint 2 and Sprint 3 both deferred it; still true here). `ShopCard` uses the shop's single `coverImageUrl` instead; swapping in a real carousel is a drop-in widget change once `shop_media` gets a route, not a redesign.
- **Search** — the top bar's search icon is present (per §7.1's layout) but inert; no search backend or screen is in this sprint's named scope, and `products.search_vector` (Sprint 3) still has no reader.
- **Shop detail navigation** — `ShopCard` is tappable now (so it doesn't need retrofitting later) but only shows a "coming in Sprint 5" snackbar; there's no shop-detail screen to send it to yet.
- **The real `/fulfillment-slots` endpoint** (§4.6, multi-day/blackout/capacity-aware) — still Sprint 7's job, unchanged from every prior sprint's write-up; this sprint's `computeNextSlot` is explicitly a smaller, Home-only helper (see above).
- **Next-day slot look-ahead** — if every slot for today has passed (or the shop's closed today), the badge just doesn't show; it never checks tomorrow. Documented above as a deliberate cut, not an oversight.

## Exit criteria check

| Criterion | Status |
|---|---|
| Home renders real nearby shops sorted by distance | `GET /v1/shops/near` sorts server-side by `ST_Distance`; `HomeScreen`/`nearbyShopsProvider` render the response in that order with no client-side re-sort. Code complete, `deno check`/`flutter analyze`-verified. **Cannot execute** until migrations `000`–`020` are applied to a live Supabase project (unchanged blocker from every prior sprint) and at least one real approved shop with a real `location` exists to be near. |
| ...filterable by category | `categoryId` query param → `EXISTS` subquery against `products.category_id`; `CategoryChipRow`/`selectedCategoryIdProvider` drive it from the mobile side. Same execution blocker as above. |
| ...on a physical device | **Not attempted.** No Android device or emulator was available in this session (`flutter devices` lists only Windows-desktop/web targets) — this is the one exit-criteria clause this sprint adds that prior sprints' "not yet verified" sections didn't have to carry, and it genuinely hasn't happened. |

**Bottom line: Sprint 4 is development-complete and internally verified at every layer this project has tooling for** (`deno check`, `flutter analyze`) — same as every prior sprint, the remaining gap is that nothing here has touched a live Supabase project, and this sprint additionally still needs an actual Android device/emulator plugged in before its own "on a physical device" clause can be checked off at all.

## What Sprint 5 needs from you before it can be verified either

Same shape as every prior sprint, plus one new item: Sprint 5 (shop detail, PDP, wishlist) can be written without a live Supabase project, but proving any of it — Sprint 4's Home included — needs the migrations actually applied, a real approved shop with real products, **and** a physical device or working emulator this session doesn't currently have access to. If you get Android command-line tools/licensing (Sprint 0's still-open item) or a physical device connected before Sprint 5 starts, that unblocks verifying this sprint's exit criteria retroactively too.

---

**Waiting for your go-ahead before starting Sprint 5**, per your instruction to stop at sprint boundaries.
