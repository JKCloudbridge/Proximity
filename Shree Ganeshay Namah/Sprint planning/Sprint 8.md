# Sprint 8 — Payments

**Status: development complete, `deno check`/`flutter analyze`-verified, not yet run against a live Supabase project, a physical device, or a real Razorpay account.**
Same honest line every prior sprint has drawn, plus a new one this sprint is the first to actually carry: **no real Razorpay (or PayU) credentials exist for this project.** Everything gated on live third-party keys is therefore code-complete and reasoned-through, not exercised even once against a real gateway — see "What's blocked on real credentials" below for the precise line between what that does and doesn't block. This sprint adds five new migrations (`033`–`037`) on top of the still-unconfirmed `000`–`032` (Sprint 7.md's own list — nothing in this session's history shows that changing). No Android device or emulator is attached to this session either (unchanged since Sprint 4); Sprint 0's `cmdline-tools`/licensing gap is still open too.

Written for a future LLM session (or you) to pick this project back up — if you're that session, start here, then `SPRINT_PLANNING.md` §11's Sprint 8 entry and §1.4/§4.9/§5.4, then `Sprint 7.md` for the checkout core this sprint's payment confirmation actually completes (`rpc_place_order`'s own header lists exactly what it deliberately left undone: stock decrement, ledger rows, rider assignment — this sprint closes the ledger half of that list).

This sprint touches `migrations/`, `proximity_backend/` (new lib + two new route files) and `proximity_app/` (mobile payment-flow wiring) — `proximity_web` is explicitly out of scope, unchanged since Sprint 3.

## Goal (from SPRINT_PLANNING.md §11)

> A PaymentGateway abstraction in both the Edge Function and Flutter — createOrder()/verifyPayment()/handleWebhook() (backend) and a thin wrapper (mobile) — implement the Razorpay adapter for real (test-mode keys), keep a PayU adapter as a stub. rpc_confirm_payment — a webhook-triggered, service-role-only RPC: verifies the gateway signature, sets order_groups.payment_status='paid', cascades every child orders.status from 'pending' to 'confirmed', and inserts the correct shop_ledger_entries row per shop sub-order. The pay_at_shop path also needs completing. Invoice generation (rpc_generate_invoice) on order confirmation. Exit criteria: a real (test-mode) payment completes and correctly produces confirmed orders, ledger entries, and an invoice PDF.

## Two things this sprint's own brief asked to be checked directly, not assumed — both checked, both confirmed

1. **§1.4's claim that Baker Ally has "a working, provable integration (`checkout_repository.dart`'s exception-mapping pattern) to lift almost verbatim" for Razorpay is false**, confirmed by re-checking Baker Ally's actual working tree directly (not just grepping filenames):
   - No `checkout_repository.dart` exists anywhere in `C:\Users\hemin\Desktop\Android Project`.
   - `razorpay_flutter: ^1.3.7` is pinned in `baker_ally_flutter/pubspec.yaml` and `razorpay: npm:razorpay@^2.9.0` in `baker_ally_backend/deno.json`, but **no Dart file imports `razorpay_flutter`** and **no backend route/repository file references the `razorpay` npm import at all** — both are unused dependency pins, not integrations.
   - `migrations/018_create_orders.sql` and `020_create_webhook_events.sql` there do carry real columns/comments (`razorpay_order_id`, `razorpay_payment_id`, a webhook-events table) — schema-level scaffolding exists, but no route or repository code was ever written against it.
   - `Planning docs/Architecture/RAZORPAY_INTEGRATION.md` (and its `_QUICK_REFERENCE`/`_SETUP_CHECKLIST`/`_COMPLIANCE_AUDIT` siblings) describe a design in prose only.

   Net effect: this sprint's Razorpay adapter (`proximity_backend/supabase/functions/api/lib/payments/razorpay.ts`, `proximity_app/lib/features/payments/data/razorpay_payment_gateway.dart`) is designed fresh against Razorpay's own current published API/SDK docs, verified live this session (sources listed below), not lifted from anything in this codebase's history — exactly as the standing rule for third-party packages requires.

2. **No `invoices` table exists anywhere in this project's recoverable history, including Baker Ally's.** Checked directly (`grep -ri invoice` over Baker Ally's `migrations/` turns up nothing) before assuming the "fresh design against prose, but recoverable" pattern Sprint 6/7 each found for `carts`/`product_cross_sell`/`discounts` — this one really is a third, genuinely fresh design, not a third recovery. `migrations/034_create_invoices.sql`'s own header says so plainly.

## What was actually checked live before writing code against it (this sprint's third-party-package standing rule)

| Package/API | Checked against | Result |
|---|---|---|
| `razorpay_flutter` (pub.dev) | Live package page | 1.4.6, current, verified publisher, `Razorpay`/`open()`/`on()`/`clear()` API confirmed |
| `razorpay` npm SDK | — | **Not used.** This project's entire Razorpay need (create one order, verify two kinds of HMAC signature) is two REST calls + one crypto primitive, directly expressible with Deno's built-in `fetch`/Web Crypto — see `lib/payments/razorpay.ts`'s header for why pulling in the full SDK wasn't worth the extra audit surface |
| Razorpay Orders API (`POST /v1/orders`) | razorpay.com/docs/api/orders/create | amount (paise)/currency required, `receipt` ≤40 chars, response has `id`/`amount`/`currency`/`status` |
| Payment-signature verification (Checkout success) | razorpay.com/docs/webhooks/validate-test, razorpay-node's own `paymentVerfication.md`, multiple current docs pages | `HMAC-SHA256(order_id + "|" + payment_id, key_secret)`, compared to `razorpay_signature` |
| Webhook signature verification | razorpay.com/docs/webhooks/validate-test | `HMAC-SHA256(raw_body, webhook_secret)` (a **separate** secret from `key_secret`), compared to `X-Razorpay-Signature` |
| Webhook payload shape | razorpay.com/docs/webhooks/payloads/payments/ and .../orders/ | **A real, caught mistake, not a footnote** — see "Bugs caught" #1 below |
| `pdf-lib` (npm) | Live npm listing | 1.17.1, last published some years ago, no known critical issues, no native deps — flagged plainly as not actively maintained rather than implied otherwise |
| `url_launcher` (pub.dev) | Live package page | 6.3.2, current |

PayU: **not checked live, deliberately.** §13's open-decisions log wanted "current Flutter-SDK-maturity confirmation" before Sprint 8 started; that confirmation never happened (no PayU sandbox account exists), so `lib/payments/payu.ts` and `payu_payment_gateway.dart` are genuinely empty stubs, not a guess at what a real integration would look like.

## What was built

### Migrations (`migrations/`)

| File | Purpose |
|---|---|
| [migrations/033_add_shops_invoice_seq.sql](../../migrations/033_add_shops_invoice_seq.sql) | One column added to `shops` — `next_invoice_seq`, the atomic per-shop invoice counter `rpc_generate_invoice` increments. See its header for why this is a plain column, not a SQL `SEQUENCE` (would need one per shop). |
| [migrations/034_create_invoices.sql](../../migrations/034_create_invoices.sql) | `invoices` — fresh design against §4.10's prose, no recoverable original anywhere (see above). Snapshots `shop_name`/`shop_gstin` at generation time, same immutable-record principle `order_items` already applies. |
| [migrations/035_create_invoices_bucket.sql](../../migrations/035_create_invoices_bucket.sql) | The `invoices` Storage bucket (private) — **deliberately no client-facing Storage RLS policy at all**, unlike `rider-documents`/`product-images`. See its header: invoices have two ownership classes (buyer + shop team) that a single-segment path-based policy can't cleanly express, so every read goes through the authenticated `GET /v1/orders/:orderId/invoice` route instead, which mints a short-lived signed URL after checking ownership itself. |
| [migrations/036_rpc_confirm_payment.sql](../../migrations/036_rpc_confirm_payment.sql) | `rpc_confirm_payment` — the sprint's centerpiece. Answers both of Sprint 7's own flagged open questions (see "Design decisions" below) in its own header, in full, rather than picking silently. Idempotent (`SELECT ... FOR UPDATE` + a `payment_status` guard) — safe to call from both the client-verify path and the webhook, in either order. |
| [migrations/037_rpc_generate_invoice.sql](../../migrations/037_rpc_generate_invoice.sql) | `rpc_generate_invoice` — creates the DB row + a deterministic `pdf_path`; the actual PDF bytes are rendered/uploaded by TypeScript (`lib/invoice.ts`) immediately after, since Postgres can't render one. Idempotent (returns the existing row on a repeat call for the same `order_id`, never mints a second invoice number). |

**Not yet run** against the live Supabase project — same "apply in order via the Supabase SQL editor" workflow as every prior migration. See "What you need to run" below.

### Backend (`proximity_backend/`)

| File | Purpose |
|---|---|
| [proximity_backend/deno.json](../../proximity_backend/deno.json) | Added `pdf-lib@^1.17.1` to the import map, keyed as the literal `"npm:pdf-lib"` specifier every file imports by — Sprint 6's own dependency-pinning bug (bare keys never matching `npm:`-prefixed imports) is still fixed and this sprint's own addition follows the corrected convention, not the old broken one. |
| [proximity_backend/.env.example](../../proximity_backend/.env.example) | Added `RAZORPAY_KEY_ID`/`KEY_SECRET`/`WEBHOOK_SECRET` (all unset — no real account exists) and `PAYMENT_GATEWAY_DEFAULT=razorpay`, each with a comment on the real, easy-to-make mistakes they guard against (KEY_SECRET vs WEBHOOK_SECRET being different values; the webhook's subscribed event needing to be `order.paid`, not `payment.captured`). |
| [proximity_backend/supabase/functions/api/db/schema.ts](../../proximity_backend/supabase/functions/api/db/schema.ts) | Added `shops.nextInvoiceSeq` and the `invoices` table. |
| [proximity_backend/supabase/functions/api/lib/payments/types.ts](../../proximity_backend/supabase/functions/api/lib/payments/types.ts) | The `PaymentGateway` interface (§1.4, verbatim shape: `createOrder`/`verifyPaymentSignature`/`verifyAndParseWebhook`) + shared types. |
| [proximity_backend/supabase/functions/api/lib/payments/crypto.ts](../../proximity_backend/supabase/functions/api/lib/payments/crypto.ts) | Shared `hmacSha256Hex`/`timingSafeEqual` (Web Crypto, no npm dependency) — used by every signature check in `razorpay.ts`. |
| [proximity_backend/supabase/functions/api/lib/payments/razorpay.ts](../../proximity_backend/supabase/functions/api/lib/payments/razorpay.ts) | The real adapter — `fetch`-based order creation, both HMAC verifications, webhook parsing. See "Bugs caught" #1 for a real mistake caught and fixed in this file before calling it done. |
| [proximity_backend/supabase/functions/api/lib/payments/payu.ts](../../proximity_backend/supabase/functions/api/lib/payments/payu.ts) | The stub — every method throws `GatewayNotImplementedError`, mapped by `routes/payments.ts` to a `501`, not a `500`. |
| [proximity_backend/supabase/functions/api/lib/payments/index.ts](../../proximity_backend/supabase/functions/api/lib/payments/index.ts) | `getPaymentGateway()` — the registry §1.4 asked for: swapping gateways is `PAYMENT_GATEWAY_DEFAULT`, not a rewrite. |
| [proximity_backend/supabase/functions/api/lib/invoice.ts](../../proximity_backend/supabase/functions/api/lib/invoice.ts) | PDF rendering (`pdf-lib`) + Storage upload/exists/signed-URL helpers. Renders amounts as "Rs. 123.45," never "₹123.45" — a real `pdf-lib` constraint (Helvetica's WinAnsi encoding has no Rupee-sign glyph; `drawText` throws on an unencodable character), checked against the library's own behavior, not discovered by trial and error against a runtime this session doesn't have. |
| [proximity_backend/supabase/functions/api/lib/orderConfirmation.ts](../../proximity_backend/supabase/functions/api/lib/orderConfirmation.ts) | New shared module: `loadOrderGroup` (moved out of `checkout.ts`) + `confirmPaymentAndGenerateInvoices` (calls `rpc_confirm_payment` then generates an invoice per order, best-effort per order). Exists specifically to give `routes/payments.ts` a second caller for `loadOrderGroup` without a circular import between `checkout.ts` and `payments.ts` — see "Bugs caught" #2. |
| [proximity_backend/supabase/functions/api/routes/checkout.ts](../../proximity_backend/supabase/functions/api/routes/checkout.ts) | `loadOrderGroup` moved out (now imported from `orderConfirmation.ts`). `POST /orders` now calls `confirmPaymentAndGenerateInvoices` immediately after a successful `pay_at_shop` placement — see "Design decisions" #2 for exactly why that's the chosen trigger point. |
| [proximity_backend/supabase/functions/api/routes/payments.ts](../../proximity_backend/supabase/functions/api/routes/payments.ts) | New. `POST /order-groups/:id/payment-order` (create/reuse a gateway order), `POST /order-groups/:id/verify-payment` (the fast, client-triggered confirm path), `POST /webhooks/razorpay` (the authoritative path, no `authMiddleware` — the HMAC check IS its authentication). |
| [proximity_backend/supabase/functions/api/routes/invoices.ts](../../proximity_backend/supabase/functions/api/routes/invoices.ts) | New. `GET /orders/:orderId/invoice` — buyer or shop owner/staff only (§5.3), self-healing (regenerates the PDF if the row exists but the object doesn't, e.g. after a prior upload failure), never returns the raw storage path, only a fresh signed URL. |
| [proximity_backend/supabase/functions/api/lib/supabaseAdmin.ts](../../proximity_backend/supabase/functions/api/lib/supabaseAdmin.ts) | Header comment updated — this client now has a second real use (Storage against the `invoices` bucket), not just `auth.getUser`. |
| [proximity_backend/supabase/functions/api/index.ts](../../proximity_backend/supabase/functions/api/index.ts) | Wired `paymentsRoute`/`invoicesRoute`/`paymentsWebhookRoute` in — the webhook route is a deliberately separate export/mount specifically so it's obvious at the call site that it carries no auth middleware. |

**Verified:** `deno check supabase/functions/api/index.ts` passes clean (re-run after every substantive change, not just once at the end — including after the webhook-payload fix in "Bugs caught" #1). `deno lint` on every new file surfaces only the same pre-existing, codebase-wide `npm:`-import-version warning Sprint 3/6 already documented as not a regression (this project gates on `deno check`).
**Not verified:** never deployed, never received a real request, never run against a real database, and — new this sprint — **never called Razorpay's actual servers even once**, since no real key pair exists. `rpc_confirm_payment`/`rpc_generate_invoice` carry the same "never executed against real Postgres" caveat every RPC since `rpc_place_order` has (see "What's genuinely unverified").

### Mobile app (`proximity_app/`)

New feature folder `payments`.

| File | Purpose |
|---|---|
| [proximity_app/pubspec.yaml](../../proximity_app/pubspec.yaml) | Added `razorpay_flutter: ^1.4.6`, `url_launcher: ^6.3.2` — both verified live against pub.dev before adding (table above), both actually resolved via `flutter pub get` (checked the resolved versions landed in `pubspec.lock`, not just trusted the command's exit code — this machine's own standing "verify, don't trust the exit code" lesson, carried over from the npm side of this project to the pub side too). |
| [proximity_app/.env.example](../../proximity_app/.env.example) | Explicitly does **not** add a Razorpay key field — the key id is read from `POST /order-groups/:id/payment-order`'s own response instead (the backend already holds it), so there's no second copy of it to let drift. Documents why, and that `RAZORPAY_KEY_SECRET` never belongs in this app in any form. |
| [proximity_app/lib/features/payments/data/payment_gateway.dart](../../proximity_app/lib/features/payments/data/payment_gateway.dart) | The Flutter half of §1.4's abstraction — one `pay()` method, a result type that treats cancellation/failure as a normal outcome, not an exception. |
| [proximity_app/lib/features/payments/data/razorpay_payment_gateway.dart](../../proximity_app/lib/features/payments/data/razorpay_payment_gateway.dart) | The real adapter — turns `razorpay_flutter`'s event-callback API (`on(EVENT_PAYMENT_SUCCESS/...)`) into the one `Future` `pay()` promises, via a `Completer` guarded against completing twice. |
| [proximity_app/lib/features/payments/data/payu_payment_gateway.dart](../../proximity_app/lib/features/payments/data/payu_payment_gateway.dart) | The stub — `throw UnimplementedError(...)`, matching the backend's own stub. |
| [proximity_app/lib/features/payments/data/models/payment_order.dart](../../proximity_app/lib/features/payments/data/models/payment_order.dart), [models/invoice_link.dart](../../proximity_app/lib/features/payments/data/models/invoice_link.dart) | Mirror the two new backend response shapes. |
| [proximity_app/lib/features/payments/data/payment_repository.dart](../../proximity_app/lib/features/payments/data/payment_repository.dart) | `createPaymentOrder`, `verifyPayment`, `getInvoice` (null on 404, same convention every other repository in this project uses). |
| [proximity_app/lib/features/payments/presentation/providers/payment_providers.dart](../../proximity_app/lib/features/payments/presentation/providers/payment_providers.dart) | `paymentGatewayFor(gatewayId)` — §1.4's "a config flag, not a rewrite" on the Flutter side: the checkout/confirmation screens never import `RazorpayPaymentGateway`/`PayUPaymentGateway` directly. |
| [proximity_app/lib/features/payments/presentation/attempt_online_payment.dart](../../proximity_app/lib/features/payments/presentation/attempt_online_payment.dart) | One shared create-order/pay/verify sequence, used by both call sites below — never throws; a failure just leaves `payment_status` wherever the backend actually put it. |
| [proximity_app/lib/features/checkout/presentation/screens/checkout_screen.dart](../../proximity_app/lib/features/checkout/presentation/screens/checkout_screen.dart) | `_placeOrder` now attempts online payment immediately after a successful `online`-mode placement, before navigating to the confirmation screen — but doesn't block navigation on the outcome (see "Design decisions" #3). |
| [proximity_app/lib/features/checkout/presentation/screens/order_confirmation_screen.dart](../../proximity_app/lib/features/checkout/presentation/screens/order_confirmation_screen.dart) | Sprint 7's placeholder "Paid"/"Pay at shop" label replaced with a real `_paymentStatusLabel` reading the group's actual `paymentStatus`. New: a "Payment wasn't completed" banner + Retry button for a still-`pending` online group (reuses `attemptOnlinePayment`), and a per-shop-card "View invoice" action once that order is past `pending`/`cancelled` (opens the signed PDF URL via `url_launcher`). |

**Verified:** `flutter pub get` (checked `razorpay_flutter 1.4.6`/`url_launcher 6.3.2` actually landed in `pubspec.lock`, not just a success exit code). `flutter analyze` — 0 errors, 0 warnings; 20 info-level style lints, the same two pre-existing categories every prior sprint has accepted (`prefer_initializing_formals`, `use_null_aware_elements`) — 1 new instance in this sprint's own new file, not fixed, for the same consistency reasons every prior sprint gave.
**Not verified:** never run on an emulator or physical device (none attached this session, same gap every sprint since Sprint 4 has carried), never connected to a real backend/database, and the entire Razorpay Checkout flow (`RazorpayPaymentGateway.pay()`) has never actually opened a real Checkout sheet or received a real callback — there is no test-mode key to open one with.

## Design decisions this sprint had to make itself (flagged plainly, not picked silently)

### 1. Who absorbs an admin-authored discount code's cost?

`migrations/031`'s own header (Sprint 7) named this as the real open question Sprint 8 had to answer. **Decision: the platform absorbs it, always, on both payment paths** — every shop's ledger behaves as if the discount had never existed from that shop's own point of view. Reasoning and the exact math are in `migrations/036`'s header in full; short version:
- **Online** — `payout_due` is computed off `orders.subtotal` (pre-discount), never `orders.total`. The shop is paid what it would have earned with no discount; the platform's own margin absorbs the gap (which can go negative on a steep discount against a low-commission shop — a real, disclosed possibility, not a bug).
- **Pay-at-shop** — `commission_due` is computed off `subtotal` too, for consistency. But the shop only physically collected the post-discount `total` in cash/UPI directly from the buyer — so if `discount_value > 0` on that order, a **second** ledger entry (`payout_due`, for exactly `discount_value`) is inserted: the platform separately owing the shop back the promo's cost, reusing the ledger's existing two entry types rather than inventing a third.

This is a real design call, not the only defensible one — a project that later wants shop-funded discounts would need a different rule (and probably a `discounts.scope_shop_id` column, which `migrations/026`'s header already flagged as deliberately not built).

### 2. When does `order_groups.payment_status` become `'collected_at_shop'`?

This sprint's own brief named this as genuinely undecided ("at order placement? at a shop marking it picked up/delivered? there's no explicit trigger point named yet"). **Decision: at order placement, synchronously** — `routes/checkout.ts`'s `POST /orders` calls `confirmPaymentAndGenerateInvoices` itself, immediately after `rpc_place_order` succeeds, for every `pay_at_shop` group. Two real reasons, both in `migrations/036`'s header:
- There is, by construction, no gateway event to wait for in this mode at all — §1.4's whole premise is "Proximity collects zero money" here.
- The alternative (gating on a shop explicitly marking the order picked-up/delivered) depends on a shop-side order-status-advance surface — **checked directly, not assumed: `rpc_shop_advance_order_status` does not exist anywhere in this codebase through Sprint 7, and is not scheduled by name in any sprint's own §11 entry either.** Building Sprint 8's commission bookkeeping around a mechanism with no scheduled owner would leave `commission_due` permanently unrecorded for every pay_at_shop order until some future sprint happens to build that surface — worse for the platform's own revenue visibility than recording the obligation on trust at placement, which is already the trust model §1.4 explicitly accepted for this entire payment mode.

**Honest, disclosed consequence:** a pay_at_shop order that's later cancelled still leaves its ledger entries in place — nothing in this sprint (or any prior one) writes to `shop_ledger_entries` on cancellation, because no cancellation flow exists at all yet.

### 3. Client-verify path vs. webhook — both, deliberately, not one or the other

`rpc_confirm_payment` is called from two places: `POST /order-groups/:id/verify-payment` (the buyer's own app, right after Razorpay Checkout's success callback) and `POST /webhooks/razorpay` (Razorpay's own server). The RPC's own `SELECT ... FOR UPDATE` + `payment_status` guard (migrations/036) makes calling both, in either order, a safe no-op the second time. This is standard practice for exactly the reason `checkout_screen.dart`'s own comment gives: the client path is fast (no buyer-visible wait on a webhook round trip) but not guaranteed to run at all if the app crashes/loses network/gets force-closed the instant Checkout succeeds; the webhook is slower but authoritative. Neither alone was judged good enough on its own.

### 4. Invoice storage — no direct client Storage access, unlike every prior bucket

`invoices` (the bucket, `migrations/035`) has **no** client-facing Storage RLS policy at all — every prior bucket (`rider-documents`, `product-images`) let its owning party read/write directly through Supabase's Storage API with their own JWT. Invoices have two independent ownership classes (buyer + shop team) that a single-path-segment policy can't cleanly express without a second, subtly different access-control shape just for this one bucket — so every read instead goes through `GET /v1/orders/:orderId/invoice`, which already has to answer exactly this ownership question for the DB row, then hands back a short-lived signed URL. Full reasoning in that migration's header.

## Bugs caught and fixed during implementation

1. **A real webhook-payload mistake, caught before this was called done, not left as a live bug.** The first draft of `lib/payments/razorpay.ts`'s webhook parser subscribed to (and parsed) `payment.captured`, reading `order_group_id` out of `payload.payment.entity.notes`. Checked live against Razorpay's own documented sample payloads (razorpay.com/docs/webhooks/payloads/payments/ and .../orders/) before calling this done, and that check reversed the design: **`payment.captured`'s own documented payload contains ONLY the payment entity — no order entity at all — and a payment's `notes` are a field independent of the order's `notes`** (creating a Razorpay order with `notes: {order_group_id: ...}` does not copy that onto the payment made against it). This project's own `order_group_id` note, set at order-creation time, would have been unrecoverable from every real `payment.captured` webhook this project ever received — silently breaking the *authoritative* confirmation path (the client-verify path would have kept working, masking the gap until the day a buyer's app crashed mid-Checkout and nothing was there to confirm the payment). Fixed: the webhook now subscribes to and parses **`order.paid`** instead, which Razorpay's own docs confirm carries both `payload.order.entity` (with the notes) and `payload.payment.entity` (the payment id) in one payload. `.env.example` and this file both now say explicitly which event to subscribe to in the Razorpay Dashboard. `deno check` re-verified clean after the fix.
2. **A circular-import risk, headed off before it was ever written, not discovered by a failing build.** `routes/payments.ts` needs `routes/checkout.ts`'s `loadOrderGroup`; `routes/checkout.ts`'s own `POST /orders` handler needs this sprint's new `confirmPaymentAndGenerateInvoices` for the `pay_at_shop` path — two route files each needing something from the other. Resolved by pulling both functions into a new shared `lib/orderConfirmation.ts` (one implementation, three callers: `checkout.ts`, `payments.ts`'s verify-payment route, and its webhook route) rather than letting either route file import the other directly — same "pull the shared thing out once a second caller exists" judgment call `shopAccess.ts`'s `isShopWriter` made in Sprint 3.
3. **A stray `--` (SQL-comment syntax) instead of `//` slipped into several TypeScript file headers during drafting** — a real, repeated slip this session (not hypothetical), caught by proof-reading each file rather than by `deno check` (a `--` mid-comment-block doesn't actually break TypeScript parsing the way Sprint 3's stray `#` did in a `.ts` file, since `--` isn't special syntax there — it would have just read as a decrement-adjacent typo forever if left, or in the worst case have been misread by a future editor copy-pasting from it into real code). Fixed in `razorpay.ts`, `payu.ts`, `invoice.ts`, and `checkout.ts` before this was called done, by grepping the whole backend for lines starting with `--` after the fact rather than trusting the drafting pass caught every instance.

## What's genuinely unverified (worth being specific about, same treatment Sprint 7 gave `rpc_place_order`)

`rpc_confirm_payment` and `rpc_generate_invoice` have never executed against a real Postgres instance, same as every RPC in this project since Sprint 1 — but this sprint adds a genuinely new *kind* of unverified surface on top of that:

- **No real Razorpay account, in any form, exists for this project.** Order creation, both HMAC signature checks, and the webhook payload shape were all checked against Razorpay's own current documentation (table above) — not assumed from training-data memory — but **zero bytes of this code have ever talked to Razorpay's actual servers.** The `RAZORPAY_KEY_ID`/`KEY_SECRET`/`WEBHOOK_SECRET` env vars are unset in every `.env.example`; `getPaymentGateway()` throws `PaymentGatewayNotConfiguredError` (mapped to a `503`) the moment anything tries to use them as they stand today.
- **The `order.paid` vs `payment.captured` webhook-event fix (Bugs caught #1) is reasoned from documentation, not confirmed by receiving one real webhook delivery.** This is exactly the kind of gap a single real test-mode transaction would close for good.
- **`razorpay_flutter`'s Checkout sheet has never actually opened.** No device/emulator, and no key to open it with even if one were attached.
- **`pdf-lib`'s PDF has never been opened in a real PDF viewer.** The rendering logic was traced by hand against `pdf-lib`'s documented API (`PDFDocument.create`/`addPage`/`embedFont`/`drawText`/`drawLine`/`save`) and its known WinAnsi-encoding limitation (hence "Rs." not "₹"), but never actually run — Deno's own `npm:pdf-lib` resolution, the exact byte output, and whether a real PDF reader opens it cleanly are all unconfirmed.
- **The `largest-remainder`-adjacent arithmetic in `rpc_confirm_payment`'s ledger math (`ROUND(subtotal * commission_pct / 100.0)`) has been traced by hand against Postgres's documented `numeric`/`integer` rounding semantics, not against a running query.**
- **The two-call idempotency guard (`SELECT ... FOR UPDATE` + a `payment_status` check) has never been raced against itself for real** — reasoned through against Postgres's documented row-locking semantics, not observed under real concurrent webhook + client-verify traffic.

None of this changes the sprint's status honestly — every prior sprint has carried some version of "unverified against live infra." This sprint's honest difference is that **the exit criteria's own "a real (test-mode) payment completes" clause cannot be attempted at all** without a real Razorpay test account, not just a database connection.

## Exit criteria check

| Criterion | Status |
|---|---|
| A real (test-mode) payment completes | **Cannot be attempted.** No Razorpay test-mode credentials exist for this project. The abstraction, the RPC, the webhook route, and the mobile wiring are all code-complete and reasoned through against Razorpay's real, current docs — but "completes" requires an actual gateway to complete against. |
| ...and correctly produces confirmed orders | `rpc_confirm_payment` cascades `orders.status` pending→confirmed for both payment paths, traced by hand against every relevant CHECK constraint. **Cannot execute** until migrations `000`–`037` are live and a real payment (or a real pay_at_shop placement) exists to confirm. |
| ...ledger entries | `payout_due`/`commission_due` insertion, including the discount-absorption rule (Design decision #1), is code-complete and traced by hand. Same execution blocker. |
| ...and an invoice PDF | `rpc_generate_invoice` + `lib/invoice.ts`'s render/upload are code-complete; the self-healing `GET /orders/:orderId/invoice` route is built and gated correctly (§5.3). **Never produced or opened a real PDF file even once** — see "What's genuinely unverified." |

**Bottom line: Sprint 8 is development-complete and internally verified at every layer this project has tooling for** (`deno check`, `flutter analyze`) — but is honestly the first sprint where "not yet verified" means something categorically bigger than "no live database": the exit criteria's central clause is blocked on a real account this project doesn't have, not just on infrastructure this project has consistently deferred setting up.

## What's blocked on real credentials vs. what isn't

Scoped explicitly, per this sprint's own instructions:

**Built and reviewable without real keys (done this sprint):**
- The `PaymentGateway` abstraction, both languages.
- The webhook signature-verification shape (and the real `order.paid`-vs-`payment.captured` payload distinction, Bugs caught #1).
- `rpc_confirm_payment`, `rpc_generate_invoice`, and every route around them.
- The discount-absorption and pay_at_shop-timing decisions (both genuinely had to be made regardless of credentials).
- The mobile Checkout-wrapper wiring, including cancellation/failure/retry handling.

**Blocked on real Razorpay test-mode keys, cannot be verified without them:**
- That `createOrder` actually reaches Razorpay's servers and gets a real order back.
- That the payment-signature and webhook-signature HMAC math actually matches what Razorpay computes (reasoned correct against docs; unconfirmed against a real signature).
- That `order.paid` actually fires, with the shape this sprint's fix assumes, for a real captured payment.
- The entire on-device Checkout sheet experience.

**Blocked on a PayU sandbox account, and out of scope regardless per §13:** everything about a real PayU integration — the stub stays a stub.

## Not yet built (by design, deferred to the sprint that actually needs it)

- **A real PayU adapter.** Unchanged scope call from §1.4/§13 — needs live commercial terms and Flutter-SDK-maturity confirmation neither of which happened before this sprint started, so it didn't happen during it either.
- **Refunds/disputes.** Not named in §5.4's Sprint 8 scope; `lib/payments/razorpay.ts`'s webhook payload type is deliberately narrow (only what `order.paid`/`payment.failed` need), not the full event catalog.
- **Settlement automation** (actually moving money to a shop's bank account). Unchanged Phase-2 reasoning from v1/§4.9 — `shop_ledger_entries` still only records the obligation.
- **A shop-side order-status-advance surface** (`rpc_shop_advance_order_status`, §5.4). Flagged above (Design decision #2) as a real, still-unscheduled gap this sprint worked around rather than closed — worth a real slot in a future sprint's plan, not silently left to be rediscovered.
- **Cancellation/refund reversal of ledger entries.** A pay_at_shop or online order cancelled after confirmation leaves its ledger rows in place. No cancellation flow exists anywhere in this project yet to even trigger the question.
- **Multi-page invoices.** `lib/invoice.ts` renders one A4 page with no overflow handling — fine for any realistic kirana-shop cart size, a real gap for an order with enough line items to run past one page.
- **CGST/SGST/IGST tax breakup, HSN codes on the invoice.** `products`/`product_variants` carry no tax-rate or HSN column anywhere in this project's schema — nothing to compute a breakup from. Flagged in both `migrations/034` and `lib/invoice.ts`'s own headers, not implied to be a complete GST document.
- **Razorpay Route** (marketplace split payouts) — §1.4 named it as relevant "once automated shop payouts happen"; that's still Phase 2.
- **Buyer profile prefill on the Razorpay Checkout sheet** (name/email/phone). `PaymentGatewayRequest` supports it, but no reusable buyer-profile provider exists elsewhere in this app to source it from yet (only `AuthSessionState`'s bare `role`/`userId`) — building one was judged out of scope for "payment-flow wiring" specifically. Razorpay Checkout works fine with the buyer typing their own contact details in the sheet; this is a polish item, not a blocker.

## What you need to run

Same list Sprint 3–7.md carried, plus five new files:

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
033_add_shops_invoice_seq.sql           -- Sprint 8, new
034_create_invoices.sql                 -- Sprint 8, new
035_create_invoices_bucket.sql          -- Sprint 8, new
036_rpc_confirm_payment.sql             -- Sprint 8, new
037_rpc_generate_invoice.sql            -- Sprint 8, new
```

If `000`–`032` are already confirmed applied, only **`033`–`037`** are new and need running, strictly in that order (`033` before `037`, since `rpc_generate_invoice` reads `shops.next_invoice_seq`; `034` before `035`/`036`/`037`, since all three reference `invoices` or its bucket).

**Given this sprint's exit criteria cannot be attempted at all without real Razorpay test-mode keys, getting a Razorpay test account (free, no live commercial terms needed for test mode) would unblock more of this sprint's own verification than a live Supabase project would on its own** — though both together are what the exit criteria actually needs: migrations `000`–`037` applied, a real approved shop with a real GSTIN, at least one online-paid order and one pay_at_shop order, and a Razorpay webhook pointed at a deployed Edge Function subscribed to `order.paid`.

## What Sprint 9 needs from you before it can be verified either

Same shape as every prior sprint, unchanged: Sprint 9 (rider network live — `rpc_assign_rider`, the rider app touchpoint, buyer-side Realtime tracking) can be written without live infrastructure, but proving any of it — this sprint's payment confirmation included — needs the migrations actually applied, real approved shops/riders, a physical device or working emulator, and now also a real Razorpay test account if Sprint 9's own work ever touches an order that's supposed to already be paid.

One more thing worth deciding before Sprint 9, not this sprint's call to make silently: **`rpc_shop_advance_order_status` (§5.4) still has no scheduled sprint** (Design decision #2 above). If Sprint 9's rider-status-ladder work is meant to be the shop-side equivalent too, say so explicitly; if not, this gap should get a real line in a future sprint's `§11` entry rather than staying an implicit assumption.

---

**Waiting for your go-ahead before starting Sprint 9**, per your instruction to stop at sprint boundaries.
