# Sprint 7 — Checkout Core (No Payment Gateway Yet)

**Status: development complete, `deno check`/`flutter analyze`-verified, not yet run against a live Supabase project or a physical device.**
Same honest line every prior sprint has drawn. This sprint adds seven new migrations (`026`-`032`) on top of the still-unconfirmed `000`-`025` (Sprint 6.md's "What you need to run" list -- nothing in this session's history shows that changing). No Android device or emulator is attached to this session either (`flutter devices` still shows only Windows-desktop/Chrome/Edge, and this project still has no `windows`/`web` platform folders -- `android`/`ios` only); Sprint 0's still-open `cmdline-tools`/licensing gap is still open too. This sprint additionally has the biggest single piece of untestable logic in the project so far (`rpc_place_order`) -- see "What's genuinely unverified" below for exactly what that means in practice.

Written for a future LLM session (or you) to pick this project back up -- if you're that session, start here, then `SPRINT_PLANNING.md` §11's Sprint 7 entry and §4.8/§5.4/§7.4, then `Sprint 6.md` for the cart this sprint's checkout screen actually consumes, and for the account of Sprint 6's own second-review-pass findings (a project-wide `deno.json` dependency-pinning bug, and two Flutter `Key` bugs) -- both fixed there, both still holding here (re-verified this sprint, see "Verified" below).

This sprint touches `migrations/`, `proximity_backend/` (new routes + one RPC), and `proximity_app/` (mobile) -- `proximity_web` is explicitly out of scope, unchanged since Sprint 3.

## Goal (from SPRINT_PLANNING.md §11)

> Migrations: order_groups, orders (new shape, §4.8), order_items, order_status_history, shop_ledger_entries. rpc_place_order (§5.4) -- per-shop fulfillment selection, unified slot generation endpoint (§4.6), delivery-fee CHECK constraint enforcement, discounts engine wired (banner still hidden per your original instruction, table live). Checkout UX (§7.4) steps 1-4, ending in a stubbed "payment" step (mocked success) so the rest of the flow can be tested before gateway integration lands. Exit criteria: a full multi-shop checkout produces one order_groups row and correct per-shop orders rows with the right fulfillment/slot/fee data, verified by hand against the CHECK constraints.

## A third table needed a fresh design against prose -- `discounts`

§11's own line for this sprint says "discounts engine wired ... table live," and §5.2 lists `discounts` in the admin-only RLS ownership class -- but, same as `carts`/`product_cross_sell` in Sprint 6 and `products`/`wishlists` before that, **no literal DDL for `discounts` appears anywhere in §4.** Checked the read-only Baker Ally reference project on the same instinct Sprint 6 used for carts/cross-sell, and it paid off a third time: `migrations/016_create_discounts.sql` and `017_create_product_discounts.sql` there give the real v1 shape. Reused directly (migrations/026), with two documented departures -- see that file's own header: a `created_by` column added, and `product_discounts`/the later quantity-discount columns from Baker Ally's own Milestone 6.5 migration deliberately **not** carried over, because those exist to drive the quantity-discount progress banner, and §11's own line for this sprint says that banner "stays hidden."

## The stubbed-payment / "no real gateway" boundary, drawn precisely

`order_groups.payment_status` starts at `'pending'` and nothing in this sprint ever moves it. There is no mocked-success step in the backend at all -- `POST /v1/orders` either succeeds (the order is placed, unpaid) or fails outright with a typed error. Placement and payment confirmation are already two separate steps in §4.8's own schema (`orders.status` starts at `'pending'` regardless of `payment_status`), so "ending in a stubbed payment step" is implemented as: the checkout screen calls `POST /v1/orders`, and a successful response *is* the mocked "payment succeeded" moment from the buyer's point of view -- there's no second, fake gateway call to simulate, because §4.8's model never needed placement to wait on payment in the first place. Sprint 8 is what makes `payment_status` mean anything.

## What was built

### Migrations (`migrations/`)

| File | Purpose |
|---|---|
| [migrations/026_create_discounts.sql](../../migrations/026_create_discounts.sql) | `discounts` -- fresh design against prose, DDL recovered from Baker Ally's original (see header above). Seeds one demo code, `PROX10`, same reason Baker Ally seeded `BAKE10` at this stage. |
| [migrations/027_create_order_groups.sql](../../migrations/027_create_order_groups.sql) | `order_groups` -- §4.8's literal DDL, plus one documented addition: `discount_id`, so a placed order remembers *which* code it used, not just how much it took off. |
| [migrations/028_create_orders.sql](../../migrations/028_create_orders.sql) | `orders` -- §4.8's literal DDL, verbatim, both CHECK constraints included exactly as written there. |
| [migrations/029_create_order_items.sql](../../migrations/029_create_order_items.sql) | `order_items` -- §4.8's literal DDL, verbatim. §9's immutable order-item snapshot (name/unit/price copied at order time). |
| [migrations/030_create_order_status_history.sql](../../migrations/030_create_order_status_history.sql) | `order_status_history` -- §4.8's literal DDL, verbatim. Append-only; no UPDATE/DELETE policy for anyone. |
| [migrations/031_create_shop_ledger_entries.sql](../../migrations/031_create_shop_ledger_entries.sql) | `shop_ledger_entries` -- §4.9's literal DDL, verbatim. **Table only** -- nothing writes a row this sprint; Sprint 8's `rpc_confirm_payment` is the first writer (§11). Records one real open question Sprint 8 has to answer: who absorbs a discount code's cost, the platform or the shop? |
| [migrations/032_rpc_place_order.sql](../../migrations/032_rpc_place_order.sql) | `rpc_place_order` -- the sprint's centerpiece. See "What rpc_place_order actually does" below. |

**Not yet run** against the live Supabase project -- same "apply in order via the Supabase SQL editor" workflow as every prior migration. See "What you need to run" below.

### Backend (`proximity_backend/`)

| File | Purpose |
|---|---|
| [proximity_backend/supabase/functions/api/db/schema.ts](../../proximity_backend/supabase/functions/api/db/schema.ts) | Added `discounts`, `orderGroups`, `orders`, `orderItems`, `orderStatusHistory`, `shopLedgerEntries`, and `shopBlackoutDates` (existed since Sprint 2's migrations/013, deliberately kept out of this file until a route touched it -- this sprint's slot generator is that route). |
| [proximity_backend/supabase/functions/api/lib/slots.ts](../../proximity_backend/supabase/functions/api/lib/slots.ts) | Added `generateSlots` -- the real `GET /v1/shops/:id/fulfillment-slots` (§4.6) Sprints 4/5/6 each deferred here by name, plus `istDateString`/`istWeekdayForDate` helpers. Sprint 4's narrower `computeNextSlot` (the Home badge's own stand-in) is untouched and still used only there. |
| [proximity_backend/supabase/functions/api/routes/checkout.ts](../../proximity_backend/supabase/functions/api/routes/checkout.ts) | New. `GET /checkout/config` (the admin-controlled rider fee + slot granularity), `GET /discounts/:code?subtotal=N` (preview only -- see below), `GET /shops/:shopId/fulfillment-slots` (public), `POST /orders` (places the order via `rpc_place_order`, maps its 19 typed error codes to HTTP responses), `GET /order-groups/:id` (the confirmation-screen read, §7.4 step 5's per-shop-card shape). |
| [proximity_backend/supabase/functions/api/routes/cart.ts](../../proximity_backend/supabase/functions/api/routes/cart.ts) | `GET /v1/cart`'s shop join widened to include `supportsPickup`/`supportsDelivery`/`deliveryMode`/`minOrderValue` -- the checkout screen needs these per shop-group and the cart response already joins shops once; costs nothing extra to carry them along rather than a second per-shop request. |
| [proximity_backend/supabase/functions/api/index.ts](../../proximity_backend/supabase/functions/api/index.ts) | Wired `checkoutRoute` in. |

**Verified:** `deno check supabase/functions/api/index.ts` passes clean.
**Not verified:** never deployed, never received a real request, never run against a real database -- same standing gap every prior sprint's backend work has carried. `rpc_place_order` specifically has never executed against real Postgres at all -- see "What's genuinely unverified" below, which is longer than usual for this sprint on purpose.

### What `rpc_place_order` actually does

Ten numbered steps, all inside one function call (one transaction, per §5.1's reasoning -- quoted in the migration's own header: "a checkout that half-succeeded ... is not a bug you can apologise your way out of"):

1. Validate the cart exists, isn't empty, and every line in it is still purchasable *right now* (active variant, in-stock, active product, approved shop) -- the cart screen already flags these, but a buyer can sit on checkout while a shop deactivates something underneath them.
2. The `p_fulfillment` JSONB array must describe every shop in the cart exactly once -- no missing group, no extra group, no duplicate.
3. §1.4: `pay_at_shop` is refused outright if any shop-group involves a platform rider.
4. Read the admin-controlled slot granularity and rider delivery fee from `platform_settings` (§1.3 -- the shop never sets the fee).
5. Validate every group in a first pass: the shop is approved and actually offers the chosen fulfillment type, the delivery fulfiller matches what that shop's `delivery_mode` actually allows (§1.3's three-way contract), a delivery group has an address the buyer owns, the slot is real (right duration, not in the past, not blacked out, fits inside that weekday's business hours -- compared as full local timestamps, not raw `::time` values, so a slot can't wrap past midnight and miscompare), and the shop's `min_order_value` is met (enforced for the first time -- the column has existed since Sprint 2 with nothing reading it).
6. Compute the discount, if a code was given -- same three rules (`percent`/`flat`/`free_shipping`) the preview route (`GET /discounts/:code`) checks first, re-validated here as the actual authority.
7. Insert one `order_groups` row -- the single amount charged.
8. Insert one `orders` row per shop (+ its `order_items`, snapshotted per §9's immutable-copy pattern, + its first `order_status_history` row), using the per-shop discount allocation step 6b computes (see "Bugs caught" below for why that's its own numbered step and not folded into this loop).
9. **Assert**, don't assume: the sum of every shop's `orders.total` must equal `order_groups.total`. If it doesn't, the whole transaction aborts (`ORDER_TOTAL_MISMATCH`) instead of shipping mismatched money.
10. Burn the discount's `uses_count`, delete the cart's lines (the `carts` row itself stays -- one per user, Sprint 6), return the new group id.

Deliberately **not** done here, each for a stated reason (also in the migration's own header): no `stock_qty` decrement (an unpaid order holds nothing; Sprint 8's `rpc_confirm_payment` is the honest place if stock should ever move), no `shop_ledger_entries` rows (nobody's owed anything until payment confirms, §11 puts that in Sprint 8), no rider assignment (`rpc_assign_rider` is Sprint 9).

### Bugs caught and fixed during implementation

1. **A real money-allocation bug, caught while writing this function, not after.** The first draft split a cart-wide discount across shops by rounding each shop's proportional share and having the *last* shop "absorb the remainder" (`discount_total - sum_of_others`). That scheme can drive the last shop's own `discount_value` **negative** once enough shops are in one cart for per-shop rounding to compound past the total (three shops whose exact proportional shares each round up by close to half a paisa can together overshoot the total by more than any one shop's real share). The buyer's own total was never wrong -- the bug was purely in how it got divided across shops -- but a negative discount on one shop's own order row is real, visible wrongness that Sprint 8's ledger math would have inherited downstream, and my own step-9 invariant check doesn't catch it either (redistributing money between shops doesn't change the grand total, so the assertion that group total = sum of shop totals stays true either way). Fixed with a **largest-remainder apportionment** (the same method real-world seat/tax apportionment uses for exactly this class of problem): floor every shop's exact share first (always ≥ 0), then hand the leftover paise -- always between 0 and shop-count-minus-one, since the un-floored shares already sum to the total exactly -- one each to the shops with the largest fractional remainder. Sums to exactly the right total by construction; no share can go negative. Computed once (migrations/032 step 6b, two parallel arrays keyed by shop id) rather than procedurally inside the insertion loop, which is also what let the loop itself get simpler, not more complex, once the fix landed.
2. **`RadioListTile`'s own `groupValue`/`onChanged` are deprecated in this project's actual installed Flutter version** (checked against the real SDK source, `widgets/radio_group.dart` and `material/radio_list_tile.dart`, not assumed from training data -- `flutter analyze` flagged six `deprecated_member_use` warnings the moment the checkout screen's two radio groups were written, a new lint category this codebase hadn't hit before Sprint 1-6's two accepted "existing style" categories). The replacement is a `RadioGroup<T>` ancestor managing selection for every `Radio`/`RadioListTile` in its subtree; fixed by wrapping the address-picker and payment-mode radios each in their own `RadioGroup<String>` and dropping the per-tile `groupValue`/`onChanged`. `flutter analyze` re-verified clean afterward (0 new warnings, only the two established pre-existing info categories, same count pattern every prior sprint has carried).
3. **The cart screen's own "some items are unavailable" warning line turned out to be quietly false the moment `rpc_place_order` existed.** It used to say unavailable items "won't be counted at checkout" -- which was a reasonable guess back when nothing actually checked out yet, but `rpc_place_order` refuses the *entire* checkout if any line is unavailable (`CART_HAS_UNAVAILABLE_ITEMS`), it doesn't quietly drop the bad lines. Caught while wiring the cart screen's "Proceed to checkout" button to a real destination for the first time. Corrected to the accurate instruction ("remove the unavailable items above"), and the button itself is now disabled while any are present, rather than sending the buyer to a checkout screen that cannot succeed.

### Mobile app (`proximity_app/`)

New feature folder `checkout`.

| File | Purpose |
|---|---|
| [proximity_app/lib/features/checkout/data/models/fulfillment_slot.dart](../../proximity_app/lib/features/checkout/data/models/fulfillment_slot.dart) | Mirrors the slot endpoint -- unavailable slots come back **with a reason**, not filtered out, per §7.4's own instruction ("disabled slots shown grayed with a reason rather than hidden"). |
| [proximity_app/lib/features/checkout/data/models/checkout_config.dart](../../proximity_app/lib/features/checkout/data/models/checkout_config.dart) | `CheckoutConfig` (the admin rider fee/slot settings) + `DiscountPreview`. |
| [proximity_app/lib/features/checkout/data/models/order_group.dart](../../proximity_app/lib/features/checkout/data/models/order_group.dart) | `OrderGroup` -- the one-charge/N-shops shape, nested exactly the way §4.8's redesign and §7.4 step 5 both insist on. |
| [proximity_app/lib/features/checkout/data/checkout_repository.dart](../../proximity_app/lib/features/checkout/data/checkout_repository.dart) | `getConfig`, `getSlots`, `previewDiscount` (returns `null` for an unusable code rather than throwing -- "this code doesn't work" isn't exceptional), `placeOrder`, `getOrderGroup`. |
| [proximity_app/lib/features/checkout/presentation/providers/checkout_providers.dart](../../proximity_app/lib/features/checkout/presentation/providers/checkout_providers.dart) | `checkoutConfigProvider`, `slotsProvider` (`.family`-keyed on shop/date/type, `.autoDispose`), and `CheckoutDraftNotifier`/`checkoutDraftProvider` -- the first real `StateNotifier` for actual multi-field UI state this project has needed (every prior sprint got away with plain `StateProvider`s or network-only `FutureProvider`s). Keeps §1.4's pay-at-shop/platform-rider invariant live in the draft itself: picking a rider delivery anywhere in the checkout forces the payment mode off `pay_at_shop` immediately, not just at submission. |
| [proximity_app/lib/features/checkout/presentation/widgets/slot_picker_sheet.dart](../../proximity_app/lib/features/checkout/presentation/widgets/slot_picker_sheet.dart) | §7.4 step 1's slot picker -- a 7-day strip over the real slot endpoint, unavailable slots shown greyed with their reason. |
| [proximity_app/lib/features/checkout/presentation/widgets/shop_fulfillment_card.dart](../../proximity_app/lib/features/checkout/presentation/widgets/shop_fulfillment_card.dart) | Per-shop-group card: pickup/delivery toggle (only the modes that shop actually offers), the delivery-fulfiller sub-choice **only when `delivery_mode = 'both'`** (a `self`/`platform` shop has exactly one legal answer, and asking would be theatre), the slot picker trigger, and a live below-minimum warning against that shop's `min_order_value`. |
| [proximity_app/lib/features/checkout/presentation/screens/checkout_screen.dart](../../proximity_app/lib/features/checkout/presentation/screens/checkout_screen.dart) | §7.4 steps 1-4, as one scrollable numbered-section screen rather than a wizard -- deliberate: a multi-shop cart routinely needs the buyer to go back and change one shop's slot after seeing the total, and a wizard turns that into a navigation problem. The pay button still gates on every step being complete. |
| [proximity_app/lib/features/checkout/presentation/screens/order_confirmation_screen.dart](../../proximity_app/lib/features/checkout/presentation/screens/order_confirmation_screen.dart) | §7.4 step 5 -- **one card per shop-group**, each with its own fulfillment type, slot, status, and delivery-fee line, "never a single merged summary line." |
| [proximity_app/lib/features/cart/data/models/cart_item.dart](../../proximity_app/lib/features/cart/data/models/cart_item.dart) | `CartItemShop` widened to carry the new fulfillment fields (defaulted on parse, not required, so a stale cached response shape can't crash a screen that doesn't even use them). |
| [proximity_app/lib/features/cart/presentation/screens/cart_screen.dart](../../proximity_app/lib/features/cart/presentation/screens/cart_screen.dart) | "Proceed to checkout" now pushes `/checkout` for real, disabled while any cart line is unavailable (see "Bugs caught" #3). |
| [proximity_app/lib/core/router/app_router.dart](../../proximity_app/lib/core/router/app_router.dart) | Added `/checkout`, `/order-groups/:id` -- both added to `_protectedPaths` (unlike `/cart`, these are pushed routes reached only from an already-authenticated cart, so gating them there is the right call, not the `/cart`-tab exception's reasoning). |

**Verified:** `flutter analyze` -- 0 errors, 0 warnings; 19 info-level style lints, the same two pre-existing categories every prior sprint has accepted (`prefer_initializing_formals`, `use_null_aware_elements`), 2 new instances in this sprint's own files. `dart run build_runner build` succeeds.
**Not verified:** never run on an emulator or physical device (none attached this session, same gap every sprint since Sprint 4 has carried), never connected to a real backend/database, the `CheckoutDraftNotifier`'s pay-at-shop auto-correction and the slot picker's day-strip were read and reasoned through but never actually tapped on a running app.

## What's genuinely unverified (worth being specific about, given the size of this sprint)

`rpc_place_order` is the single largest, most consequential piece of logic in this project to date, and it has never executed against a real Postgres instance -- not once. Every other sprint's raw SQL has had the same caveat, but this is the first one where the untested surface includes real money-splitting arithmetic, a 400+ line procedural function, window-function-based apportionment, and `AT TIME ZONE` arithmetic across a slot boundary. Specifically still unconfirmed against a live database:

- That the largest-remainder CTE (migrations/032 step 6b) actually compiles and executes as written -- the window-function/`ROW_NUMBER`/`ARRAY_AGG` combination was checked by hand against Postgres's documented semantics, not against a running query planner.
- That `AT TIME ZONE 'Asia/Kolkata'` behaves as expected on whatever Postgres version the eventual Supabase project runs (every other date computation in this codebase, `lib/slots.ts` included, uses a hardcoded `+5:30` offset specifically because there's no live database to confirm a named-zone lookup against -- this RPC is the first thing in the project to use one).
- That the two-pass loop (validate, then insert) doesn't hit some interaction with RLS or `SECURITY DEFINER` privilege boundaries this session can't see from reading the code alone.
- The entire mobile-to-backend round trip: the checkout screen has never sent a real `POST /v1/orders` body and seen a real response, typed error or success.

None of this changes the sprint's status honestly -- every prior sprint has carried some version of "unverified against live infra" -- but this sprint's unverified surface is qualitatively bigger than a CRUD route, and it deserves to be flagged as such rather than filed under the same one-line caveat as, say, a wishlist toggle.

## Exit criteria check

| Criterion | Status |
|---|---|
| A full multi-shop checkout produces one `order_groups` row and correct per-shop `orders` rows with the right fulfillment/slot/fee data | `rpc_place_order` is code-complete and traced by hand against every CHECK constraint in `orders`/`order_groups` (migrations/027/028) -- every branch that sets `delivery_fee`/`delivery_fulfilled_by` was verified to satisfy both CHECKs before this was called done. **Cannot execute** until migrations `000`-`032` are applied to a live Supabase project (unchanged blocker from every prior sprint) and at least two real approved shops with real products exist to check out from. |
| ...verified by hand against the CHECK constraints | Done as part of writing the RPC, not as an afterthought -- see "What rpc_place_order actually does" and the CHECK-constraint tracing called out there. Still "by hand," not "by Postgres actually enforcing them on a real row," which is the honest distinction this whole write-up keeps drawing. |

**Bottom line: Sprint 7 is development-complete and internally verified at every layer this project has tooling for** (`deno check`, `flutter analyze`, `dart run build_runner build`) -- same as every prior sprint, the remaining gap is that nothing here has touched a live Supabase project, and this sprint's centerpiece RPC in particular carries a larger-than-usual amount of untested-against-real-Postgres logic, flagged explicitly above rather than folded into the standard one-line caveat.

## Not yet built (by design, deferred to the sprint that actually needs it)

- **Real payment.** `payment_status` never leaves `'pending'` this sprint -- see "The stubbed-payment / 'no real gateway' boundary" above for exactly what that does and doesn't mean. Sprint 8 (§11) is the `PaymentGateway` abstraction, the Razorpay adapter, `rpc_confirm_payment`, and the `shop_ledger_entries` insertion this sprint's own table sits waiting for.
- **Order history / Order Again.** This sprint's `GET /v1/order-groups/:id` is a single-group read for the checkout flow's own confirmation step, not a list. The `/order-again` bottom tab is still Sprint 10's placeholder.
- **Rider assignment and live tracking.** `orders.rider_id` stays NULL even for `platform_rider` groups; §7.5's Realtime subscription on `order_status_history` is Sprint 9's job.
- **Quantity-discount progress banner and `product_discounts`.** §11 explicitly keeps this hidden this sprint -- see "A third table needed a fresh design against prose" above.
- **Admin discount authoring UI.** `discounts` has RLS and one seeded code (`PROX10`); Sprint 12 (§11) is the admin panel that lets someone create more without touching SQL directly.
- **A dry-run/preview mode on `rpc_place_order` itself.** The discount-preview route computes its own small, duplicated copy of the discount math (three rules, same order) rather than calling into a preview mode on the real placement RPC -- a deliberate, bounded duplication (routes/checkout.ts's own header explains the trade) rather than building a second execution path through the RPC this sprint didn't need.

## What you need to run

Same list Sprint 3/4/5/6.md carried, plus seven new files:

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
026_create_discounts.sql                -- Sprint 7, new
027_create_order_groups.sql             -- Sprint 7, new
028_create_orders.sql                   -- Sprint 7, new
029_create_order_items.sql              -- Sprint 7, new
030_create_order_status_history.sql     -- Sprint 7, new
031_create_shop_ledger_entries.sql      -- Sprint 7, new
032_rpc_place_order.sql                 -- Sprint 7, new
```

If `000`-`025` are already confirmed applied, only **`026`-`032`** are new and need running, strictly in that order (`026` before `027`, since `order_groups.discount_id` references it; `027` before `028`; `032` last, since it references every table this sprint creates).

**Given this sprint's centerpiece has never touched a real database, running it for real and placing one actual multi-shop test order -- two shops, at least one delivery and one pickup, a discount code applied -- would be worth doing before treating this sprint's exit criteria as more than "verified by hand."**

## What Sprint 8 needs from you before it can be verified either

Same shape as every prior sprint, unchanged: Sprint 8 (payments -- the `PaymentGateway` abstraction, Razorpay adapter, `rpc_confirm_payment`, invoice generation) can be written without a live Supabase project, but proving any of it -- this sprint's checkout core included -- needs the migrations actually applied, real Razorpay/PayU test credentials (SPRINT_PLANNING.md §13's "still genuinely open" list names live commercial terms as needed "before Sprint 8 starts, not before" -- that's now), at least two real approved shops with real products, and a physical device or working emulator this session still doesn't have access to.

---

**Waiting for your go-ahead before starting Sprint 8**, per your instruction to stop at sprint boundaries.
