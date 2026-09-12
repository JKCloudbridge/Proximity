# Sprint 6 — Multi-Shop Cart

**Status: development complete, `deno check`/`flutter analyze`-verified, not yet run against a live Supabase project or a physical device.**
Same honest line every prior sprint has drawn. This sprint adds four new migrations (`022`-`025`) on top of the still-unconfirmed `000`-`021` (Sprint 5.md's "What you need to run" list -- nothing in this session's history shows that changing). No Android device or emulator is attached to this session either (`flutter devices` still shows only Windows-desktop/Chrome/Edge, and this project still has no `windows`/`web` platform folders -- `android`/`ios` only); Sprint 0's still-open `cmdline-tools`/licensing gap is still open too.

Written for a future LLM session (or you) to pick this project back up -- if you're that session, start here, then `SPRINT_PLANNING.md` §11's Sprint 6 entry and §1.5/§7.3, then `Sprint 5.md` for the browse path this sprint's "Add to cart" button actually completes (it was real but inert through Sprint 5, on purpose).

This sprint touches `migrations/` and `proximity_backend/` (new routes) plus `proximity_app/` (mobile) only -- `proximity_web` is explicitly out of scope, unchanged since Sprint 3/4/5.

## Goal (from SPRINT_PLANNING.md §11)

> Migrations: carts/cart_items (no shop lock, §1.5). Cart screen grouped by shop (§7.3), Recommended-for-you baseline (`product_cross_sell` + trending fallback). Exit criteria: a cart can hold items from two different shops simultaneously and displays them grouped correctly.

## Where this sprint's two "fresh design against prose" tables actually came from

Both `carts` and `product_cross_sell` hit the same situation Sprint 3's products/variants and Sprint 5's wishlists already documented: §1.5 gives `cart_items`' literal DDL directly, but not `carts`' own DDL ("you'll need to design that table's own DDL (owner FK, timestamps) against the surrounding prose" -- this sprint's own instructions); §4.10 says `product_cross_sell` "carries over unchanged from v1" without repeating its DDL. Unlike wishlists, though, **both originals turned out to be recoverable this time** -- not from this repo's own history, but from the read-only Baker Ally reference project (`C:\Users\hemin\Desktop\Android Project`), which §9's reuse map already names as this project's source for exactly these two ideas:

- `migrations/014_create_carts.sql` and `015_create_cart_items.sql` there give `carts`' real literal DDL (`id`, `user_id UNIQUE`, timestamps) and confirm `cart_items`' shape matches §1.5's own literal SQL exactly.
- `migrations/025_AP_product_cross_sell.sql` there gives `product_cross_sell`'s real literal DDL.

Both are reused directly in this sprint's migrations rather than re-derived from prose alone, with the specific additions flagged in each file's own header (`carts.updated_at`; `product_cross_sell`'s self-reference `CHECK`) rather than silently folded in -- same "documented addition, not a silent deviation" discipline Sprint 2's `kyc_document_url` addition established.

**One reuse-map item deliberately NOT carried over:** §9 also names "Drift two-layer cart mechanics" (an offline-first local cache, guest-cart-merges-on-login, optimistic writes with revert-on-failure) as reused from Baker Ally. Checked directly against Baker Ally's actual working tree before assuming it -- no `CartRepository`/`CartNotifier`/cart-specific Drift table exists there at all (only planning docs describe a design that was apparently never committed as code). Combined with the fact that every list provider this project has shipped since Sprint 1 has consistently gone network-only with offline caching explicitly and repeatedly deferred to Sprint 13 polish, and that §5.2 already describes `cart_items` as ordinary own-user data (same ownership class as `addresses`/`wishlists`, both already sign-in-required with no guest fallback) -- building cart as a plain authenticated, network-only feature (same shape as `wishlists`) is the right call here, not a shortcut. `routes/cart.ts`'s own header documents this plainly, same way §9 itself already revisited the single-shop cart trigger.

## What was built

### Migrations (`migrations/`)

| File | Purpose |
|---|---|
| [migrations/022_create_carts.sql](../../migrations/022_create_carts.sql) | `carts` -- one row per user (`UNIQUE user_id`), created lazily by `rpc_add_to_cart` (024), never at signup. DDL reused from Baker Ally's recovered original; `updated_at` added on top of it. |
| [migrations/023_create_cart_items.sql](../../migrations/023_create_cart_items.sql) | `cart_items` -- literal DDL from SPRINT_PLANNING.md §1.5, verbatim. No shop lock. |
| [migrations/024_rpc_add_to_cart.sql](../../migrations/024_rpc_add_to_cart.sql) | `rpc_add_to_cart(p_user_id, p_variant_id, p_quantity)` -- the RPC §5.4 names explicitly ("Upsert into cart_items, stock-status check"). Get-or-create-the-cart then upsert-the-item, both via `ON CONFLICT`, inside one `SECURITY DEFINER` function -- same cross-row-race reasoning as `rpc_set_default_address` (005). |
| [migrations/025_create_product_cross_sell.sql](../../migrations/025_create_product_cross_sell.sql) | `product_cross_sell` -- DDL reused from Baker Ally's recovered original, plus a `CHECK (source_product_id <> recommended_product_id)` not in that original. Public read, admin-only write (`get_role()`, same pattern as `categories`). |

**Not yet run** against the live Supabase project -- same "apply in order via the Supabase SQL editor" workflow as every prior migration. See "What you need to run" below.

### Backend (`proximity_backend/`)

| File | Purpose |
|---|---|
| [proximity_backend/supabase/functions/api/db/schema.ts](../../proximity_backend/supabase/functions/api/db/schema.ts) | Added `carts`, `cartItems`, `productCrossSell`. |
| [proximity_backend/supabase/functions/api/middleware/auth.ts](../../proximity_backend/supabase/functions/api/middleware/auth.ts) | New `optionalAuthMiddleware` + `OptionalAuthEnv` -- the first "public, but personalizes when a valid bearer token happens to be present" route shape in this codebase (every prior route was either always-authenticated or always-public). Never rejects on a missing/invalid token; just proceeds as a guest. |
| [proximity_backend/supabase/functions/api/routes/cart.ts](../../proximity_backend/supabase/functions/api/routes/cart.ts) | New. `GET /v1/cart` (joined with variant/product/shop, batch-fetched same as `wishlist.ts`), `POST /v1/cart/items` (via `rpc_add_to_cart`, upsert-and-increment), `PATCH /v1/cart/items/:id` (absolute quantity set, plain Drizzle -- the stepper's own job, distinct semantics from POST's increment), `DELETE /v1/cart/items/:id`, `DELETE /v1/cart/shops/:shopId` (§7.3's "Remove all from this shop" section action). Entirely authenticated, same own-user-data shape as `wishlist.ts` -- no guest-usable backing. |
| [proximity_backend/supabase/functions/api/routes/recommendations.ts](../../proximity_backend/supabase/functions/api/routes/recommendations.ts) | New. `GET /v1/recommended` -- public (guests see it too), personalizes off the caller's own wishlist via `optionalAuthMiddleware` when signed in. See "The Recommended-for-you baseline, honestly" below for exactly how the ranking works and its one real limitation. |
| [proximity_backend/supabase/functions/api/index.ts](../../proximity_backend/supabase/functions/api/index.ts) | Wired `cartRoute`/`recommendationsRoute` in. |

**Verified:** `deno check supabase/functions/api/index.ts` passes clean. `deno lint` on the two new route files surfaces only the same pre-existing, codebase-wide `npm:`-import-version warning Sprint 3's write-up already documented as not a regression (this project gates on `deno check`, not `deno lint`).
**Not verified:** never deployed, never received a real request, never run against a real database -- same standing gap every prior sprint's backend work has carried. The raw SQL in `recommendations.ts` (the trend-score aggregation, the `ST_DWithin`/`HAVING` distance cut) is only checked at the TypeScript type level, not proven against real Postgres/PostGIS, same caveat Sprint 4's `/shops/near` write-up gave its own raw SQL.

### Mobile app (`proximity_app/`)

New feature folder `cart`.

| File | Purpose |
|---|---|
| [proximity_app/lib/features/cart/data/models/cart_item.dart](../../proximity_app/lib/features/cart/data/models/cart_item.dart) | Mirrors `GET /v1/cart`. `variant`/`product`/`shop` are non-nullable here (unlike `WishlistItem.product`) -- `cart_items.variant_id` is `ON DELETE CASCADE`, so a deleted variant takes its cart row down with it; there's no "row survives, joined data gone" case the way a wishlisted-then-hard-deleted product can happen. |
| [proximity_app/lib/features/cart/data/cart_repository.dart](../../proximity_app/lib/features/cart/data/cart_repository.dart) | `getCart`, `addItem` (increment), `updateQuantity` (absolute set), `removeItem`, `removeShop`. |
| [proximity_app/lib/features/cart/presentation/providers/cart_providers.dart](../../proximity_app/lib/features/cart/presentation/providers/cart_providers.dart) | `cartProvider` (network-only, empty list for guests, same convention as `wishlistProvider`), `cartItemCountProvider` (sum of quantities -- `app_shell.dart`'s own Sprint 1 comment named this sprint as the one that wires the bottom-nav badge). |
| [proximity_app/lib/features/cart/presentation/widgets/cart_item_tile.dart](../../proximity_app/lib/features/cart/presentation/widgets/cart_item_tile.dart) | One line item -- thumbnail, name/unit, price, a +/- stepper (absolute-set semantics, disables itself while a request is in flight so a rapid double-tap can't fire two overlapping PATCHes), remove action. Dims and shows "No longer available"/"Out of stock" with remove-only for a blocked item, same "flag explicitly, don't silently hide" rule `wishlist.ts` established. |
| [proximity_app/lib/features/cart/presentation/widgets/shop_cart_section.dart](../../proximity_app/lib/features/cart/presentation/widgets/shop_cart_section.dart) | §7.3's collapsible per-shop section -- logo/name header (expanded by default), shop subtotal, "Remove all from this shop" (with a one-tap confirmation dialog -- a bulk section-level action is more consequential than the wishlist screen's un-confirmed single-item "x"). |
| [proximity_app/lib/features/cart/presentation/screens/cart_screen.dart](../../proximity_app/lib/features/cart/presentation/screens/cart_screen.dart) | The real Cart tab -- replaces the Sprint 1 placeholder. Groups `cart_items` by shop **client-side** (§1.5's own framing: a plain insertion-ordered `Map`, not a data-model constraint), grand total + an honest inert "Proceed to checkout" (`Checkout arrives in Sprint 7`, same "wired now, built later" treatment the PDP's own Add to cart button got through Sprint 5). Guests see a sign-in prompt rendered by this screen itself, not a router redirect -- see below. |
| [proximity_app/lib/features/home/data/models/recommended_product.dart](../../proximity_app/lib/features/home/data/models/recommended_product.dart) | Mirrors `GET /v1/recommended`. |
| [proximity_app/lib/features/home/data/home_repository.dart](../../proximity_app/lib/features/home/data/home_repository.dart) | Added `getRecommended`. |
| [proximity_app/lib/features/home/presentation/providers/home_providers.dart](../../proximity_app/lib/features/home/presentation/providers/home_providers.dart) | Added `recommendedProductsProvider`. |
| [proximity_app/lib/features/home/presentation/widgets/recommended_product_card.dart](../../proximity_app/lib/features/home/presentation/widgets/recommended_product_card.dart) | One card -- no quick-add button, same restraint `ProductGridTile` already established (tap-through to the PDP only). |
| [proximity_app/lib/features/home/presentation/screens/home_screen.dart](../../proximity_app/lib/features/home/presentation/screens/home_screen.dart) | Added the "Recommended for you" section between the category chips and "Shops near you" -- a horizontal `GridView` with `crossAxisCount: 2` (an actual 2-row horizontal scroll, matching §7.1's wording literally, not a single-row approximation). Renders nothing at all (not even a heading) while loading or empty, same "don't show a section with nothing under it" rule Frequently-Bought's own future ≥3-gate will use. |
| [proximity_app/lib/features/product_detail/presentation/screens/product_detail_screen.dart](../../proximity_app/lib/features/product_detail/presentation/screens/product_detail_screen.dart) | "Add to cart" now real -- calls `CartRepository.addItem`, guest tap prompts sign-in (same rule `WishlistHeartButton` established), `OUT_OF_STOCK` from the RPC surfaces as a real message rather than a generic failure. |
| [proximity_app/lib/shared/widgets/app_shell.dart](../../proximity_app/lib/shared/widgets/app_shell.dart) | Cart tab now shows a live item-count `Badge`. |
| [proximity_app/lib/core/router/app_router.dart](../../proximity_app/lib/core/router/app_router.dart) | `/cart` now routes to the real `CartScreen`. Deliberately **not** added to `_protectedPaths` -- see that file's own updated header comment for why (a bottom-nav tab redirecting a guest straight out of the shell is worse UX than the screen's own sign-in prompt). |

**Verified:** `flutter analyze` -- 0 errors, 0 warnings; 17 info-level style lints, the same two pre-existing categories every prior sprint has accepted (`prefer_initializing_formals`, `use_null_aware_elements`), 2 new instances in this sprint's own new files. `dart run build_runner build` succeeds.
**Not verified:** never run on an emulator or physical device (none attached this session, same gap every sprint since Sprint 4 has carried), never connected to a real backend/database, the stepper's busy-guard and the guest sign-in prompts were read and reasoned through but never actually tapped on a running app.

## The Recommended-for-you baseline, honestly

§11's Sprint 6 entry says "`product_cross_sell` + trending fallback." Built as one ranked query, not a two-phase list splice:

1. Fetch up to ~60 eligible candidate products near the buyer (same `ST_DWithin`-then-`service_radius_km` cut as `GET /v1/shops/near`), ordered by **trend score** (total quantity currently sitting in any buyer's `cart_items` for that product -- Sprint 6's own new table, a genuine signal from the moment carts start filling) then by `created_at DESC` as the tiebreak/cold-start fallback, so a fresh database with zero cart activity still shows *something* (newest products) rather than an empty section.
2. If the caller is signed in (`optionalAuthMiddleware`), fetch their wishlist product ids, then any `product_cross_sell` rows sourced from those ids.
3. Filter out anything already in the wishlist (never recommend what's already saved), then stable-sort so `product_cross_sell` hits float to the front, ahead of the trend-ranked list.

**The honest limitation:** no admin route curates `product_cross_sell` yet -- not itemized anywhere in §8.6's admin scope (shop/rider approval, categories, `platform_settings`, commission override, discount authoring; cross-sell curation isn't in that list). So step 2/3 above are built correctly and will pick up real rows the moment a future admin UI writes any, but **in every real run right now, `sourceProductId -> recommendedProductId` never gets a row, and the trending fallback is what actually powers this section.** Flagging that plainly rather than implying personalization is live -- same discipline Sprint 3 applied to `product_variants`' undeclared unique constraint and Sprint 5 applied to wishlists' variant-memory cut.

## Bugs caught and fixed during implementation

1. **A Dart parser quirk, not a logic bug, but a real compile error until fixed:** `cond ? x['a']?['b'] : y` -- a bare `?[...]` null-aware-index chain immediately as a ternary's true-branch -- is a genuine syntax error in this project's own Dart SDK (confirmed by isolating it in a throwaway file before touching the real one: `error - Expected an identifier` / `Expected to find ':'`, reproducible with or without an intervening cast, with or without pulling the operands into named variables first). Needs its own parens: `cond ? (x['a']?['b']) : y`. Hit in `product_detail_screen.dart`'s `_addToCart` error-mapping (`err.response?.data is Map ? responseData['error']?['code'] : null`) -- caught by `flutter analyze` before this was called done, not left for a runtime surprise.
2. **`SUM(integer)` is `bigint` in Postgres, which postgres.js returns as a JS string, not a number.** `recommendations.ts`'s trend-score aggregation would have quietly mistyped its own `CandidateRow.trend_score: number` the moment anyone actually read that field (it currently doesn't -- the column only ever feeds the query's own `ORDER BY`, never the JS response mapping -- so this had zero runtime impact today, but it was a real, latent type-inaccuracy). Cast down explicitly (`::integer`) rather than left for a future reader of this file to trust a type that was already wrong.
3. **Checked, not assumed: Baker Ally's own working tree has no actual cart implementation**, despite `SPRINT_PLANNING.md` §9 naming "Drift two-layer cart mechanics" as reused from it and that project's own Milestone docs describing one in detail. `grep`ing `baker_ally_flutter/lib` for anything cart-related turns up nothing but a two-line aspirational comment in `core/providers.dart`. Found real `carts`/`cart_items`/`product_cross_sell` *migrations* there instead (which this sprint did reuse, see above) -- but the described Drift/offline/guest-cart architecture itself was never committed as code anywhere this session could find. Documented in `routes/cart.ts`'s own header rather than silently building (or silently skipping) something §9 named, so a future session doesn't wonder whether it was missed.

## Exit criteria check

| Criterion | Status |
|---|---|
| A cart can hold items from two different shops simultaneously | `cart_items` has no shop lock at all (migrations/023, literal to §1.5); `rpc_add_to_cart` never checks what else is in the cart before adding. Code complete, `deno check`-verified. **Cannot execute** until migrations `000`-`025` are applied to a live Supabase project (unchanged blocker from every prior sprint) and at least two real approved shops with real products exist to add from. |
| ...and displays them grouped correctly | `GET /v1/cart` returns a flat, joined list (shop id/name/logo included per row); `CartScreen` groups client-side into `ShopCartSection`s, one per distinct `shop.id`, preserving first-appearance order. Same execution blocker as above. |

**Bottom line: Sprint 6 is development-complete and internally verified at every layer this project has tooling for** (`deno check`, `flutter analyze`, `dart run build_runner build`) -- same as every prior sprint, the remaining gap is that nothing here has touched a live Supabase project, and this sprint still has no Android device/emulator to actually tap through "add from Shop A, add from Shop B, see two sections" on, same open item every sprint since Sprint 4 has carried.

## Not yet built (by design, deferred to the sprint that actually needs it)

- **Checkout** -- the cart screen's "Proceed to checkout" button is real and reachable, but inert (`order_groups`/`orders` don't exist until Sprint 7, §4.8). Same "wired now, built later" treatment the PDP's own Add to cart button got through Sprint 5.
- **Quantity-discount progress banners** (§7.3 names Baker Ally's `quantity_promo_banner.dart` as a "ported as-is" reuse) -- not built. Two independent reasons: no `discounts` table exists yet (§5.4 lists "discounts engine wired ... table live" as Sprint 7 scope, not Sprint 6), and (checked, not assumed, same discipline as the Drift finding above) no `quantity_promo_banner.dart` file actually exists anywhere in Baker Ally's recoverable working tree either -- there is nothing to port yet, on either side of the reuse.
- **Optimistic cart state** -- every mutation is "fire the request, then `ref.invalidate` and refetch," same convention `WishlistHeartButton` established in Sprint 5, not true optimistic UI. The stepper's own busy-guard (disables while in flight) keeps rapid taps from racing each other, but a slow network still means a visible round-trip per tap. Same "not silky yet, deferred to Sprint 13 polish" gap this codebase has flagged rather than silently left unmentioned elsewhere (e.g. Sprint 5's pagination note).
- **`product_cross_sell` admin curation UI** -- see "The Recommended-for-you baseline, honestly" above. Table + RLS exist; nothing writes to it yet.
- **Category filtering on Recommended-for-you** -- §7.1's "category-click filtering across sections" was named for Shops-near-you specifically (Sprint 4); the recommended feed doesn't re-filter when a Home category chip is tapped. Revisit if real usage asks for it.

## What you need to run

Same list Sprint 3/4/5.md carried, plus four new files:

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
022_create_carts.sql                    -- Sprint 6, new
023_create_cart_items.sql               -- Sprint 6, new
024_rpc_add_to_cart.sql                 -- Sprint 6, new
025_create_product_cross_sell.sql       -- Sprint 6, new
```

If `000`-`021` are already confirmed applied, only **`022`-`025`** are new and need running, strictly in that order (`022` before `023`/`024`, since both reference `carts`; `025` is independent of the other three and can run any time after `017_create_products.sql`).

## What Sprint 7 needs from you before it can be verified either

Same shape as every prior sprint, unchanged: Sprint 7 (checkout core -- `order_groups`/`orders`/`order_items`/`order_status_history`/`shop_ledger_entries`, `rpc_place_order`, the stubbed-payment checkout UX) can be written without a live Supabase project, but proving any of it -- this sprint's multi-shop cart included -- needs the migrations actually applied, at least two real approved shops with real products, and a physical device or working emulator this session still doesn't have access to (Sprint 0's Android `cmdline-tools`/licensing gap is still the cheapest way to unblock at least the emulator half of that, if you get to it before Sprint 7 starts).

---

**Waiting for your go-ahead before starting Sprint 7**, per your instruction to stop at sprint boundaries.
