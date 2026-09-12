# Sprint 2 — Shop & Rider Onboarding, Platform Settings

**Status: development complete, build/typecheck/lint-verified across all three deployables, not yet verified against live infrastructure.**
Same honest line Sprint 1.md drew, for the same reason: no real Supabase project has run migrations `006`–`016` yet, no real shop/rider has been created end to end, and no admin account exists to test the approval queues. Everything below "What's actually verified" is correct against the code and the tooling, not against a running system.

Written for a future LLM session (or you) to pick this project back up — if you're that session, start here, then `SPRINT_PLANNING.md` §11's Sprint 2 entry, then `Sprint 1.md` for what Sprint 1 actually shipped underneath this.

## A note on where this repo lives now

This sprint's work was originally developed under `C:\Users\hemin\OneDrive\Desktop\Proximity`. Partway through, that OneDrive-synced folder caused two real problems, unrelated to any code in this sprint:

1. **`npm install` inside `proximity_web` repeatedly corrupted itself** — OneDrive's real-time sync raced npm's rapid directory renames during large package extraction (`next` specifically), producing `ENOTEMPTY`/`EPERM` errors mid-install, and in one case npm reported success while having silently failed to extract almost every package.
2. **The local `.git` folder itself went stale/corrupted** after a multi-day gap in this session — OneDrive dehydrated or otherwise lost local file content under `.git` (and, it turned out, under the whole project), to the point that real `git.exe` reported "not a git repository" even though the directory wasn't empty.

Neither was a data-loss event — the actual working files were still intact and complete at the time, confirmed by an exhaustive file-count and `git status` diff against a fresh clone of `origin/Sprint-2`. The project has since moved to `C:\Users\hemin\Desktop\Proximity` (plain NTFS, no OneDrive sync), with git repaired by re-initializing and re-pointing at the existing GitHub remote (`https://github.com/JKCloudbridge/Proximity`) rather than re-cloning over the working files. **This is now the canonical path** — if you're a future session reading this from anywhere else, stop and confirm you're in the right folder first.

Even off OneDrive, `npm install` still needed a second clean attempt in this same folder before every package actually landed (Windows Defender real-time scanning is the suspected cause this time, not OneDrive) — flagging this as a standing "verify, don't trust the exit code" lesson for this machine, not something fixed once and done.

## Goal (from SPRINT_PLANNING.md §11)

> Migrations: shops, shop_team_members (moved here from Sprint 1), shop_business_hours, shop_media, shop_sub_categories, riders, platform_settings (seeded with delivery fee + slot window + default commission), shop_blackout_dates. proximity_web scaffolded (Next.js 16/Tailwind/shadcn), shopkeeper signup → shop creation form (incl. delivery_mode choice) → pending status. Rider signup + KYC upload flow (mobile, minimal) → is_verified=false. Admin panel skeleton: shop approval queue, rider approval queue. Exit criteria: a shop and a rider can be created and admin-approved end to end.

## What was built

### Migrations (`migrations/`)

| File | Purpose |
|---|---|
| [migrations/006_create_shops.sql](../../migrations/006_create_shops.sql) | `shops` (§4.4) — `delivery_fee` never existed here (removed vs. v1); `location` set atomically inside `rpc_create_shop`, not a two-step insert-then-update like `addresses` |
| [migrations/007_create_shop_team_members.sql](../../migrations/007_create_shop_team_members.sql) | `shop_team_members` (§1.2), moved here from Sprint 1 — also carries the two `shops` RLS policies that had to be deferred from 006 (see "Bugs caught" #1) |
| [migrations/008_create_shop_business_hours.sql](../../migrations/008_create_shop_business_hours.sql) | Per-weekday open/close + `is_closed`, `weekday` follows Postgres's own `EXTRACT(DOW)` convention |
| [migrations/009_create_shop_media.sql](../../migrations/009_create_shop_media.sql) | Ordered photo/video list per shop — table only, no route yet (see "Not yet built") |
| [migrations/010_create_shop_sub_categories.sql](../../migrations/010_create_shop_sub_categories.sql) | Shop-owned subdivisions of the global `categories` (§4.3) — table only, no route yet |
| [migrations/011_create_riders.sql](../../migrations/011_create_riders.sql) | `riders` (§4.7) + `kyc_document_url`, a real addition on top of §4.7's literal SQL (see "Bugs caught" #2) |
| [migrations/012_create_platform_settings.sql](../../migrations/012_create_platform_settings.sql) | `platform_settings` (§4.6) + the three seeded rows named there — no read/write route yet (see "Not yet built") |
| [migrations/013_create_shop_blackout_dates.sql](../../migrations/013_create_shop_blackout_dates.sql) | Per-shop closed-date exceptions (§4.6) — table only, consumed starting Sprint 7 |
| [migrations/014_rpc_create_shop.sql](../../migrations/014_rpc_create_shop.sql) | Atomic shop + owner `shop_team_members` row + `users.role → 'shop_owner'` (§4.4's stated invariant), never downgrades an existing admin |
| [migrations/015_rpc_create_rider_profile.sql](../../migrations/015_rpc_create_rider_profile.sql) | Same atomic pattern for riders; idempotent (`ON CONFLICT ... DO UPDATE`) so a KYC resubmission is the same call as first signup |
| [migrations/016_create_rider_documents_bucket.sql](../../migrations/016_create_rider_documents_bucket.sql) | The `rider-documents` Storage bucket + RLS — named in §3.6 since Sprint 0 but never actually created until now (see "Bugs caught" #4) |

**Not yet run** against the live Supabase project — same "apply in order, by hand, via the SQL editor" workflow as 000–005, still unverified against a real database.

### Backend (`proximity_backend/`)

| File | Purpose |
|---|---|
| [proximity_backend/supabase/functions/api/db/schema.ts](../../proximity_backend/supabase/functions/api/db/schema.ts) | Extended with `shops`, `shopTeamMembers`, `shopBusinessHours`, `riders`, `platformSettings`. `shop_media`/`shop_sub_categories`/`shop_blackout_dates` deliberately **not** added yet — no route touches them |
| [proximity_backend/supabase/functions/api/lib/shopAccess.ts](../../proximity_backend/supabase/functions/api/lib/shopAccess.ts) | `getShopMembership`/`isShopOwner`/`shopIdsForUser` — shop-team membership isn't a JWT-claim role (§1.2), so every shop-scoped route asks this same question through one shared helper |
| [proximity_backend/supabase/functions/api/routes/shops.ts](../../proximity_backend/supabase/functions/api/routes/shops.ts) | `POST /v1/shop/shops` (create, via `rpc_create_shop`), `GET .../mine`, `GET/PATCH .../:id`, `GET/PUT .../:id/business-hours` |
| [proximity_backend/supabase/functions/api/routes/riders.ts](../../proximity_backend/supabase/functions/api/routes/riders.ts) | `POST /v1/rider/riders` (idempotent create/resubmit), `GET .../me`, `PATCH .../me/status` (online/offline, verified-only) |
| [proximity_backend/supabase/functions/api/routes/admin.ts](../../proximity_backend/supabase/functions/api/routes/admin.ts) | `GET/POST /v1/admin/shops*` (approve/suspend), `GET/POST /v1/admin/riders*` (approve/revoke) — the "admin panel skeleton" this sprint's exit criteria names |
| [proximity_backend/supabase/functions/api/index.ts](../../proximity_backend/supabase/functions/api/index.ts) | Wired the three new route modules in; CORS allowlist comment updated to note `/v1/rider/*` is mobile-only, deliberately not in it |

**Verified:** `deno check supabase/functions/api/index.ts` passes clean.
**Not verified:** never deployed, never received a real request, never connected to a real database.

### Mobile app (`proximity_app/`)

| File | Purpose |
|---|---|
| [proximity_app/pubspec.yaml](../../proximity_app/pubspec.yaml) | Added `image_picker` (resolved `1.2.3`), verified against the actual installed source before use, same discipline as Sprint 1 |
| [proximity_app/lib/features/rider/data/models/rider_profile.dart](../../proximity_app/lib/features/rider/data/models/rider_profile.dart) | Defensive camelCase/snake_case field lookup, same pattern as `Address.fromJson` |
| [proximity_app/lib/features/rider/data/rider_repository.dart](../../proximity_app/lib/features/rider/data/rider_repository.dart) | `POST /v1/rider/riders` (idempotent create/resubmit), `GET .../me` (404 → `null`, not an error) |
| [proximity_app/lib/features/rider/data/rider_document_service.dart](../../proximity_app/lib/features/rider/data/rider_document_service.dart) | KYC document capture (`image_picker`) + direct-to-Supabase-Storage upload — same "Storage is a separate, already-authenticated path" precedent as Baker Ally's avatar upload |
| [proximity_app/lib/features/rider/presentation/providers/rider_providers.dart](../../proximity_app/lib/features/rider/presentation/providers/rider_providers.dart) | — |
| [proximity_app/lib/features/rider/presentation/screens/rider_onboarding_screen.dart](../../proximity_app/lib/features/rider/presentation/screens/rider_onboarding_screen.dart) | One screen, branches on whether a rider profile already exists: the signup form, or a pending/verified status card with a resubmit path |
| [proximity_app/lib/features/account/presentation/account_screen.dart](../../proximity_app/lib/features/account/presentation/account_screen.dart) | Placeholder for the real `profile_overlay_sheet.dart` port (§7.6, still pending) — exists now specifically to give "Become a rider" a real entry point |
| [proximity_app/lib/core/router/app_router.dart](../../proximity_app/lib/core/router/app_router.dart) | Added `/account`, `/rider/onboarding` |
| [proximity_app/lib/shared/widgets/app_shell.dart](../../proximity_app/lib/shared/widgets/app_shell.dart) | Avatar tap now routes to `/account` instead of straight to `/addresses` |

**Verified:** `flutter analyze` — 0 errors, 0 warnings, 10 info-level style lints (up from Sprint 1's 5; the two new categories — `prefer_initializing_formals`, `use_null_aware_elements` — match existing, previously-accepted style in this codebase, not fixed here either).
**Not verified:** never run on a device, KYC upload never exercised against a real Storage bucket, rider signup never exercised against a real backend.

### Web app (`proximity_web/`) — new this sprint

Scaffolded via `create-next-app` (Next.js 16.3.5 after the security fix below, TypeScript, Tailwind v4, App Router, no `src/` dir), structurally reusing `baker_ally_admin`'s proven Next.js 16 + `@supabase/ssr` wiring (§9 reuse map) rather than guessing at Next.js 16 conventions from training data — e.g. `middleware.ts` renamed to `proxy.ts` (exported function literally named `proxy`) was confirmed by reading `baker_ally_admin`'s own real, running file, not assumed.

| File | Purpose |
|---|---|
| [proximity_web/proxy.ts](../../proximity_web/proxy.ts) | Next.js 16's `middleware.ts` replacement |
| [proximity_web/lib/supabase/client.ts](../../proximity_web/lib/supabase/client.ts), [server.ts](../../proximity_web/lib/supabase/server.ts), [proxy.ts](../../proximity_web/lib/supabase/proxy.ts) | Browser/server Supabase clients + the session-refresh-and-role-gate logic `proxy.ts` calls |
| [proximity_web/lib/api-core.ts](../../proximity_web/lib/api-core.ts), [api.ts](../../proximity_web/lib/api.ts), [api-client.ts](../../proximity_web/lib/api-client.ts) | Server/browser split for calling `proximity_backend`, same shape as `baker_ally_admin`'s |
| [proximity_web/lib/auth.ts](../../proximity_web/lib/auth.ts) | `requireUser()`, `requireAdmin()`, `requireShop()` — the last one checks real `shop_team_members` membership via `GET /v1/shop/shops/mine`, not the JWT role claim (§1.2: staff/delivery never get a global role change) |
| [proximity_web/lib/types.ts](../../proximity_web/lib/types.ts) | Mirrors backend response shapes; Postgres `numeric` columns typed as `string`, matching Drizzle's actual default behavior |
| [proximity_web/lib/nav.ts](../../proximity_web/lib/nav.ts) | Admin nav (Shops, Riders) / dashboard nav (Overview) — deliberately minimal, matches this sprint's actual scope |
| [proximity_web/components/ui/*.tsx](../../proximity_web/components/ui/button.tsx) | `button`/`input`/`label`/`card`/`badge` — **hand-written**, not fetched via the `shadcn` CLI (see "Bugs caught" #6 for why) |
| [proximity_web/components/app-nav.tsx](../../proximity_web/components/app-nav.tsx), [sign-out-button.tsx](../../proximity_web/components/sign-out-button.tsx) | Plain top-nav shell, not the shadcn `Sidebar` primitive — simpler shape for a "panel skeleton," revisit if the nav grows |
| [proximity_web/app/login/page.tsx](../../proximity_web/app/login/page.tsx) | Email+password sign-in (deliberately different primitive from the buyer app's Email OTP — a business dashboard, not a consumer one-time flow) |
| [proximity_web/app/signup/page.tsx](../../proximity_web/app/signup/page.tsx) | Shopkeeper self-registration; handles Supabase's "confirm email" setting explicitly rather than assuming a session comes back immediately |
| [proximity_web/app/onboarding/shop/page.tsx](../../proximity_web/app/onboarding/shop/page.tsx) + [shop-creation-form.tsx](../../proximity_web/app/onboarding/shop/shop-creation-form.tsx) | §8.1's shop creation form — name/address/GSTIN/FSSAI/service radius/pickup+delivery/delivery-mode/min-order/7-day business hours. Lat/lng are manual number inputs, not geocoded — no Maps/Geocoding API key exists yet (see "Not yet built") |
| [proximity_web/app/onboarding/pending/page.tsx](../../proximity_web/app/onboarding/pending/page.tsx) | Status page while `shops.status` is `pending`/`suspended` |
| [proximity_web/app/dashboard/layout.tsx](../../proximity_web/app/dashboard/layout.tsx) + [page.tsx](../../proximity_web/app/dashboard/page.tsx) | Shop-status overview only — catalog/orders/sales/team are Sprint 3+ |
| [proximity_web/app/admin/layout.tsx](../../proximity_web/app/admin/layout.tsx) + [page.tsx](../../proximity_web/app/admin/page.tsx) | Admin-only gate + redirect to the shops queue |
| [proximity_web/app/admin/shops/page.tsx](../../proximity_web/app/admin/shops/page.tsx) + [shops-client.tsx](../../proximity_web/app/admin/shops/shops-client.tsx) | Shop approval queue — tabs by status, approve/suspend |
| [proximity_web/app/admin/riders/page.tsx](../../proximity_web/app/admin/riders/page.tsx) + [riders-client.tsx](../../proximity_web/app/admin/riders/riders-client.tsx) | Rider approval queue — tabs by verified state, approve/revoke, flags whether a KYC document was uploaded (no inline preview yet) |
| [proximity_web/app/unauthorized/page.tsx](../../proximity_web/app/unauthorized/page.tsx) | — |

**Verified:** `npm run build` (Next.js 16.3.5, Turbopack) — compiles, typechecks, generates all 10 routes + the proxy middleware correctly. `npm run lint` — clean. `npm audit` — 0 vulnerabilities (after the fix below).
**Not verified:** never pointed at a real `.env.local`, never deployed, no page has been opened in a browser against a live backend.

## Bugs caught and fixed during implementation

1. **`shops`' own RLS policies couldn't reference `shop_team_members` in the same migration that creates `shops`** — `shop_team_members` FKs to `shops(id)`, so it must come after; but two of `shops`' policies (`shops_select_team`, `shops_owner_update`) need `shop_team_members` to exist. Resolved by splitting: 006 creates `shops` with only its two membership-independent policies (public-approved-read, admin-all), and 007 adds the other two once `shop_team_members` exists. Documented in both files so it doesn't read as an oversight later.

2. **§4.7's literal `riders` DDL has no column for the KYC document it says gets uploaded.** SPRINT_PLANNING.md §4.7's prose (and §3.6's bucket name) both assume a document reference gets stored somewhere, but the `CREATE TABLE` block there never names one. Added `kyc_document_url` (deliberately just one column, not a documents table, per this sprint's "(mobile, minimal)" scope) — caught while wiring the actual signup route, same kind of gap-before-it-breaks catch as Sprint 1's `shop_team_members` sequencing bug.

3. **RPC-returned rows come back snake_case, not camelCase, through this backend's raw `db.execute(sql...)` path** — same landmine `rpc_set_default_address` left in Sprint 1 (worked around client-side there, in `Address.fromJson`, rather than fixed). Rather than carry that same inconsistency into two more RPCs, `POST /shop/shops` and `POST /rider/riders` now re-select the created row through Drizzle's schema-mapped `.select()` before responding, so every response in this codebase is camelCase going forward. `rpc_set_default_address`'s existing behavior was left alone (out of scope, still relied on by the Sprint 1 Flutter code's fallback).

4. **The `rider-documents` Storage bucket never actually existed.** Named in §3.6 since before Sprint 1, referenced in §4.7's onboarding description, but no migration had ever created it or its RLS policies — "private" was a comment, not an enforced property. Added migration 016: the bucket itself, own-folder read/write policies keyed on `(storage.foldername(name))[1] = auth.uid()::text`, and a read-only admin policy so KYC review is actually possible.

5. **`google_sign_in`-style verification discipline applied to Next.js 16 too, and it mattered:** `middleware.ts` is gone in Next.js 16 — replaced by `proxy.ts` exporting a function literally named `proxy`. Confirmed by reading `baker_ally_admin`'s own real `proxy.ts` (a working Next.js 16 project) rather than assumed from older Next.js training data. Same for the exact `@supabase/ssr` cookie-handling shape (`getClaims()`, the "don't run code between `createServerClient` and `getClaims()`" warning) — copied from a proven, running reference rather than reconstructed from memory.

6. **shadcn CLI deliberately not used, a real environment-driven decision, not laziness:** `npx shadcn add ...` needs a live registry round-trip on top of an `npm install` that had *already* shown real file-system flakiness in this exact folder (see the OneDrive section above). Rather than add a second flaky network dependency for component source this small, `components/ui/{button,input,label,card,badge}.tsx` were hand-written to the same shape the CLI would generate (`cva` variants, `cn` helper, no Radix). If a redesign wants Radix-backed primitives (Dialog, Sheet, real Sidebar) later, running the actual CLI is still on the table — this wasn't a permanent architectural call, just this sprint's pragmatic one given the environment.

7. **Critical Next.js CVE caught by `npm audit` before this was called done, not after:** the exact pinned version (`16.3.2`) has a published unauthenticated RCE advisory (Windows-hosted servers) plus a second RCE in the AVIF image-optimization path. Bumped to `16.3.5` (patch only, no breaking change) in `package.json` and `eslint-config-next` alongside it; re-verified `0 vulnerabilities` afterward. Worth remembering for every future `npm install` in this project: check `npm audit`, don't just check that the install "succeeded."

8. **`npm install` reporting success while silently installing almost nothing** happened twice in this sprint (once on OneDrive, once even after moving off it) — `next`/`eslint` would land, but `react`, `@supabase/*`, `tailwindcss`, and everything else would simply be missing from `node_modules` despite an `added N packages ... 0 vulnerabilities` exit message. The only reliable check turned out to be: after any install, actually `ls` for a handful of specific expected packages (not just a total count, and not just trusting the exit code) before treating the install as real.

## Exit criteria check

| Criterion | Status |
|---|---|
| A shop can be created | Code complete (`rpc_create_shop`, `POST /v1/shop/shops`, the web onboarding form) and build/typecheck-verified. **Cannot execute** until migrations 006–016 are applied to the live Supabase project. |
| ...and reaches `status='pending'` | `shops.status` defaults to `'pending'` at the DB level (migrations/006); logic verified by reading, not executed. |
| A rider can be created | Code complete (`rpc_create_rider_profile`, `POST /v1/rider/riders`, the mobile onboarding screen) and `flutter analyze`-verified. **Cannot execute** until the same migrations are live and the `rider-documents` bucket actually exists. |
| ...and reaches `is_verified=false` | `riders.is_verified` defaults to `false` at the DB level (migrations/011); logic verified by reading, not executed. |
| Admin can approve both | `proximity_web`'s `/admin/shops` and `/admin/riders` queues are build-verified against the real route shapes in `routes/admin.ts`. **Cannot execute** until an admin account exists (no self-serve admin signup by design — needs a manual `role='admin'` promotion after someone signs up) and the backend is deployed and reachable. |

**Bottom line: Sprint 2 is development-complete and internally verified at every layer this project has tooling for (deno check, flutter analyze, next build/lint/audit)** — the remaining gap is entirely "this hasn't touched a real, running system yet," which was always the correctly-identified dependency, not a shortcut taken.

## Not yet built (by design, deferred to the sprint that actually needs it)

- Routes/UI for `shop_media`, `shop_sub_categories`, `shop_blackout_dates` — tables exist (migrations 009/010/013), consumed starting Sprint 3 (catalog) and Sprint 7 (fulfillment slots).
- A `GET`/`PATCH` route for `platform_settings` — seeded (migration 012), no reader yet; the real settings-editor UI is Sprint 12's job per §11.
- Geocoding on the shop-creation form — lat/lng are plain manual number inputs because no Google Maps/Geocoding API key exists yet (unchanged from Sprint 0/1's status). Swap this out the moment that credential exists.
- Inline KYC document preview in the admin riders queue — it shows "Uploaded"/"Missing" only; actually viewing the image needs a `createSignedUrl` call against the private bucket, not built this sprint.
- Team invites (`shop_team_members` rows for `staff`/`delivery`, §8.3) — only the owner-creates-a-shop path exists; invite flow is implied by later sprints' dashboard work.

## What Sprint 3 needs from you before it can be verified either

Same shape as Sprints 1 and 2: catalog/inventory code can all be written without a live Supabase project, but none of it — Sprint 2's either — becomes a provably working product until migrations `006`–`016` are actually applied and at least one real shop/rider/admin account exists to exercise the approval loop end to end.

---

**Waiting for your go-ahead before starting Sprint 3**, per your instruction to stop at sprint boundaries.
