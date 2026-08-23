# Sprint 1 — Identity, Roles, Geo Core

**Status: code complete and self-verified, not yet verified against live infrastructure.**
No Supabase project exists yet (you're providing that later), so nothing here has actually executed against a real database, and no Google/Apple OAuth credentials exist yet, so those two sign-in paths are correct against the real package APIs but have never run end to end. Everything else — file structure, compilation, type-checking — is verified, not assumed. See "What's actually verified" below before treating anything past that line as working.

Written for a future LLM session (or you) to pick this project back up without re-reading the whole planning conversation — if you're that session, start here, then `SPRINT_PLANNING.md` §11's Sprint 1 entry, then `Sprint 0.md` for what was already true about this machine before this sprint started.

## Goal (from SPRINT_PLANNING.md §11)

> Migrations already drafted and committed (000–004): postgis/pg_cron/pg_net extensions, users, addresses (w/ PostGIS location), categories (seeded, 20-item list), custom_access_token_hook + get_role() helper. shop_team_members moved to Sprint 2. RLS baseline policies. Auth in proximity_app: Email OTP, Google Sign-In, Apple Sign-In. First end-to-end RPC: rpc_set_default_address. Exit criteria: a real user can sign up on both platforms, has a role, has an address with a resolved lat/lng.

## What was built

### Migrations (`migrations/`)

| File | Purpose |
|---|---|
| [migrations/000_enable_extensions.sql](../../migrations/000_enable_extensions.sql) | postgis, pg_cron, pg_net |
| [migrations/001_create_users.sql](../../migrations/001_create_users.sql) | `users` table + own-row RLS policies |
| [migrations/002_create_addresses.sql](../../migrations/002_create_addresses.sql) | `addresses` w/ `GEOGRAPHY(Point,4326)` + GIST index |
| [migrations/003_create_categories.sql](../../migrations/003_create_categories.sql) | `categories` + full 20-item seed list |
| [migrations/004_create_custom_jwt_claims_hook.sql](../../migrations/004_create_custom_jwt_claims_hook.sql) | `custom_access_token_hook` (role → JWT) + `get_role()` helper |
| [migrations/005_rpc_set_default_address.sql](../../migrations/005_rpc_set_default_address.sql) | The Sprint 1 proof RPC — see "Bugs caught" below, this one has a real story |

**Not yet run.** Apply in order via `supabase db query -f "migrations/00N_x.sql" --linked` once a project is linked, per `SPRINT_PLANNING.md` §3.5's stated migration workflow. `004` also needs the one manual dashboard step the file itself documents (Authentication → Hooks → select `custom_access_token_hook`) — cannot be done via SQL alone, same limitation Baker Ally hit.

### Backend (`proximity_backend/`)

| File | Purpose |
|---|---|
| [proximity_backend/deno.json](../../proximity_backend/deno.json) | Import map (hono, zod, drizzle-orm, postgres, supabase-js) |
| [proximity_backend/.env.example](../../proximity_backend/.env.example) | Secrets template — `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `DB_POOL_URL`, `ADMIN_WEB_ORIGIN` |
| [proximity_backend/supabase/functions/api/index.ts](../../proximity_backend/supabase/functions/api/index.ts) | Mounts all routes, one Edge Function, same shape as Baker Ally's `index.ts` |
| [proximity_backend/supabase/functions/api/lib/supabaseAdmin.ts](../../proximity_backend/supabase/functions/api/lib/supabaseAdmin.ts) | Service-role client, used only for `auth.getUser(token)` |
| [proximity_backend/supabase/functions/api/lib/db.ts](../../proximity_backend/supabase/functions/api/lib/db.ts) | Drizzle + postgres.js over the Supavisor pooler — **this file's comment is the reason `rpc_set_default_address` looks the way it does, read it if anything RPC-related seems odd later** |
| [proximity_backend/supabase/functions/api/middleware/auth.ts](../../proximity_backend/supabase/functions/api/middleware/auth.ts) | `authMiddleware` (the actual trust boundary) + `requireRole` |
| [proximity_backend/supabase/functions/api/db/schema.ts](../../proximity_backend/supabase/functions/api/db/schema.ts) | Drizzle schema for `users`/`addresses`/`categories` — Sprint 1 subset only, grows with each migration sprint |
| [proximity_backend/supabase/functions/api/routes/health.ts](../../proximity_backend/supabase/functions/api/routes/health.ts) | `GET /v1/health` |
| [proximity_backend/supabase/functions/api/routes/auth.ts](../../proximity_backend/supabase/functions/api/routes/auth.ts) | `POST /v1/auth/me` — idempotent signup-hook replacement |
| [proximity_backend/supabase/functions/api/routes/categories.ts](../../proximity_backend/supabase/functions/api/routes/categories.ts) | `GET /v1/categories` — public, unauthenticated |
| [proximity_backend/supabase/functions/api/routes/addresses.ts](../../proximity_backend/supabase/functions/api/routes/addresses.ts) | Full CRUD + `POST /addresses/:id/default` (the RPC-backed one) |

**Verified:** `deno check supabase/functions/api/index.ts` passes clean, no type errors, run twice (once after the initial pass, once after `addresses.ts`/`index.ts` were added).
**Not verified:** never deployed, never received a real request, never connected to a real database.

### Mobile app (`proximity_app/`)

Scaffolded via `flutter create --org com.proximity --project-name proximity_app`, targets `android,ios` only (no web/desktop). Bundle id `com.proximity.app`, confirmed by you.

| File | Purpose |
|---|---|
| [proximity_app/pubspec.yaml](../../proximity_app/pubspec.yaml) | Full dependency list, all versions resolved live against pub.dev (see "Bugs caught" — do not assume these version numbers, re-check `flutter pub outdated` if this file is read much later) |
| [proximity_app/.env.example](../../proximity_app/.env.example) | Supabase URL/anon key, API base URL, Google + Apple sign-in config, each with a comment on why it needs what it needs |
| [proximity_app/lib/core/config/env.dart](../../proximity_app/lib/core/config/env.dart) | envied config class |
| [proximity_app/lib/core/theme/app_theme.dart](../../proximity_app/lib/core/theme/app_theme.dart) | Design system from `SPRINT_PLANNING.md` §6 — teal/marigold/terracotta, Baloo 2 + Plus Jakarta Sans |
| [proximity_app/lib/core/platform/platform_info.dart](../../proximity_app/lib/core/platform/platform_info.dart) | The one centralized platform-branch point, per `SPRINT_PLANNING.md` §1.1's "keep code organised" instruction — first (and so far only) consumer is Apple sign-in |
| [proximity_app/lib/core/storage/secure_storage.dart](../../proximity_app/lib/core/storage/secure_storage.dart) | JWT storage |
| [proximity_app/lib/core/network/dio_client.dart](../../proximity_app/lib/core/network/dio_client.dart) | Dio + auth interceptor — every business-data request goes through this |
| [proximity_app/lib/core/providers.dart](../../proximity_app/lib/core/providers.dart) | Root Riverpod providers |
| [proximity_app/lib/core/router/app_router.dart](../../proximity_app/lib/core/router/app_router.dart) | GoRouter — `/login`, `/addresses`, `/addresses/new`, + the 4-tab shell (`/`, `/categories`, `/cart`, `/order-again`, all placeholders until their real sprints) |
| [proximity_app/lib/shared/widgets/app_shell.dart](../../proximity_app/lib/shared/widgets/app_shell.dart) | Bottom-nav shell, 4 tabs, no cart icon in the top bar (per your original instruction) |
| [proximity_app/lib/shared/widgets/placeholder_screen.dart](../../proximity_app/lib/shared/widgets/placeholder_screen.dart) | Stand-in for Home/Categories/Cart/Order Again until Sprints 3/4/6/10 |
| [proximity_app/lib/features/auth/data/auth_repository.dart](../../proximity_app/lib/features/auth/data/auth_repository.dart) | Email OTP + native Google + native Apple, all three — **read this file's header comment, it explains a deliberate deviation from Baker Ally's Google flow** |
| [proximity_app/lib/features/auth/presentation/auth_provider.dart](../../proximity_app/lib/features/auth/presentation/auth_provider.dart) | `AuthNotifier`/`authProvider` — session sync, role hydration |
| [proximity_app/lib/features/auth/presentation/login_screen.dart](../../proximity_app/lib/features/auth/presentation/login_screen.dart) | Email field + Google button + native Apple button |
| [proximity_app/lib/features/auth/presentation/email_otp_screen.dart](../../proximity_app/lib/features/auth/presentation/email_otp_screen.dart) | 6-digit code entry |
| [proximity_app/lib/features/profile/data/models/user_profile.dart](../../proximity_app/lib/features/profile/data/models/user_profile.dart) | Smaller than Baker Ally's — no businessName/gstin, those are shop fields now |
| [proximity_app/lib/features/addresses/data/models/address.dart](../../proximity_app/lib/features/addresses/data/models/address.dart) | Note the GeoJSON `[lng, lat]` vs request-body `{lat, lng}` order handling in the comment |
| [proximity_app/lib/features/addresses/data/location_service.dart](../../proximity_app/lib/features/addresses/data/location_service.dart) | GPS + on-device geocoding, no Maps API key needed yet |
| [proximity_app/lib/features/addresses/data/address_repository.dart](../../proximity_app/lib/features/addresses/data/address_repository.dart) | Dio calls to `/v1/addresses*` |
| [proximity_app/lib/features/addresses/presentation/providers/address_providers.dart](../../proximity_app/lib/features/addresses/presentation/providers/address_providers.dart) | — |
| [proximity_app/lib/features/addresses/presentation/screens/address_list_screen.dart](../../proximity_app/lib/features/addresses/presentation/screens/address_list_screen.dart) | — |
| [proximity_app/lib/features/addresses/presentation/screens/address_form_screen.dart](../../proximity_app/lib/features/addresses/presentation/screens/address_form_screen.dart) | "Use current location" + manual entry, both paths |
| [proximity_app/lib/main.dart](../../proximity_app/lib/main.dart) | Supabase.initialize + GoogleSignIn.instance.initialize, in that order — order matters, see the comment |

**Verified:** `flutter analyze` — 0 errors, 0 warnings, 5 info-level style lints (all `prefer_initializing_formals`, matching Baker Ally's own established constructor style — not fixed, treated as intentional). `dart run build_runner build` succeeds and generates `env.g.dart`.
**Not verified:** never run on a device or emulator, never connected to real Supabase Auth, Google/Apple sign-in never actually exercised end to end.

## Bugs caught and fixed during implementation (read this before changing any of the files above)

These aren't hypothetical — each one was a real error until fixed, caught by actually reading source and running `deno check`/`flutter analyze` rather than assuming the code was right. Documented here so nobody "fixes" the code back to the wrong version later.

1. **`rpc_set_default_address` relying on `auth.uid()` — would have silently rejected its own caller.** `proximity_backend` connects to Postgres with the service-role key over a direct pooler connection (confirmed by reading Baker Ally's `lib/db.ts`/`lib/supabaseAdmin.ts`), never through PostgREST — so `auth.uid()` is always NULL in that context. Fixed: the RPC takes `p_user_id` as an explicit parameter instead, trusting the Edge Function's own `authMiddleware` (which already verified the JWT) rather than a GUC that's never set. This also required correcting `SPRINT_PLANNING.md` §5.1 itself, which originally said the client could call `supabase.rpc()` directly for simple cases — wrong for this backend's connection shape. Now: **all business data and all RPC calls go through Dio → the Edge Function, no exceptions**, one trust boundary instead of two.

2. **`shop_team_members` was scheduled for Sprint 1 in the original plan but references `shops(id)`, which doesn't exist until Sprint 2.** Caught before writing broken SQL. Moved to Sprint 2. The Sprint 1 "proof RPC" also got swapped from the originally-planned `rpc_add_to_cart` (needs tables that don't exist until Sprint 3/6) to `rpc_set_default_address`.

3. **`StateNotifier`/`StateNotifierProvider` don't exist in the resolved Riverpod version.** `flutter_riverpod` resolved to `^3.4.2` (much newer than Baker Ally's pinned `^2.6.1`), and Riverpod 3.x moved `StateNotifier` out of the main package entry point — the plain `Notifier`/`NotifierProvider` there are for `riverpod_generator`'s codegen, not hand-writing (their own source literally says "not meant for public consumption"). Fix: import `package:flutter_riverpod/legacy.dart` alongside the main package — `StateNotifier`/`StateNotifierProvider` are still fully supported there, just reorganized, not deprecated. `auth_provider.dart`'s import comment explains this.

4. **`riverpod_generator` and `envied_generator` had a real, live version conflict** (`riverpod_generator`'s latest releases cap out needing `riverpod_annotation` ≤4.0.3, but `flutter pub add` initially resolved `riverpod_annotation` to `^4.0.6`). Resolved by dropping `riverpod_annotation`/`riverpod_generator` entirely rather than fighting the resolver — Baker Ally's own code never actually used `@riverpod` codegen syntax despite having the dependency, so nothing was lost. `build_runner`/`envied_generator` kept (needed for `.env` codegen).

5. **`google_sign_in` v7 has a completely different API than the version Baker Ally used.** Baker Ally's `signInWithOAuth(OAuthProvider.google, redirectTo: ...)` browser-redirect pattern would still technically work, but the resolved `google_sign_in: ^7.2.0` uses a redesigned native API (`GoogleSignIn.instance.initialize()` once at startup, `.authenticate()`, `account.authentication.idToken`) — verified by reading the actual installed package source and `MIGRATION.md`, not assumed from training data. Used natively for both Google and Apple (see bug 6) rather than mixing a native Apple flow with a browser-redirect Google flow.

6. **Deliberate deviation, not a bug, but worth flagging as a real design decision:** Apple's App Store Review Guideline 4.8 requires Sign in with Apple wherever another social login exists, and expects comparable UX quality — a browser-tab Google flow next to a native Face-ID Apple sheet would read as inconsistent. So both providers use native SDKs feeding Supabase's `signInWithIdToken`, not `signInWithOAuth`.

7. **`sign_in_with_apple` requires `webAuthenticationOptions` on Android** (no native OS-level Apple auth there — it falls back to a Chrome Custom Tab web flow, confirmed by reading the package source directly) **and must NOT receive it on iOS** (would force the web flow instead of the native sheet). This is exactly the kind of platform branch `SPRINT_PLANNING.md` §1.1 said should live in one centralized place — it's why [platform_info.dart](../../proximity_app/lib/core/platform/platform_info.dart) exists now instead of an inline `Platform.isIOS` check.

8. **`geocoding` v5 changed from a static-function API to an instance-based `Geocoding()` class** (`Geocoding().locationFromAddress(...)`, `.placemarkFromCoordinates(...)`) — again verified against the actual installed package source rather than assumed.

9. **GeoJSON coordinate order.** PostGIS/postgres.js round-trips `location` as GeoJSON, which orders coordinates `[lng, lat]` — the opposite of the `{lat, lng}` shape the POST body accepts. Handled explicitly in `Address.fromJson`'s comment rather than left as a silent "valid-looking numbers, wrong location" bug.

## Real shortcoming found in Baker Ally along the way (not fixed there — you asked not to touch that repo)

`baker_ally_backend/supabase/functions/api/routes/addresses.ts`'s default-address logic does three sequential, non-transactional Drizzle statements (select → conditional update → insert/update) with no `db.transaction()` — a real race condition on rapid duplicate requests. `rpc_set_default_address` above exists specifically to not repeat this. Full writeup with two more (self-documented) Baker Ally trade-offs is in this session's chat history, not duplicated into a file since you asked for it in chat specifically.

## Exit criteria check

| Criterion | Status |
|---|---|
| A real user can sign up (Email OTP) | Code complete, correct against real Supabase Auth API shape. **Cannot execute** until a Supabase project exists. |
| A real user can sign up (Google) | Code complete, correct against the real installed `google_sign_in` v7 API. **Cannot execute** until Google Cloud OAuth client + `GOOGLE_SERVER_CLIENT_ID` exist. |
| A real user can sign up (Apple) | Code complete on iOS (native, no extra config needed beyond the entitlement, not yet added to the Xcode project). Android path additionally needs `APPLE_SERVICE_ID`/`APPLE_REDIRECT_URI` from Apple Developer, not yet created. |
| Has a role | `users.role` defaults to `'buyer'` at the DB level, hydrated via `/v1/auth/me`, surfaced in `AuthSessionState.role`. Logic verified by reading; **not executed**. |
| Has an address with resolved lat/lng | Full add-address flow (GPS or manual+geocode), backend persists via PostGIS. Logic verified by reading and by `flutter analyze`/`deno check`; **not executed**. |

**Bottom line: Sprint 1 is code-complete, not "done" in the sense of a verified working product** — that verification step is blocked entirely on the Supabase project and OAuth credentials you're providing later. Nothing about that gap is a shortcut taken; it's the actual, correctly-identified dependency this sprint always had.

## What Sprint 2 needs from you before it can be verified either

Same shape as this sprint: I can write all of Sprint 2's code (shop onboarding, `shops`/`shop_team_members`/`riders`/`platform_settings` migrations, `proximity_web` scaffolding) without any live account existing, but none of it will be *runnable* until the Supabase project lands, and the shop/rider approval flow specifically also wants at least a placeholder admin identity to approve against.

---

**Waiting for your go-ahead before starting Sprint 2**, per your instruction to stop at sprint boundaries.
