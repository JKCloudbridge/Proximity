# Sprint 15 — Local caching layer & real Categories tab

**Status: planning only — not yet implemented.** Written before any code changed, at your explicit request ("write a write-up for sprint 15... ask any questions you need now"), so you can review and redirect the scope before implementation starts. Inserted after the original plan, same reason and shape as Sprint 14: "iOS build & store submission" bumped from Sprint 15 to **Sprint 16** in `SPRINT_PLANNING.md` (§3.1, §3.2, §11, §12, §13 cross-references all updated) rather than reusing its number.

## Why this sprint exists

Two gaps, both surfaced by actually using the app for the first time in this project's history (Sprint 13/14's real device testing), not from re-reading the original plan:

1. **No local caching layer, anywhere.** Every screen does a live network round-trip to Supabase on every load — this codebase's own comments have named this gap explicitly, repeatedly, since as early as Sprint 1 ("no Drift caching yet"), always as a deliberately-deferred concern for "a later sprint" that never got scheduled a number until now.
2. **The Categories tab is still Sprint 1's original placeholder.** `app_router.dart`'s `/categories` route still renders `PlaceholderScreen(title: 'Categories')` — literally "Categories -- coming soon". Home, Cart, and Order Again all graduated from this exact same placeholder in their own sprints (4, 6, 10); Categories never did, and nothing in any later sprint's scope ever mentioned it again.

## Decisions made before writing this (per your answers)

- **Caching scope: targeted, not full offline-first.** A full offline-first rebuild (every screen works offline, conflict resolution, sync queues) is a much larger undertaking than one sprint should carry, and this app doesn't need it — it needs the *perceived* speed of not re-fetching the same nearby-shops list every time a buyer taps back into Home. Cache-then-revalidate on read-heavy, high-traffic screens only.
- **iOS bumped to Sprint 16**, not merged or renumbered differently — matches the precedent Sprint 14 already set.

## Scope: local caching layer

**Cached (stale-while-revalidate — show the cached result instantly, refresh in the background, swap in place if it changed):**
- `categoriesProvider` (the 20-category list — both the Home chip row and the new Categories tab below read this)
- `nearbyShopsProvider` / `buyerLocationProvider`'s resolved location (Home's "Shops near you")
- `recommendedProductsProvider`, `frequentlyBoughtGateProvider` (Home's other two sections)
- Shop detail (a shop's sub-categories + products) and product detail

**Deliberately NOT cached — stays live-network-only, unchanged:**
- Cart, checkout, order history, addresses, account/profile, wishlist, shop-owner/rider/admin screens, and every write path
- Reasoning: these are either correctness-sensitive (a stale cart total, a stale order status, or a stale stock count is a real bug, not a UX win) or inherently personal/low-repeat-visit data where the caching payoff doesn't justify the added complexity

**Mechanism:** `drift` (SQLite-backed, typed, compile-time-checked queries) — the concrete tool choice, since it's what this codebase's own prior comments already named as the intended one, not a new decision introduced here. Each covered provider gets a local Drift-backed read that emits immediately on a warm cache (UI paints with no spinner), while the real network fetch runs concurrently; on success, the cache is overwritten and the UI updates in place if the data actually changed. A cold cache (first-ever visit, or after the app's data is cleared) behaves exactly as it does today — loading spinner, then data — the cache only helps *subsequent* visits.

**Staleness handling:** a time-based TTL per cached collection (exact minutes to be decided at implementation time, reasoned against how often each screen's underlying data actually changes) — past that age, treat the cache as cold and show the loading state rather than silently serving very old data with no signal that a refresh is even happening.

## Scope: real Categories tab

Replaces `PlaceholderScreen(title: 'Categories')` with a real screen:
- A grid of all 20 seeded categories (icon + name, reusing `categoriesProvider` — itself now also cached per the section above).
- Tapping a category navigates to a new, focused screen listing nearby shops that carry it — reusing `GET /v1/shops/near?categoryId=`, the same endpoint and query param Home's own category-chip filtering already calls, so no new backend route is needed, only a new mobile screen that calls it standalone (rather than piggybacking on Home's own combined-sections layout).

## Exit criteria

- Revisiting Home, the Categories tab, a shop detail page, or a product detail page on a warm cache renders instantly with no loading spinner, then reconciles in place if the live data has actually changed since the cache was written.
- Cart, checkout, orders, and every write path show unchanged behavior — always live, never a cached value.
- The Categories tab shows all 20 real categories, not "coming soon" text; tapping one shows real nearby shops carrying that category.

## Decided (answered before implementation started)

- **Cache TTL philosophy: correctness over speed, speed only where it's actually safe.** Keep TTLs short and conservative rather than optimizing for maximum cache-hit rate — when in doubt, treat the cache as stale and show the real loading state rather than risk serving a noticeably-outdated result. This reinforces the already-narrow scope above rather than arguing for widening it: the sections covered (Home, Categories, shop/product browsing) are exactly the ones where a few-minutes-old result is genuinely harmless, and everything excluded above stays excluded for the same reason.
- **Categories tap-through reuses `shop_detail_screen.dart`'s own established interaction pattern** — a vertical rail on the left, a product grid on the right that updates based on the rail selection (`sub_category_rail.dart` + `product_grid_tile.dart`) — rather than a plain list. Concretely: tapping a category opens a screen where the **left rail lists nearby shops carrying that category** (`GET /v1/shops/near?categoryId=`, already built) and the **right grid shows the selected shop's products within that category** (`GET /v1/shop/shops/:shopId/products?categoryId=` or equivalent — check `routes/catalog.ts` for the exact existing shape before adding anything new). No new visual language — same `AppColors`/`AppTheme` (§6) as every other screen, same card/rail styling `ShopDetailScreen` already uses.
