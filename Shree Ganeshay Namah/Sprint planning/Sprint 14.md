# Sprint 14 — Password auth & account recovery

**Status: mobile-side code complete, `flutter analyze`-clean (same 33 pre-existing info-level lints Sprint 13.md accepted, 0 new), rebuild against the real connected device (motorola edge 70) kicked off at the end of this sprint but its outcome wasn't yet known when this file was written — see `SPRINT_PLANNING.md`'s own Sprint 14 entry for why this sprint exists (inserted after the original plan; the previously-numbered "iOS build & store submission" sprint is now Sprint 15, not dropped).**

Not pre-planned in `SPRINT_PLANNING.md`'s original §11 draft — added directly at your request, mid-session, once real on-device testing (the first in this project's history, same session as Sprint 13's actual device run) surfaced that the existing passwordless email-OTP-every-time flow wasn't what you wanted for this app. `proximity_backend/` and `migrations/` are untouched this sprint — Supabase Auth's own `signUp`/`signInWithPassword`/`resetPasswordForEmail`/`verifyOTP`/`updateUser` cover the whole ask natively; this is a `proximity_app/`-only sprint.

## Goal (given directly, not from a pre-written §11 entry)

Replace "sign in by requesting a fresh OTP every time" with three separate flows:
1. **Sign up** — email + password, confirmed by a 6-digit OTP (so a typo'd email can't silently create an unreachable account).
2. **Sign in** — email + password only, no OTP round trip, for any already-confirmed account.
3. **Forgot password** — email → OTP code → new password, self-service, no support contact needed.

Plus: confirm the app already stays signed in indefinitely until a manual sign-out (it does — see below), since that was asked for explicitly and is easy to accidentally regress with an auth rewrite.

## What was built

| File | Purpose |
|---|---|
| [auth_repository.dart](../../proximity_app/lib/features/auth/data/auth_repository.dart) | Replaced `sendEmailOtp`/`verifyEmailOtp` (passwordless, `OtpType.email`) with six methods: `signUpWithPassword` (`auth.signUp`), `verifySignupOtp` (`verifyOTP(type: OtpType.signup)`), `signInWithPassword` (`auth.signInWithPassword`), `sendPasswordResetOtp` (`auth.resetPasswordForEmail`), `verifyPasswordResetOtp` (`verifyOTP(type: OtpType.recovery)`), `updatePassword` (`auth.updateUser(UserAttributes(password: ...))`). |
| [auth_provider.dart](../../proximity_app/lib/features/auth/presentation/auth_provider.dart) | Same six methods exposed through `AuthNotifier`, one-line pass-throughs to the repository — no state-shape changes, `AuthSessionState` is unchanged. |
| [login_screen.dart](../../proximity_app/lib/features/auth/presentation/login_screen.dart) | Rewritten: email + password fields, "Sign in" button (`signInWithPassword`), a "Forgot password?" link, and a "New here? Create an account" link — Google/Apple buttons unchanged from Sprint 1. |
| [sign_up_screen.dart](../../proximity_app/lib/features/auth/presentation/sign_up_screen.dart) | New. Email + password + confirm-password → `signUpWithPassword` → pushes `EmailOtpScreen` (replaces itself in the stack, so a successful verify pops back to `LoginScreen`, not to the sign-up form). |
| [email_otp_screen.dart](../../proximity_app/lib/features/auth/presentation/email_otp_screen.dart) | Repurposed, not replaced: same 6-digit code UI, but now calls `verifySignupOtp` instead of the old `verifyEmailOtp` — signup confirmation only, no longer doubling as a passwordless sign-in step. |
| [forgot_password_screen.dart](../../proximity_app/lib/features/auth/presentation/forgot_password_screen.dart) | New. One screen, state-gated in two halves (`_codeSent`): email → `sendPasswordResetOtp`, then code + new password + confirm → `verifyPasswordResetOtp` followed by `updatePassword`. Deliberately does not force a second sign-in afterward — `verifyPasswordResetOtp` already leaves a real session active, consistent with this sprint's "stay signed in" requirement. |

**Session persistence — checked, not built:** `main.dart`'s `Supabase.initialize(url: ..., publishableKey: ...)` passes no custom `authOptions`, so it already uses `supabase_flutter`'s default local session storage and auto-refresh — a signed-in session survives an app restart and stays valid until `AuthRepository.signOut()` is called. Nothing needed changing for the "stay signed in until manual sign-out" requirement; confirmed by reading `main.dart` and the `supabase_flutter` init contract, not assumed.

## What this sprint could verify by reading/reasoning alone, vs. what's blocked on a real device

| Part of this sprint's scope | Checkable by reading/reasoning alone? |
|---|---|
| `flutter analyze` cleanliness | **Yes** — ran directly, 0 errors/warnings, same accepted 33 info-level lints as Sprint 13. |
| Supabase API call shapes (`signUp`/`signInWithPassword`/`resetPasswordForEmail`/`verifyOTP`/`updateUser`) | **Yes** — all six are documented, stable `gotrue`/`supabase_flutter` public API, matching this project's already-live `verifyOTP(type: OtpType.email)` precedent from before this sprint. |
| Session-persistence behavior | **Yes** — `Supabase.initialize` call site inspected directly; no override present. |
| The actual sign-up → OTP → sign-in → sign-out → sign-in-with-password round trip on a real device | **No — needs your phone.** Rebuild was still running when this file was written; you're the first person to actually exercise this flow. |
| Whether the Supabase project's **"Confirm signup"** and **"Reset Password"** email templates show the OTP code | **No — dashboard setting, same gotcha as the Magic Link template you already had to fix.** See "One more dashboard step" below — almost certainly needed before sign-up or forgot-password will be usable at all. |

## One more dashboard step you'll likely need (same shape as the Magic Link fix)

Supabase's default **"Confirm signup"** and **"Reset Password"** email templates, like the Magic Link one you already edited, only show a clickable link by default — not the raw `{{ .Token }}` code this app's screens ask you to type in. Before testing sign-up or forgot-password, check Dashboard → Authentication → Email Templates → **Confirm signup** and **Reset Password**, and add `{{ .Token }}` to each body the same way you already did for Magic Link. (Sign-in itself doesn't need this — it's password-only now, no email round trip.)

## Real bugs found during actual end-to-end testing (added after this sprint's first write-up)

Everything below was found only once a real browser and a real phone actually exercised these paths against the live `lipxvdzauddpmcpilrsw` project — none of it was visible from reading code alone, which is exactly why this project's own standing rule treats "never run against a live Supabase project/physical device" as a real, named gap rather than a formality. Each of these was a genuine defect, not a config choice, fixed in place (see each file's own header comment for the full account):

| File | Bug | Fix |
|---|---|---|
| [migrations/014_rpc_create_shop.sql](../../migrations/014_rpc_create_shop.sql) | Business-hours JSONB parsed with snake_case keys (`opens_at`/`closes_at`/`is_closed`) against this backend's own camelCase convention (`opensAt`/`closesAt`/`isClosed`, matching `shop-creation-form.tsx`) -- every real shop registration failed a CHECK constraint. | Reads the correct camelCase keys. |
| [migrations/004_create_custom_jwt_claims_hook.sql](../../migrations/004_create_custom_jwt_claims_hook.sql) | `custom_access_token_hook` had `GRANT EXECUTE` for `supabase_auth_admin` but no `GRANT SELECT` on `users`, and no RLS policy admitting that role -- enabling the hook made every sign-in fail outright ("Error running hook"). | Added the missing `GRANT SELECT` + a `supabase_auth_admin`-scoped RLS policy, matching Supabase's own documented pattern for this hook. |
| [middleware/auth.ts](../../proximity_backend/supabase/functions/api/middleware/auth.ts) | `authMiddleware` read `app_metadata.role` off `supabaseAdmin.auth.getUser(token)`'s result -- which reflects `auth.users`' persisted `app_metadata`, not the claims the hook injects only into the JWT payload itself (a real, documented Supabase limitation). Every `requireRole()`/`adminMiddleware`-gated route always returned "Insufficient role," for anyone, regardless of their real role. | Decodes the token's own payload directly (already verified authentic by the `getUser()` call above) and merges its `app_metadata` over the DB-sourced one. |
| [auth_provider.dart](../../proximity_app/lib/features/auth/presentation/auth_provider.dart) `_sync()` | The one call in this function with no try/catch (`syncSessionToStorage()`, writing to `flutter_secure_storage`/Android Keystore) -- if it throws, `state` never updates to `isLoggedIn: true` and `isLoading` sticks at its default `true` forever, which `app_router.dart`'s redirect explicitly refuses to act on. A real, successful Supabase sign-in silently never took the user anywhere. | Wrapped in try/catch, matching `hydrateProfile()`'s already-tolerant handling two lines below it. |
| [home_screen.dart](../../proximity_app/lib/features/home/presentation/screens/home_screen.dart) `_LocationPrompt` | The "Add an address" button pushed `/addresses/new` and never invalidated `addressesProvider` on return, unlike `address_list_screen.dart`'s own "Add address" FAB (which gets this right) and unlike this same prompt's own "Enable location" button right above it. A newly-saved address never made the "no location" empty state go away without an unrelated pull-to-refresh. | Awaits the push result and invalidates `addressesProvider` on success, matching the already-correct pattern elsewhere in this codebase. |
| [home_screen.dart](../../proximity_app/lib/features/home/presentation/screens/home_screen.dart) `_RecommendedSection`/`_FrequentlyBoughtSection` | `childAspectRatio` is cross-axis-extent ÷ main-axis-extent; for these *horizontally*-scrolling grids the cross axis is height and the main axis is width, so `childAspectRatio: 0.72` actually computed each card's **width** as `height ÷ 0.72` (~257dp wide against a ~185dp-tall row) -- a card far wider than tall, asked to hold a square image plus three text lines. Real overflow (Flutter's debug-mode yellow/black stripes, "BOTTOM OVERFLOWED BY 138 PIXELS"), not cosmetic -- this section had never rendered on a real screen before this sprint. | Replaced `childAspectRatio` with an explicit `mainAxisExtent: 150` (card width, unambiguous regardless of scroll direction) and increased the section height from 380 to 480 to give each row enough room for a 150dp square image plus its text block. |
| [product_detail_screen.dart](../../proximity_app/lib/features/product_detail/presentation/screens/product_detail_screen.dart), [previously_bought_tile.dart](../../proximity_app/lib/features/order_again/presentation/widgets/previously_bought_tile.dart) | Not a bug, a feedback-driven tweak: "Added to cart" used Flutter's default 4s `SnackBar` duration. | Shortened to 3s on both call sites -- the cart tab's own badge count already confirms the add, so the toast doesn't need to linger as long. |

## Not yet done / carried forward

- Real on-device verification of all three flows (sign-up, sign-in, forgot-password) — pending your test pass once the rebuild finishes.
- The two standing items from before this sprint are unaffected by this work and still open: whether `custom_access_token_hook` is enabled (Dashboard → Authentication → Hooks), and turning **off** "Verify JWT with legacy secret" on the deployed Edge Function.
- `SPRINT_PLANNING.md` itself was updated to insert this sprint and renumber the old "iOS build & store submission" entry from Sprint 14 to **Sprint 15** (§3.1, §3.2, §11, §12, §13 cross-references all updated). Older sprint files (`Sprint 0.md`, `Sprint 11.md`, `Sprint 13.md`) still say "Sprint 14" meaning the iOS sprint — left as-is deliberately, same as every other sprint file in this folder: they're point-in-time records of what was true when written, not living docs kept in sync retroactively.
