# Sprint 5 — Shop Detail, PDP, Wishlist

**Status: development complete, `deno check`/`flutter analyze`-verified, not yet run against a live Supabase project or a physical device.**
Same honest line every prior sprint has drawn: nothing in this project has touched a real, running system yet. This sprint adds one new migration (`021`) on top of the still-unconfirmed `000`–`020` (Sprint 3.md's "What you need to run" list — nothing in this session's history shows that changing). No Android device or emulator is attached to this session either (`flutter devices` still shows only Windows-desktop/Chrome/Edge, and this project has no `windows`/`web` platform folders at all -- `android`/`ios` only, per Sprint 1's `flutter create` -- so none of those three are even valid run targets here); Sprint 0's still-open `cmdline-tools`/licensing gap is still open too.

Written for a future LLM session (or you) to pick this project back up -- if you're that session, start here, then `SPRINT_PLANNING.md` §11's Sprint 5 entry and §7.1's shop-detail spec, then `Sprint 4.md` for the Home screen this sprint's navigation now leads out of (`ShopCard.onTap` pushed a "coming in Sprint 5" snackbar through last sprint; it pushes here for real now).

This sprint touches `migrations/` and `proximity_backend/` (new/extended read routes) plus `proximity_app/` (mobile) only -- `proximity_web` is explicitly out of scope per your instructions, unchanged since Sprint 3/4.

## Goal (from SPRINT_PLANNING.md §11)

> Vertical category rail w/ icon-on-select, product detail + variant selection, `wishlists`. Exit criteria: full browse path from Home -> shop -> product -> variant works.

## Where this sprint's wishlist schema actually came from

Same situation §4.5 put Sprint 3 in, and migrations/017's header comment documented plainly rather than pretending otherwise: §4.10 says wishlists "carry over unchanged from v1" without repeating v1's literal DDL, and that v1 pass predates this repo's git history -- it isn't recoverable from anywhere in this project. So `migrations/021_create_wishlists.sql` is a fresh design against §4.10's *prose*, not a transcription of an original that no longer exists. One real design decision made in that gap, worth flagging explicitly: **wishlists are scoped to the product, not to one specific `product_variant`.** A buyer saves "this snack" to come back to, not "this snack in the 200g size specifically" -- the variant picker still lives on the PDP for when they actually go to buy it. If a future sprint's product feedback says buyers expect the variant they wishlisted to be pre-selected on the PDP, that's a straightforward addition (`variant_id` nullable on `wishlists`, defaulting the PDP's selection when present) -- not a redesign.

## What was built

### Migrations (`migrations/`)

| File | Purpose |
|---|---|
| [migrations/021_create_wishlists.sql](../../migrations/021_create_wishlists.sql) | `wishlists` -- own-user data (§5.2), same RLS shape as `addresses` (002): one `FOR ALL USING (user_id = auth.uid())` policy, no shop-team or admin policy at all. `UNIQUE (user_id, product_id)` is what makes the add-route idempotent (below). |

**Not yet run** against the live Supabase project -- same "apply in order via the Supabase SQL editor" workflow as every prior migration. See "What you need to run" below.

### Backend (`proximity_backend/`)

| File | Purpose |
|---|---|
| [proximity_backend/supabase/functions/api/db/schema.ts](../../proximity_backend/supabase/functions/api/db/schema.ts) | Added `wishlists`. |
| [proximity_backend/supabase/functions/api/routes/wishlist.ts](../../proximity_backend/supabase/functions/api/routes/wishlist.ts) | New. `GET /v1/wishlist` (joined with product/shop/cheapest-active-variant/first-image, batch-fetched the same "one query per joined table, not one per row" way `GET /shops/near` shares its `platform_settings`/business-hours reads), `POST /v1/wishlist` (idempotent via `onConflictDoNothing`, same "resubmit is the same call as first" convention `rpc_create_rider_profile` established), `DELETE /v1/wishlist/:productId` (also idempotent). Entirely authenticated -- unlike every other route file this sprint touches, this one has no public half at all: wishlists are own-user data with no guest-usable backing. |
| [proximity_backend/supabase/functions/api/routes/shops.ts](../../proximity_backend/supabase/functions/api/routes/shops.ts) | Added `GET /v1/shops/:id` -- public, unauthenticated shop-detail read (name/description/logo/cover/address/pickup+delivery/deliveryMode/`NextSlotBadge` data), registered after `/shops/near` so a naive router trying literal segments first would still resolve "near" correctly even though Hono's actual router prioritizes static-over-param regardless of registration order -- costs nothing, removes the question. |
| [proximity_backend/supabase/functions/api/routes/catalog.ts](../../proximity_backend/supabase/functions/api/routes/catalog.ts) | Three changes to the existing buyer-facing routes: (1) `GET /shops/:shopId/products` now accepts an optional `subCategoryId` query param, filtering to one rail entry -- omitted shows the shop's full catalog, same "All" convention Home's category chips established. (2) That same route now attaches `images` per product (a new `withImages` helper, deliberately separate from the existing `withVariants` so the shop-team dashboard's own product list isn't changed) -- the shop-detail grid needs a thumbnail per tile. (3) `GET /products/:id` now joins a light `shop: {id, name, logoUrl}` object into its response, so the PDP has shop context even when reached from somewhere that never loaded the shop itself (the wishlist grid, in particular). |
| [proximity_backend/supabase/functions/api/index.ts](../../proximity_backend/supabase/functions/api/index.ts) | Wired `wishlistRoute` in. |

**Verified:** `deno check supabase/functions/api/index.ts` passes clean.
**Not verified:** never deployed, never received a real request, never run against a real database -- same standing gap every prior sprint's backend work has carried.

### Mobile app (`proximity_app/`)

New feature folders: `catalog` (shared browse-data models only, no screens of its own -- `ProductVariant`/`ProductImage`/`ShopProduct`), `shop_detail`, `product_detail`, `wishlist`.

| File | Purpose |
|---|---|
| [proximity_app/lib/features/catalog/data/models/product_variant.dart](../../proximity_app/lib/features/catalog/data/models/product_variant.dart) | Shared between the shop-detail grid and the PDP -- notes `unitValue`'s string-not-number round trip (Postgres `numeric` through Drizzle, same gotcha `schema.ts`'s own header already flags). |
| [proximity_app/lib/features/catalog/data/models/product_image.dart](../../proximity_app/lib/features/catalog/data/models/product_image.dart), [shop_product.dart](../../proximity_app/lib/features/catalog/data/models/shop_product.dart) | `ShopProduct` is the grid-tile model (`GET /shops/:shopId/products`'s shape) -- deliberately a separate model from the PDP's own `ProductDetail` (features/product_detail), same "two models for two response shapes" split `NearbyShop`/`ShopDetail` already established this sprint, below. |
| [proximity_app/lib/features/shop_detail/data/models/shop_detail.dart](../../proximity_app/lib/features/shop_detail/data/models/shop_detail.dart), [shop_sub_category.dart](../../proximity_app/lib/features/shop_detail/data/models/shop_sub_category.dart) | Mirror `GET /v1/shops/:id` and `GET /v1/shops/:shopId/sub-categories`. |
| [proximity_app/lib/features/shop_detail/data/shop_detail_repository.dart](../../proximity_app/lib/features/shop_detail/data/shop_detail_repository.dart) | `getShop` (null on 404, same pattern `RiderRepository.getMyProfile()` established), `getSubCategories`, `getProducts({subCategoryId})`. |
| [proximity_app/lib/features/shop_detail/presentation/providers/shop_detail_providers.dart](../../proximity_app/lib/features/shop_detail/presentation/providers/shop_detail_providers.dart) | Every provider here is `.family`-keyed on `shopId` and `.autoDispose` -- a shop-detail screen is pushed/popped per shop, and nothing (especially the rail's own selection state) should leak from one visited shop into the next. |
| [proximity_app/lib/features/shop_detail/presentation/widgets/sub_category_rail.dart](../../proximity_app/lib/features/shop_detail/presentation/widgets/sub_category_rail.dart) | §7.1's vertical rail, icon-on-select. "All" is a real first entry (unlike Home's chip row, a vertical rail with nothing ever highlighted would read as broken). |
| [proximity_app/lib/features/shop_detail/presentation/widgets/product_grid_tile.dart](../../proximity_app/lib/features/shop_detail/presentation/widgets/product_grid_tile.dart) | Grid tile -- thumbnail, veg dot, price line (cheapest active variant, "From ₹x" if >1 variant), out-of-stock overlay, embeds `WishlistHeartButton`. |
| [proximity_app/lib/features/shop_detail/presentation/screens/shop_detail_screen.dart](../../proximity_app/lib/features/shop_detail/presentation/screens/shop_detail_screen.dart) | Header (cover image, name/address/tags/`NextSlotBadge`) above a fixed `Row(rail, Expanded(grid))` split -- not a `CustomScrollView` with the rail as a sliver, since the rail and grid scroll independently and mixing two independently-scrolling lists into one sliver tree is exactly the kind of cleverness this sprint's scope doesn't need. |
| [proximity_app/lib/features/product_detail/data/models/product_detail.dart](../../proximity_app/lib/features/product_detail/data/models/product_detail.dart) | Mirrors `GET /v1/products/:id`'s full shape including the new `shop` join. |
| [proximity_app/lib/features/product_detail/data/product_detail_repository.dart](../../proximity_app/lib/features/product_detail/data/product_detail_repository.dart) | `getProduct` (null on 404). |
| [proximity_app/lib/features/product_detail/presentation/providers/product_detail_providers.dart](../../proximity_app/lib/features/product_detail/presentation/providers/product_detail_providers.dart) | `selectedVariantIdProvider` is `null` until the buyer taps a chip -- the PDP resolves a sensible default (first in-stock, else the first variant) itself on every build rather than writing that default into state on load, one less effect to get wrong. |
| [proximity_app/lib/features/product_detail/presentation/widgets/variant_selector.dart](../../proximity_app/lib/features/product_detail/presentation/widgets/variant_selector.dart) | `VariantSelector` (the unit chips) + `VariantPriceRow` (price/MRP-strikethrough/stock badge) -- pulled apart so a single-variant product still gets the price row with no chips to show. |
| [proximity_app/lib/features/product_detail/presentation/screens/product_detail_screen.dart](../../proximity_app/lib/features/product_detail/presentation/screens/product_detail_screen.dart) | §11's exit criteria ends here: images `PageView`, name/veg-dot, shop link back, variant selection, description, `info_message` callout, sticky "Add to cart" -- present and real, but intentionally inert (a snackbar: "Cart arrives in Sprint 6"), same "wired now, built later" treatment `ShopCard.onTap` got in Sprint 4. |
| [proximity_app/lib/features/wishlist/data/models/wishlist_item.dart](../../proximity_app/lib/features/wishlist/data/models/wishlist_item.dart), [wishlist_repository.dart](../../proximity_app/lib/features/wishlist/data/wishlist_repository.dart) | Mirror `GET/POST/DELETE /v1/wishlist*`. |
| [proximity_app/lib/features/wishlist/presentation/providers/wishlist_providers.dart](../../proximity_app/lib/features/wishlist/presentation/providers/wishlist_providers.dart) | `wishlistProvider` returns an empty list for a guest rather than letting the 401 surface -- both `WishlistHeartButton` (rendered on surfaces guests browse) and `WishlistScreen` need to render *something* for a signed-out state without each re-checking auth first. |
| [proximity_app/lib/features/wishlist/presentation/widgets/wishlist_heart_button.dart](../../proximity_app/lib/features/wishlist/presentation/widgets/wishlist_heart_button.dart) | The one toggle every product surface (grid tile, PDP) reuses. A guest's tap never calls the API at all -- own-user data with no guest-usable backing (routes/wishlist.ts's whole group is authenticated) -- it prompts sign-in instead, same "gated at the specific action, not at the door" rule `app_router.dart`'s own header comment already states for this app. |
| [proximity_app/lib/features/wishlist/presentation/screens/wishlist_screen.dart](../../proximity_app/lib/features/wishlist/presentation/screens/wishlist_screen.dart) | Grid of saved products; a product that's since become unavailable still shows (dimmed, "Unavailable" label, remove-only) rather than silently vanishing -- routes/wishlist.ts's own header explains why the backend never drops the row either. |
| [proximity_app/lib/shared/utils/currency.dart](../../proximity_app/lib/shared/utils/currency.dart) | `formatPaise` -- this sprint is mobile's first screen that renders a real price (§1.7's paise-integer convention), so the rupee-string formatting lives here once rather than at each of the three call sites that need it. |
| [proximity_app/lib/core/router/app_router.dart](../../proximity_app/lib/core/router/app_router.dart) | Added `/shop/:id`, `/product/:id` (both un-gated -- guests browse the full chain, same as Home), `/wishlist` (added to `_protectedPaths` -- own-user data). |
| [proximity_app/lib/features/home/presentation/screens/home_screen.dart](../../proximity_app/lib/features/home/presentation/screens/home_screen.dart) | `_openShop` now pushes `/shop/:id` for real, replacing Sprint 4's "coming in Sprint 5" snackbar. |
| [proximity_app/lib/features/account/presentation/account_screen.dart](../../proximity_app/lib/features/account/presentation/account_screen.dart) | Added a "My Wishlist" tile -- wishlists have no bottom-nav tab of their own (§7.1 names four tabs, none of them Wishlist), so this is its entry point, same role this screen already plays for "Become a rider" (Sprint 2). |

**Verified:** `flutter analyze` -- 0 errors, 0 warnings; 16 info-level style lints, all in the two categories Sprint 1/2/4 already established as accepted existing style (`prefer_initializing_formals`, `use_null_aware_elements`) -- not fixed here either, for the same consistency reasons.
**Not verified:** never run on an emulator or physical device (none attached this session, same gap Sprint 4 carried and flagged as still-open), never connected to a real backend/database, the wishlist sign-in prompt and the variant-selector default-resolution logic were read and reasoned through but never actually tapped on a running app.

## Bugs caught and fixed during implementation

1. **A wishlisted product with every variant independently deactivated would have read as "available" with no price to show.** `isAvailable` in `routes/wishlist.ts`'s response was initially `product.isActive && shop.status === 'approved'` only -- products and their variants toggle `is_active` independently (migrations/017 vs 018), so a product can stay active while every one of its variants is turned off, leaving `minPrice: null` on a row the buyer's screen would still call "available." Caught during this sprint's own self-review (same discipline Sprint 3's second pass applied), fixed by adding `prices.length > 0` to the `isAvailable` condition before this was called done, not after.
2. **`withImages` deliberately kept separate from `withVariants`, not merged in** -- both helpers in `routes/catalog.ts` are structurally identical (batch-fetch by id, filter per row), and merging them would have been the "DRYer" option. Not done: the shop-team dashboard's own product list (`GET /shop/shops/:shopId/products`) shares `withVariants` and has no reason to start carrying an `images` field it doesn't use -- keeping them separate avoids changing a response shape `proximity_web` (out of scope this sprint) may already depend on the exact prior fields of.

## Exit criteria check

| Criterion | Status |
|---|---|
| Home -> shop works | `ShopCard.onTap` pushes `/shop/:id`; `ShopDetailScreen` renders the header + rail + grid from `GET /v1/shops/:id`/`/sub-categories`/`/products`. Code complete, `deno check`/`flutter analyze`-verified. **Cannot execute** until migrations `000`–`021` are applied to a live Supabase project (unchanged blocker from every prior sprint) and at least one real approved shop with real products exists. |
| ...shop -> product works | Grid tiles and wishlist tiles both push `/product/:id`; `ProductDetailScreen` renders from `GET /v1/products/:id`. Same execution blocker as above. |
| ...product -> variant works | `VariantSelector`'s chips update `selectedVariantIdProvider`; `VariantPriceRow`/the sticky "Add to cart" button both react to the selection. Same execution blocker. |

**Bottom line: Sprint 5 is development-complete and internally verified at every layer this project has tooling for** (`deno check`, `flutter analyze`) -- same as every prior sprint, the remaining gap is that nothing here has touched a live Supabase project, and this sprint still has no Android device/emulator to actually tap through the flow on, same open item Sprint 4 already flagged.

## Not yet built (by design, deferred to the sprint that actually needs it)

- **Add to cart** -- the button is real and reachable, but inert (`cart_items` doesn't exist until Sprint 6, §1.5). Wiring it is a Sprint 6 job, not a Sprint 5 one.
- **The shop-detail cover carousel / product-image gallery beyond a plain `PageView`** -- functional, not polished; no page indicator dots, no pinch-zoom. Not named in §7.1's Sprint 5 scope.
- **Wishlisted-variant memory** -- flagged above under "where this sprint's wishlist schema came from." A real, considered cut, not an oversight.
- **Rail item counts** ("12" next to a sub-category) -- §7.1 doesn't ask for it; the rail shows name + icon only.
- **A remove confirmation on the wishlist screen** -- tapping the "x" removes immediately (idempotent on the backend, cheap to re-add), no "are you sure."
- **Pagination** on the shop-detail product grid or the wishlist grid -- both fetch everything in one call, same "minimum that makes the exit criteria true" scope discipline Sprint 3/4's public routes already established. Worth revisiting once a real shop has hundreds of products.

## What you need to run

Same list Sprint 3.md/4.md carried, plus one new file:

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
021_create_wishlists.sql                -- Sprint 5, new
```

If `000`–`020` are already confirmed applied, only **`021`** is new and needs running.

## What Sprint 6 needs from you before it can be verified either

Same shape as every prior sprint, unchanged: Sprint 6 (multi-shop cart) can be written without a live Supabase project, but proving any of it -- this sprint's browse path included -- needs the migrations actually applied, a real approved shop with real products, and a physical device or working emulator this session still doesn't have access to (Sprint 0's Android `cmdline-tools`/licensing gap is the cheapest way to unblock at least the emulator half of that, if you get to it before Sprint 6 starts).

---

**Waiting for your go-ahead before starting Sprint 6**, per your instruction to stop at sprint boundaries.
