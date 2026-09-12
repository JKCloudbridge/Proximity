# Sprint 3 — Catalog & Inventory

**Status: development complete, build/typecheck/lint/audit-verified across the touched deployables, not yet verified against live infrastructure.**
Same honest line Sprint 1.md and Sprint 2.md both drew, for the same reason: no real Supabase project has run migrations `017`–`020` yet (or, as far as this session can tell, `000`–`016` either — see "What you need to run" below), so no real product/variant has ever actually been created, listed, or read back through the buyer-facing API. Everything below "What's actually verified" is correct against the code and the tooling, not against a running system.

Written for a future LLM session (or you) to pick this project back up — if you're that session, start here, then `SPRINT_PLANNING.md` §11's Sprint 3 entry, then `Sprint 2.md` for what Sprint 2 shipped underneath this (shops/riders/platform onboarding, the `proximity_web` scaffold, the OneDrive move story).

This sprint touches `migrations/` and `proximity_backend/` only, plus `proximity_web/`'s shopkeeper dashboard — **`proximity_app` (mobile) is untouched**, per `SPRINT_PLANNING.md` §2's system map: catalog management is explicitly a `proximity_web` dashboard feature, not a mobile one (mobile's own catalog surface is the buyer *browse* experience, which starts in Sprint 4).

## Goal (from SPRINT_PLANNING.md §11)

> Migrations: products, product_variants (unit fields, stock_status), product_images. Shopkeeper dashboard catalog CRUD (§8.2). Exit criteria: a shopkeeper can list a real product with variants and see it queryable via the buyer-facing read API.

## A note on where this sprint's schema actually came from

§4.5 says products/variants "carry over exactly as designed in v1," but doesn't repeat v1's literal DDL (v1 predates this repo's git history — it isn't recoverable from anywhere in this project). So this sprint's `products`/`product_variants`/`product_images` tables are a fresh design against §4.5's *prose* spec (unit_value/unit_label split, stock_status coarse toggle alongside stock_qty, is_veg, info_message, search vector), built with the same conventions every other Sprint 1/2 table already established (UUID PKs, paise-integer money, RLS-on-everything with the four-policy shop_sub_categories/shop_media shape, TIMESTAMPTZ). Flagging this plainly rather than implying it was transcribed from an original that no longer exists anywhere.

## What was built

### Migrations (`migrations/`)

| File | Purpose |
|---|---|
| [migrations/017_create_products.sql](../../migrations/017_create_products.sql) | `products` (§4.5) — shop-scoped, `category_id` required/`sub_category_id` optional, nullable `is_veg` ("not applicable" ≠ "false"), generated `search_vector` column (no route reads it yet) |
| [migrations/018_create_product_variants.sql](../../migrations/018_create_product_variants.sql) | `product_variants` — `unit_value`/`unit_label` split, `price`/`mrp` paise integers, `stock_status` (§1.7's kirana-shop trust-risk mitigation) alongside `stock_qty`, deliberately **not** auto-derived from one another this sprint |
| [migrations/019_create_product_images.sql](../../migrations/019_create_product_images.sql) | `product_images` — ordered per-product photo list, same shape as `shop_media` (009) |
| [migrations/020_create_product_images_bucket.sql](../../migrations/020_create_product_images_bucket.sql) | The `product-images` Storage bucket (**public**, unlike `rider-documents` — §3.6 doesn't mark this one private) + shop-team RLS keyed on `{shop_id}/...` path segments |

**Not yet run.** Same "apply in order via the Supabase SQL editor" workflow as every prior migration — see "What you need to run" below for the exact list, since as far as this session can tell `000`–`016` haven't been confirmed run against a live project either.

### Backend (`proximity_backend/`)

| File | Purpose |
|---|---|
| [proximity_backend/supabase/functions/api/db/schema.ts](../../proximity_backend/supabase/functions/api/db/schema.ts) | Extended with `shopSubCategories`, `products`, `productVariants`, `productImages`. `searchVector` intentionally omitted — same "no clean Drizzle pg-core type, no route needs it yet" reasoning as `shops.location` |
| [proximity_backend/supabase/functions/api/lib/shopAccess.ts](../../proximity_backend/supabase/functions/api/lib/shopAccess.ts) | Added `isShopWriter` (owner **or** staff, §5.3's "Add/edit catalog" row) alongside the existing owner-only `isShopOwner` |
| [proximity_backend/supabase/functions/api/routes/catalog.ts](../../proximity_backend/supabase/functions/api/routes/catalog.ts) | New. Shop-team routes (`/v1/shop/shops/:shopId/sub-categories*`, `/products*`, `/products/:productId/variants*`, `/products/:productId/images*`) plus the **buyer-facing public read API** this sprint's exit criteria names: `GET /v1/shops/:shopId/products`, `GET /v1/products/:id`, `GET /v1/shops/:shopId/sub-categories` — unauthenticated, filtered to approved shops/active rows |
| [proximity_backend/supabase/functions/api/index.ts](../../proximity_backend/supabase/functions/api/index.ts) | Wired `catalogRoute` in |

**Verified:** `deno check supabase/functions/api/index.ts` passes clean.
**Not verified:** never deployed, never received a real request, never connected to a real database.

### Web app (`proximity_web/`)

| File | Purpose |
|---|---|
| [proximity_web/lib/types.ts](../../proximity_web/lib/types.ts) | Added `Category`, `ShopSubCategory`, `Product`, `ProductVariant`, `ProductImage`, `StockStatus` |
| [proximity_web/lib/nav.ts](../../proximity_web/lib/nav.ts) | Dashboard nav gains "Catalog" |
| [proximity_web/components/ui/select.tsx](../../proximity_web/components/ui/select.tsx), [textarea.tsx](../../proximity_web/components/ui/textarea.tsx) | Hand-written, same shadcn-shape convention as the rest of `components/ui` (Sprint 2's bug #6) |
| [proximity_web/components/ui/button.tsx](../../proximity_web/components/ui/button.tsx) | Now also exports `buttonVariants`, so a styled `<Link>` (e.g. "Add product," row-level "Edit") can look like a button without a Radix `asChild`/`Slot` dependency this project doesn't have |
| [proximity_web/app/dashboard/catalog/page.tsx](../../proximity_web/app/dashboard/catalog/page.tsx) + [catalog-client.tsx](../../proximity_web/app/dashboard/catalog/catalog-client.tsx) | §8.2's "browse platform categories, create shop_sub_categories" step — a tabbed products list + sub-category manager. Deliberately **not** gated on `shop.status === 'approved'` (unlike `dashboard/page.tsx`) — a pending shop can build its catalog while it waits on admin review |
| [proximity_web/app/dashboard/catalog/products/new/page.tsx](../../proximity_web/app/dashboard/catalog/products/new/page.tsx), [products/product-form.tsx](../../proximity_web/app/dashboard/catalog/products/product-form.tsx) | Create-product form, shared with the edit page below |
| [proximity_web/app/dashboard/catalog/products/\[id\]/page.tsx](<../../proximity_web/app/dashboard/catalog/products/[id]/page.tsx>), [product-detail-client.tsx](<../../proximity_web/app/dashboard/catalog/products/[id]/product-detail-client.tsx>), [variant-manager.tsx](<../../proximity_web/app/dashboard/catalog/products/[id]/variant-manager.tsx>), [image-manager.tsx](<../../proximity_web/app/dashboard/catalog/products/[id]/image-manager.tsx>) | Product detail/edit — the form above, plus variant CRUD (add/toggle stock status/toggle active/remove) and photo upload (direct browser → `product-images` Storage bucket, then a row-recording POST, same split as the rider KYC upload) |

**Verified:** `npm run build` (Next.js 16.3.5, Turbopack) — compiles, typechecks, generates all 17 routes including the three new catalog ones. `npm run lint` — clean. `npm audit` — 0 vulnerabilities (no dependencies added or changed this sprint).
**Not verified:** never pointed at a real `.env.local`, never opened in a browser against a live backend, image upload never exercised against a real Storage bucket.

## Bugs caught and fixed during implementation

A second, independent verification pass (re-running `deno check`/`flutter analyze`/`npm run build|lint|audit` and re-reading every new migration and route file with fresh eyes) caught two more real issues after the sprint was first called "complete" — recorded here rather than quietly folded into the list above, since "verified" should mean something:

5. **`020`'s Storage RLS cast the wrong side.** All three write policies cast the *untrusted* path segment to `::uuid` (`(storage.foldername(name))[1]::uuid IN (SELECT shop_id FROM ...)`) before comparing it against `shop_team_members.shop_id`. A malformed or adversarial folder segment (anything that isn't a valid UUID string) would make Postgres raise a hard cast error during policy evaluation instead of the policy just evaluating to "no match" — a correctness/robustness gap, not an access-control hole (the request still fails closed either way), but a real inconsistency with `rider_documents`' own policies (016), which cast the *trusted* side (`auth.uid()::text`) instead. Fixed by comparing as text on both sides (`(storage.foldername(name))[1] IN (SELECT shop_id::text FROM ...)`), matching that precedent.
6. **`product_variants`' own `UNIQUE (product_id, unit_value, unit_label)` constraint (018) was never declared in `schema.ts`.** Every other unique constraint in this sprint's and Sprint 2's schema (`shop_team_members`, `shop_business_hours`, `shop_sub_categories`) is mirrored there with a matching named `unique(...)` — `product_variants` was the one omission, caught by re-reading `schema.ts` side-by-side with the migration rather than assuming the first pass was complete. The DB-level constraint was never actually missing or unenforced (Postgres enforces it regardless of what Drizzle's TS schema says), so this was a documentation/consistency gap, not a live bug — but it's exactly the kind of drift that causes a real bug two sprints from now when someone trusts `schema.ts` as the source of truth for what constraints exist. Fixed; `deno check` re-verified clean afterward. (Note, not fixed: creating a duplicate variant still surfaces as a generic 500 from `index.ts`'s catch-all `onError`, not a friendly `409`/`400` — no route anywhere in this codebase currently catches Postgres unique-violation errors specially, so this matches the project's actual current maturity level rather than being a new gap; worth a real pass if it comes up in practice.)

1. **A stray `#` instead of `//` broke a comment mid-file** — while wrapping a long comment line in `routes/catalog.ts`, one continuation line was accidentally left without its `//` prefix, which would have been parsed as an invalid top-level statement rather than a comment. Caught and fixed before the first `deno check` (which would have failed loudly on it anyway, but worth noting as a real slip, not a hypothetical one).
2. **`isVeg`'s "not applicable" state couldn't be *re*-selected on edit.** The first pass mapped the form's "not applicable" option to `undefined`, which `JSON.stringify` drops from the request body entirely — on a PATCH, an omitted key means "leave unchanged" (same convention every other partial-update route in this codebase uses), so re-selecting "not applicable" after a product had been marked veg/non-veg would silently do nothing. Fixed by making `isVeg` nullable end-to-end (`createProductSchema`/`updateProductSchema` accept `boolean | null`, not just `boolean | undefined`) and having the form send an explicit `null` — the same "explicit value vs. omitted key" distinction Sprint 1/2 already rely on elsewhere (e.g. every route's `body.x !== undefined ? {...} : {}` spread pattern).
3. **A sub-category's own `category_id` needed a second, cross-table check the DB schema can't express.** `shop_sub_categories` (010) already scopes each row to one shop *and* one top-level category, but nothing stops a product's `sub_category_id` and `category_id` from pointing at a sub-category that belongs to a *different* category than the one the product claims — not a single-table CHECK constraint, so it's enforced in `routes/catalog.ts`'s `validateSubCategory` (both on create and on any update that touches either field), same "cross-table invariant → application layer, not RLS" judgment call `shops.ts`'s `supportsDelivery`/`deliveryMode` check already made in Sprint 2.
4. **Cross-shop tampering via a foreign product id.** `isShopWriter(userId, shopId)` alone only proves the caller can write to `:shopId` — it says nothing about whether `:productId` in the URL actually belongs to that shop. Every variant/image route (and the product detail/update/delete routes) fetches the product scoped to *both* `id` and `shopId` (`getOwnedProduct`) before doing anything else, so a writer on shop A can't reach shop B's product by guessing its UUID. Caught while writing the nested variant/image routes, not after — the same shape of gap `routes/shops.ts`'s membership checks already close for shop-level access, just one level deeper.

## Exit criteria check

| Criterion | Status |
|---|---|
| A shopkeeper can list a real product with variants | Code complete (`routes/catalog.ts`'s product + variant CRUD, `proximity_web`'s catalog dashboard/product form/variant manager) and build/typecheck-verified. **Cannot execute** until migrations `017`–`020` (and, per below, `000`–`016`) are applied to a live Supabase project and a real approved shop exists. |
| ...and see it queryable via the buyer-facing read API | `GET /v1/shops/:shopId/products` and `GET /v1/products/:id` exist, unauthenticated, filtered to approved-shop/active-row exactly like the RLS backstop. Logic verified by reading and by `deno check`; **not executed** against a real request. |

**Bottom line: Sprint 3 is development-complete and internally verified at every layer this project has tooling for** (`deno check`, `next build`/`lint`/`audit`) — the remaining gap is the same one every prior sprint has honestly carried: nothing here has touched a real, running system yet.

## What you need to run (you asked specifically — here's the exact list)

As far as this session can tell, **no migration has been confirmed run against any live Supabase project yet** — Sprint 0/1/2's write-ups all say "not yet run," and nothing in this session's history shows that changing. So the honest answer is the full sequence, in order, `000` through `020`:

```
000_enable_extensions.sql
001_create_users.sql
002_create_addresses.sql
003_create_categories.sql
004_create_custom_jwt_claims_hook.sql   -- plus its one manual step: Authentication → Hooks → select custom_access_token_hook
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
017_create_products.sql                 -- Sprint 3, new
018_create_product_variants.sql         -- Sprint 3, new
019_create_product_images.sql           -- Sprint 3, new
020_create_product_images_bucket.sql    -- Sprint 3, new
```

**If `000`–`016` are already applied** (tell a future session this directly, or add a note here, so this list doesn't get re-run and re-checked from scratch every sprint) — then only **`017`–`020`** are new and need running, strictly in that order (`017` before `018`/`019`, since both FK to `products`; `020` last, since it's Storage-side and independent of the other three but conceptually belongs with them).

## Not yet built (by design, deferred to the sprint that actually needs it)

- Buyer-facing browse/search UX (filtering by category, sorting, pagination, full-text search against `products.search_vector`) — Sprint 4+'s job; this sprint's public routes are deliberately the minimum that makes the exit criteria true, not the finished buyer API.
- `shop_media` and `shop_blackout_dates` still have no route — unchanged from Sprint 2, still correctly deferred (Sprint 3 catalog work didn't need either).
- A `GET`/`PATCH` route for `platform_settings` — still Sprint 12's job, unchanged from Sprint 2.
- Inline image reordering (drag-to-sort `product_images.sort_order`) — the column exists, the upload flow always appends at the end; a real reorder UI wasn't in this sprint's scope.
- Bulk product import (CSV) — not mentioned in §8.2, not built.

## What Sprint 4 needs from you before it can be verified either

Same shape as every prior sprint: Sprint 4 (buyer Home — shops-near-you, category filtering, `NextSlotBadge`) can be written without a live Supabase project, but proving *any* of it — this sprint's catalog work included — needs the migrations actually applied and at least one real approved shop with real products in it to browse.

---

**Waiting for your go-ahead before starting Sprint 4**, per your instruction to stop at sprint boundaries.
