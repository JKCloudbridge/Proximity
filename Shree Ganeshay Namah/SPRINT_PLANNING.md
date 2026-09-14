# Proximity — Architecture & Sprint Planning (v2)
*श्री गणेशाय नमः*

**Status:** Pre-Sprint-0. Supersedes the v1 pass in this same file — v1 is preserved in git/version history if you're tracking this folder with source control (if not, start now, see §3.4).
**What changed since v1, and why this is a rewrite, not a patch:** you reversed the single-shop-cart decision (cart is now multi-shop, one charge), added a full rider network alongside shop self-delivery, asked for an explicit RPC/access-control layer, want PayU evaluated against Razorpay, and want delivery/pickup slots unified on a platform-wide 6 AM–12 AM/2-hour default with admin control over the fee. Every one of those touches the `orders` table, so a section-by-section patch would leave stale cross-references. This version is internally consistent end to end.

**Inputs reviewed (unchanged from v1):** `whisk-app-mockup.html` (visual pattern reference only), and the full prior codebase at `C:\Users\hemin\OneDrive\Desktop\Android Project`.

---

## Table of contents

1. [Read this first](#1-read-this-first)
2. [System map](#2-system-map)
3. [Prerequisites](#3-prerequisites)
4. [Supabase schema](#4-supabase-schema)
5. [Access control & RPC architecture](#5-access-control)
6. [Design system](#6-design-system)
7. [Buyer app UX spec](#7-buyer-app-ux-spec)
8. [Shopkeeper, rider & admin spec](#8-shopkeeper-rider-admin)
9. [What we're reusing from Baker Ally](#9-reuse-map)
10. [Feature backlog](#10-feature-backlog)
11. [Sprint plan — full draft](#11-sprint-plan)
12. [Requirements traceability](#12-traceability)
13. [Open decisions log](#13-open-decisions)

---

## 1. Read this first <a name="1-read-this-first"></a>

### 1.1 iOS — noted, scoped into one sprint, not a running worry

Per your instruction, I've stopped treating this as a cross-cutting risk to flag everywhere. It gets exactly one home: **Sprint 14** does the actual Xcode-side build/sign/TestFlight work, on a Mac (yours, or a cloud one — Codemagic/GitHub Actions macOS runners if you don't have physical Mac access when that sprint arrives; either is fine, decide it when you get there, not now). Sprint 0 only does the cheap, non-blocking prep that's annoying to leave until the last minute: register the Apple Developer Program account ($99/yr) and note the **Sign in with Apple** requirement (Apple rejects an app that offers Google Sign-In without it, App Store Review Guideline 4.8 — build it alongside Google/Email-OTP auth in Sprint 1, not as a Sprint 14 scramble).

**"Keep code organised so it doesn't jumble later"** — concretely, that means:
- Never branch on `Platform.isAndroid`/`Platform.isIOS` scattered through feature code. Centralize the handful of places that genuinely need it (push-token registration, permission prompts, deep-link scheme) behind one small `lib/core/platform/` abstraction with a single implementation per platform.
- All environment/config values (Supabase URL/anon key, Razorpay/PayU keys, Maps API key) live in `.env` via `envied` (same as Baker Ally), never hardcoded — this is what makes "test on Windows against staging, build for iOS on a Mac against the same staging project" a non-event.
- Standard Flutter `ios/` and `android/` platform folders stay untouched by hand-edits where possible; anything that must be hand-edited (Podfile, entitlements, `Info.plist` permission strings) gets a comment explaining why, so a second person (or Mac) picking this up doesn't have to reverse-engineer it.

### 1.2 Roles, decided explicitly (you asked "I hope you have planned the roles")

Four platform-level roles, plus one shop-scoped membership table for anything finer-grained than "which platform role":

| Role (`users.role`) | Who | Scope |
|---|---|---|
| `buyer` | Everyone by default, including shop owners acting as customers | Their own cart/orders/addresses/wishlist/organizer lists |
| `shop_owner` | Created a shop | Owns ≥1 row in `shops`; full control over that shop via `shop_team_members` membership with `member_role='owner'` |
| `rider` | Proximity's own delivery fleet | Their own assigned deliveries only |
| `admin` | Platform ops | Category governance, shop/rider approval, commission & delivery-fee settings, discount authoring |

**Shop staff and shop-employed delivery people are *not* a global role** — they're membership rows in `shop_team_members` (below), scoped to one specific shop, with a `member_role` of `owner`/`staff`/`delivery`. This is the correct normalization: a global `shop_staff` role (what v1 had) can't answer "staff of *which* shop," which is exactly the question RLS needs answered on every query.

```sql
CREATE TABLE shop_team_members (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id      UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  member_role  TEXT NOT NULL CHECK (member_role IN ('owner','staff','delivery')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (shop_id, user_id)
);
ALTER TABLE shop_team_members ENABLE ROW LEVEL SECURITY;
```

Full permission matrix in §5.3.

### 1.3 Delivery — both shop-fulfilled and platform riders, as instructed

Reversing my v1 recommendation (I'd suggested shop-only to cut scope) — you want both, so both get built, with per-shop control over which:

```sql
ALTER TABLE shops ADD COLUMN delivery_mode TEXT NOT NULL DEFAULT 'self'
  CHECK (delivery_mode IN ('self', 'platform', 'both'));
```
- `self` — the shop's own person delivers (a `shop_team_members` row with `member_role='delivery'`, or the owner/staff themselves). **No delivery fee** — your instruction, enforced at the DB level (§4.7 CHECK constraint), not just in the UI.
- `platform` — every delivery order for this shop is auto-assigned to a Proximity rider. Delivery fee applies, amount set by admin (§4.6), not the shop.
- `both` — shop chooses per order at accept-time (self-deliver this one, or hand it to a platform rider); a Phase-2 refinement is auto-escalating to a platform rider if the shop hasn't accepted within N minutes, not built in MVP.

A genuinely new entity for the rider side — Proximity's own fleet, full schema in §4.6.

### 1.4 Payments — Razorpay vs PayU, honestly, and a "pay at shop" mode you also asked for

**I'm not going to assert one is cheaper than the other.** I don't have verified, current (2026) MDR/fee schedules for Razorpay or PayU, and India payment-gateway pricing changes with volume tiers, payment method (UPI vs cards vs wallets), and negotiated rates — a number I typed from training data could easily be stale or just wrong. **Get live quotes from both before Sprint 8 (payments integration) starts** — that decision materially affects your unit economics on every transaction, so it deserves a real quote, not my guess.

What I *can* say with confidence, engineering-side:
- **Razorpay** has the more mature Flutter ecosystem (`razorpay_flutter` on pub.dev is the standard, widely-used package), and your prior project already has a working, provable integration (`checkout_repository.dart`'s exception-mapping pattern) to lift almost verbatim. It also has **Razorpay Route**, a purpose-built marketplace split-payment product, relevant once automated shop payouts happen (§4.7's `shop_ledger_entries`).
- **PayU** is a legitimate, established Indian gateway with its own marketplace/split product, but I have lower confidence in the current maturity of its Flutter-specific SDK — worth a spike (a day, not a sprint) confirming what the current best-maintained Flutter package actually is before committing engineering time.
- Neither is "Supabase supported" in any special sense — **Supabase has no native payment-gateway integration for anyone.** Both integrate identically: your app opens the gateway's checkout SDK, the gateway calls your Edge Function webhook on completion, you verify the signature and update your DB. This is provider-agnostic by construction; the choice doesn't change your Supabase architecture at all.

**My recommendation:** build a small `PaymentGateway` interface (both in the Edge Function backend and as a thin Flutter wrapper) with `createOrder()` / `verifyPayment()` / `handleWebhook()` methods, implement the Razorpay adapter first for MVP, keep a PayU adapter stub. Swapping or running both becomes a config flag, not a rewrite, so this decision stops being expensive to revisit.

**Pay-at-shop, which you also specified** ("for pickup and delivery by shopkeeper payments is anyways done on shopkeeper's UPI or their payment method") — this is a **second, non-gateway payment mode**, not a Razorpay/PayU detail:

```sql
-- on order_groups, see §4.7
payment_mode TEXT NOT NULL CHECK (payment_mode IN ('online', 'pay_at_shop'))
```

- `online` — Razorpay/PayU, required whenever *any* shop in the checkout is fulfilled by a **platform rider** (a rider has no business collecting a shop's cash/UPI on that shop's behalf — that's an operational and trust problem, not a payments one).
- `pay_at_shop` — cash or the shop's own UPI, settled directly between buyer and shop at pickup or shop-self-delivery. Proximity collects **zero money** on this order. Only allowed when every shop-group in the checkout uses `delivery_mode` `self` (or is a pickup). This is a genuine simplification for the self-fulfillment case — no platform money custody, no payout owed — but it flips the settlement direction: **the platform is now owed commission** on money it never touched, tracked as a receivable in `shop_ledger_entries` (§4.7) rather than a payable. Both directions are schema-complete in this plan; actual settlement automation is still Phase 2 (unchanged from v1's reasoning), but nothing here blocks it from being wired up later without a schema change.

### 1.5 Cart is multi-shop, one charge — the actual redesign

You want a cart that spans shops, charged once, with each shop's fulfillment shown correctly and independently. This is the standard Amazon/Flipkart marketplace-cart pattern: **one `order_groups` row per checkout (one payment), one `orders` row per shop inside it** (own fulfillment type, own slot, own status, own delivery mode). Full schema and the placement RPC are in §4.7/§5. The cart table itself goes back to being simple — no shop lock, no trigger:

```sql
CREATE TABLE cart_items (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cart_id     UUID NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
  variant_id  UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
  quantity    INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
  added_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (cart_id, variant_id)
);
```
The Flutter cart screen groups `cart_items` by shop client-side for display ("3 items from Shop A", "2 items from Shop B" as separate collapsible sections) — this is a presentation concern, not a data-model constraint, which is the correct place for it once the cart itself is allowed to be mixed.

### 1.6 Delivery/pickup slots — unified, your 6 AM–12 AM / 2-hour rule

Both pickup and delivery now use the **same slot mechanism**: platform-wide default template, 06:00–24:00 in 2-hour buckets (9 slots/day: 6–8, 8–10, 10–12, 12–2, 2–4, 4–6, 6–8pm, 8–10pm, 10–12am), clipped by each shop's actual `shop_business_hours` (a shop closed at 9pm simply doesn't offer the 10pm slot) and `shop_blackout_dates`. I unified pickup onto the same mechanism rather than keeping it on separate per-shop granularity as in v1 — you only specified the 2-hour rule for delivery, but running two different slot-generation code paths for what's conceptually the same problem is needless complexity; override this if you actually want pickup slots to work differently. The granularity itself (`120` minutes) and the window (`06:00`–`24:00`) are **admin-configurable settings** (§4.6), not hardcoded, satisfying the same "admin controls this" principle you stated for the delivery fee.

Your worked example — "delivery is on 10 AM, it's 9:20 AM, show 40 min" — is a live countdown-to-slot-boundary badge, spec'd in §7.2.

### 1.7 Still true from v1, unchanged

- Windows still can't run Xcode (§1.1 — now scoped to one sprint instead of raised as a constant risk).
- Stock-count accuracy from small kirana shops is still a real trust risk; the `stock_status` coarse toggle mitigation (§4.5) stands.
- Two-sided marketplace cold start is still real; the referral-to-onboard-shops idea (§10) still stands.
- Paise-integer money, UUID PKs, RLS-on-everything, `TIMESTAMPTZ` — unchanged conventions throughout.

---

## 2. System map <a name="2-system-map"></a>

Still three deployables — **riders don't get a fourth app**, they get a role inside `proximity_app`, same lightweight-touchpoint treatment as shopkeepers (§8):

| Component | Stack | Serves |
|---|---|---|
| **`proximity_app`** | Flutter (iOS + Android) | Buyers, plus lightweight in-app views for shop-order-notifications (shopkeepers/staff) and rider delivery tasks |
| **`proximity_web`** | Next.js 16, TypeScript, Tailwind, shadcn/ui | Shopkeeper dashboard (catalog, orders, sales, invoices, team) + internal admin (shop/rider approval, categories, commission, delivery-fee & slot settings, discounts, ledger) |
| **`proximity_backend`** | One Supabase Edge Function (`api`), Deno + Hono + Drizzle + Zod | All REST routes, three role-gated namespaces: `/v1/*` (buyer), `/v1/shop/*` (shop team), `/v1/admin/*` (admin). Riders get `/v1/rider/*`. |
| Supabase | Postgres + PostGIS + Auth + Storage + Realtime + `pg_cron` + `pg_net` | Source of truth, RLS everywhere, SECURITY DEFINER RPCs for anything cross-table (§5) |

---

## 3. Prerequisites <a name="3-prerequisites"></a>

### 3.1 Local toolchain

Unchanged from v1 except iOS is no longer front-loaded as urgent:

| Tool | Purpose |
|---|---|
| Flutter SDK (latest stable) + Dart (bundled) | Mobile app |
| Android SDK **command-line tools** + `platform-tools` (adb) + `build-tools`/`platforms` for your target `compileSdk` | Still required to build the Android APK even without an emulator — see v1's correction, unchanged |
| Java JDK 17+ (Temurin) | Gradle |
| Node.js 20 LTS+ | Next.js website |
| Supabase CLI | Migrations, secrets, deploy |
| Deno | Local Edge Function testing |
| Xcode + CocoaPods | **On a Mac, when Sprint 14 arrives** — not needed before then |

### 3.2 Cloud accounts

- **Supabase** — two projects, `proximity-staging` / `proximity-prod`.
- **Google Cloud project** — OAuth clients (Android SHA-1 + iOS bundle ID), Geocoding API + Places Autocomplete (address entry, lat/lng resolution), Maps SDK if the map-view backlog item (§10) is built.
- **Apple Developer Program** ($99/yr) — register in Sprint 0, used in Sprint 14. Includes Sign in with Apple capability (§1.1).
- **Firebase** — FCM push, Crashlytics, Analytics; iOS needs an APNs Auth Key uploaded to Firebase.
- **Razorpay** — test keys, evaluate Route for future split payouts.
- **PayU** — test/sandbox keys, confirm current Flutter SDK maturity and marketplace-split product before Sprint 8.
- **Optional:** Upstash Redis, Sentry (backend-side error tracking, complements mobile-only Crashlytics).

### 3.3 App identity

Unchanged from v1: propose `com.proximity.app`, deep-link `com.proximity.app://login-callback`, confirm before Sprint 1's OAuth/Firebase registration.

### 3.4 Source control — not previously flagged, flagging now

Nothing in the prerequisites conversation has mentioned git. **Set up a git repo for this project before Sprint 0's scaffolding work starts** — three deployables plus a schema that's already gone through two substantial redesigns in one afternoon is exactly the situation where "keep things organised, not jumbled" (your own words) requires version history, not just careful file naming. GitHub/GitLab private repo, protected `main`, feature branches — standard practice, worth stating explicitly since it wasn't mentioned yet.

### 3.5 Backend pattern

Unchanged: one Edge Function, Drizzle+Zod, hand-numbered `/migrations/*.sql` applied via `supabase db query -f ... --linked`, `custom_access_token_hook` for role claims (now carrying `role` +, for shop-team members, their `shop_id`/`member_role` pairs so the JWT itself can shortcut simple RLS checks without a subquery on every request — a worthwhile optimization once you have real traffic, not required for MVP correctness since RLS subqueries against `shop_team_members` work fine either way). `pg_cron` + `pg_net` + PostGIS all enabled, same as v1.

### 3.6 Storage

Buckets: `shop-logos`, `shop-media`, `product-images`, `invoices` (private), `rider-documents` (private — KYC docs for rider onboarding, new vs. v1).

---

## 4. Supabase schema <a name="4-supabase-schema"></a>

Sections unchanged from v1 are noted as such rather than re-justified at length.

### 4.1 Identity & roles

```sql
CREATE TABLE users (
  id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role          TEXT NOT NULL DEFAULT 'buyer'
                  CHECK (role IN ('buyer', 'shop_owner', 'rider', 'admin')),
  full_name     TEXT,
  phone         TEXT,
  email         TEXT,
  avatar_url    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
```

Plus `shop_team_members` from §1.2.

### 4.2 Addresses — unchanged from v1

`addresses` with `GEOGRAPHY(Point,4326) location`, populated via Geocoding API or device GPS. See v1 rationale, nothing changed here.

### 4.3 Categories & shop sub-categories — unchanged from v1

Global curated `categories` (20-item seed list — Groceries & Staples, Fruits & Vegetables, Dairy/Bread & Eggs, Snacks & Beverages, Bakery & Cakes, Meat/Fish & Poultry, Frozen Foods, Beauty & Cosmetics, Personal Care, Household Essentials, Baby Care, Health & Wellness [OTC-only, licensing caution stands], Stationery & Office, Electronics & Mobile Accessories, Hardware & Tools, Home/Kitchen & Décor, Toys/Games & Gifts, Pet Supplies, Gardening & Plants, Festive & Seasonal), plus per-shop `shop_sub_categories` with the `icon_url` field powering the shop-detail rail interaction. `products.is_veg` FSSAI-labelling flag unchanged. Full DDL identical to v1 — not repeated here to keep this revision focused on what actually changed; pull it from the v1 content already discussed if you need the literal SQL restated.

### 4.4 Shops

```sql
CREATE TABLE shops (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id               UUID NOT NULL REFERENCES users(id),
  name                   TEXT NOT NULL,
  description            TEXT,
  logo_url               TEXT,
  cover_image_url        TEXT,
  gstin                  TEXT,
  fssai_license_no       TEXT,
  address_line           TEXT NOT NULL,
  city                   TEXT NOT NULL,
  pincode                TEXT NOT NULL,
  location               GEOGRAPHY(Point, 4326) NOT NULL,
  service_radius_km      NUMERIC(4,1) NOT NULL DEFAULT 3.0,
  supports_pickup        BOOLEAN NOT NULL DEFAULT true,
  supports_delivery      BOOLEAN NOT NULL DEFAULT true,
  delivery_mode          TEXT NOT NULL DEFAULT 'self' CHECK (delivery_mode IN ('self','platform','both')),
  min_order_value        INTEGER NOT NULL DEFAULT 0,
  status                 TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','suspended')),
  platform_commission_pct NUMERIC(4,2) NOT NULL DEFAULT 10.00,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_shops_location ON shops USING GIST(location);
ALTER TABLE shops ENABLE ROW LEVEL SECURITY;
```

**Changed vs. v1:** `delivery_fee` column **removed** — it's no longer a per-shop, shopkeeper-controlled field (per your instruction), it's an admin-controlled platform setting (§4.6). `delivery_mode` added (§1.3).

`shop_business_hours` and `shop_media` unchanged from v1.

On shop creation, insert a `shop_team_members` row for the creator with `member_role='owner'` in the same transaction — a shop with no owner-membership row would be locked out of its own RLS-gated data.

### 4.5 Products & variants — unchanged from v1

`products` (shop-scoped, `is_veg`, `info_message`, search vector) and `product_variants` (`unit_value`/`unit_label` split for price-per-unit math, `stock_status` coarse toggle alongside precise `stock_qty`) carry over exactly as designed in v1 — nothing about the delivery/cart/payment changes touches the catalog layer.

### 4.6 Platform settings & slots — new structure

Replaces v1's per-shop `pickup_slot_minutes` with an admin-controlled, key-value platform settings table — deliberately generic so future admin-tunable constants (default commission %, slot window) don't each need their own migration:

```sql
CREATE TABLE platform_settings (
  key         TEXT PRIMARY KEY,
  value       JSONB NOT NULL,
  updated_by  UUID REFERENCES users(id),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE platform_settings ENABLE ROW LEVEL SECURITY;

-- Seeded rows (Sprint 2):
-- ('platform_rider_delivery_fee', '{"amount_paise": 3000}')   -- admin-editable, your instruction
-- ('slot_window',                 '{"start": "06:00", "end": "24:00", "slot_minutes": 120}')
-- ('default_shop_commission_pct', '{"value": 10.00}')
```

```sql
CREATE TABLE shop_blackout_dates (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id   UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  date      DATE NOT NULL,
  reason    TEXT,
  UNIQUE (shop_id, date)
);
ALTER TABLE shop_blackout_dates ENABLE ROW LEVEL SECURITY;
```

`GET /v1/shops/:id/fulfillment-slots?date=YYYY-MM-DD&type=pickup|delivery` generates candidate slots from `platform_settings.slot_window` intersected with that weekday's `shop_business_hours` and `shop_blackout_dates`, drops past-today slots, and annotates each with a live countdown (§7.2) and, if capacity limits are ever added, a booked count. No standing table of empty future slots.

### 4.7 Riders

```sql
CREATE TABLE riders (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  full_name         TEXT NOT NULL,
  phone             TEXT NOT NULL,
  vehicle_type      TEXT CHECK (vehicle_type IN ('bike','scooter','bicycle','on_foot')),
  vehicle_number    TEXT,
  status            TEXT NOT NULL DEFAULT 'offline' CHECK (status IN ('offline','available','on_delivery')),
  current_location  GEOGRAPHY(Point, 4326),
  is_verified       BOOLEAN NOT NULL DEFAULT false,   -- admin KYC approval, mirrors shops.status gate
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_riders_location ON riders USING GIST(current_location);
ALTER TABLE riders ENABLE ROW LEVEL SECURITY;
```

`riders.user_id` gets `role='rider'` in `users`. Onboarding mirrors shop onboarding: signup → KYC documents to the private `rider-documents` bucket → `is_verified=false` → admin approval (§8).

### 4.8 Orders — the actual multi-shop-cart, single-charge redesign

```sql
-- One row per checkout = one payment. This is what gets charged once.
CREATE TABLE order_groups (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  payment_mode        TEXT NOT NULL CHECK (payment_mode IN ('online','pay_at_shop')),
  payment_gateway     TEXT CHECK (payment_gateway IN ('razorpay','payu')),   -- NULL when pay_at_shop
  gateway_order_id    TEXT,
  gateway_payment_id  TEXT UNIQUE,
  subtotal            INTEGER NOT NULL,
  discount_value      INTEGER NOT NULL DEFAULT 0,
  delivery_fee_total  INTEGER NOT NULL DEFAULT 0,
  total               INTEGER NOT NULL,           -- the ONE amount charged to the customer
  payment_status      TEXT NOT NULL DEFAULT 'pending'
                         CHECK (payment_status IN ('pending','paid','failed','collected_at_shop')),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE order_groups ENABLE ROW LEVEL SECURITY;

-- One row per shop inside that checkout — own fulfillment, own slot, own status.
CREATE TABLE orders (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_group_id         UUID NOT NULL REFERENCES order_groups(id) ON DELETE CASCADE,
  user_id                UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  shop_id                UUID NOT NULL REFERENCES shops(id),
  fulfillment_type       TEXT NOT NULL CHECK (fulfillment_type IN ('pickup','delivery')),
  delivery_fulfilled_by  TEXT CHECK (delivery_fulfilled_by IN ('shop','platform_rider')),  -- NULL if pickup
  address_id             UUID REFERENCES addresses(id),
  slot_start             TIMESTAMPTZ NOT NULL,
  slot_end               TIMESTAMPTZ NOT NULL,
  rider_id               UUID REFERENCES riders(id),    -- set only when delivery_fulfilled_by='platform_rider'
  status                 TEXT NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending','confirmed','preparing','ready_for_pickup',
                                               'out_for_delivery','completed','cancelled')),
  subtotal               INTEGER NOT NULL,                  -- this shop's share only
  discount_value         INTEGER NOT NULL DEFAULT 0,
  delivery_fee           INTEGER NOT NULL DEFAULT 0,
  platform_commission_pct NUMERIC(4,2) NOT NULL,            -- snapshotted from shops at order time
  total                  INTEGER NOT NULL,                  -- this shop's share of the one combined charge
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (
    (fulfillment_type = 'delivery' AND address_id IS NOT NULL AND delivery_fulfilled_by IS NOT NULL) OR
    (fulfillment_type = 'pickup' AND delivery_fulfilled_by IS NULL)
  ),
  -- Your instruction, enforced at the DB layer, not just the UI: no delivery
  -- fee unless a platform rider is actually doing the delivery.
  CHECK (delivery_fee = 0 OR delivery_fulfilled_by = 'platform_rider')
);
CREATE INDEX idx_orders_user_created ON orders(user_id, created_at DESC);
CREATE INDEX idx_orders_shop_created ON orders(shop_id, created_at DESC);
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

CREATE TABLE order_items (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id      UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  variant_id    UUID NOT NULL REFERENCES product_variants(id),
  product_name  TEXT NOT NULL,
  variant_name  TEXT NOT NULL,
  quantity      INTEGER NOT NULL,
  unit_price    INTEGER NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

CREATE TABLE order_status_history (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id    UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  status      TEXT NOT NULL,
  note        TEXT,
  changed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE order_status_history ENABLE ROW LEVEL SECURITY;
```

**Why this satisfies "charge once, show delivery status correctly per shop":** the customer sees and pays `order_groups.total` exactly once (one Razorpay/PayU sheet, or one pay-at-shop confirmation). Order history and tracking then render **one card per `orders` row**, each independently showing its own `fulfillment_type`, `slot_start`/`slot_end`, `delivery_fulfilled_by`, and `status` — "Shop A: pickup, 4–6 PM, ready for pickup" and "Shop B: delivery, 10 AM–12 PM, out for delivery" as two clearly separate cards under one order confirmation, never merged into a single ambiguous status line.

Also note: **the shopkeeper dashboard's order list already only shows their own shop's `orders` rows by construction** — nothing about the multi-shop cart leaks cross-shop visibility, because `orders` stayed per-shop the whole time; only the payment step got unified. Your point 5 concern ("shopkeeper's dashboard would show only items sold from their shop") holds automatically, enforced further by RLS in §5.

### 4.9 Ledger — replaces v1's `payouts` table

Needed in both directions now that `pay_at_shop` is a real MVP payment mode, not deferred:

```sql
CREATE TABLE shop_ledger_entries (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id      UUID NOT NULL REFERENCES shops(id),
  order_id     UUID REFERENCES orders(id),
  entry_type   TEXT NOT NULL CHECK (entry_type IN ('payout_due', 'commission_due')),
  -- payout_due: platform collected online, owes the shop (total - commission)
  -- commission_due: shop collected pay_at_shop directly, owes the platform its commission cut
  amount       INTEGER NOT NULL,      -- paise, always positive; entry_type gives direction
  status       TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','settled')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE shop_ledger_entries ENABLE ROW LEVEL SECURITY;
```

One `rpc_confirm_payment`/`rpc_place_order` call inserts the correct entry automatically depending on `order_groups.payment_mode` — online orders create a `payout_due` row per shop sub-order, pay-at-shop orders create a `commission_due` row instead. Settlement batching (actually moving money) is still Phase 2, unchanged reasoning from v1 §1.3(b) — the schema no longer blocks it either way, which is the improvement over v1.

### 4.10 Invoices, wishlist, cross-sell, organizer — unchanged from v1

`invoices` stays keyed to `orders.id` (the per-shop sub-order, not `order_groups`) because each shop needs its own GST invoice under its own GSTIN — this was already correct in v1 and needed no change. `wishlists`/`product_cross_sell` carry over unchanged (and turned out to be literally recoverable from Baker Ally's own migrations, Sprint 6/7). **`recurring_lists`/`recurring_list_items` do NOT carry over from anywhere — corrected in Sprint 11, same "revisit the reuse map against reality" discipline Sprint 6/8/10 each applied to a different false reuse claim.** Checked directly before Sprint 11 started: no `recurring_list`/organizer migration, route, or screen exists anywhere in Baker Ally's actual working tree — not even a prose spec the way Order Again's `03_order_again_tab.md` existed. `migrations/043`'s own header has the full "fresh design against thin prose" account; organizer/reminder-mode is this project's own design, not a v1 carryover.

---

## 5. Access control & RPC architecture <a name="5-access-control"></a>

This is the direct answer to your point 2 ask — an explicit, organized layer, not implicit trust in the app to behave.

### 5.1 The rule

**Corrected during Sprint 1 implementation** (see `Sprint planning/Sprint 1.md` for the full story) — the original draft of this section said the client could call `supabase.rpc()` directly for simple RPCs. That's wrong for this backend's actual connection shape, confirmed by reading Baker Ally's `lib/db.ts`/`lib/supabaseAdmin.ts`: `proximity_backend` connects to Postgres via postgres.js over the Supavisor pooler using the **service-role** connection string, the same way Baker Ally's Edge Function does. That connection is never mediated by PostgREST, so `auth.uid()`/`auth.jwt()` are never populated on it — an RPC written to trust `auth.uid()` would silently see NULL and reject its own caller. So, revised:

**RLS is enabled on every table with no exceptions** (already stated throughout §4) as a **defense-in-depth backstop** — it protects any access path that genuinely goes through PostgREST with a real user JWT (the Supabase dashboard's table editor, for instance), but it is *not* the live enforcement mechanism for the app's normal data flow. **The actual trust boundary is the Edge Function's own `authMiddleware`**, which verifies the caller's JWT once per request (`supabaseAdmin.auth.getUser(token)`, mirroring Baker Ally exactly) — every route handler, and every RPC it calls, trusts the resulting user id from there on. Concretely: **all business data, all RPC calls, everything except the Supabase Auth calls themselves, goes through Dio → the Edge Function** — no direct `supabase.rpc()`/PostgREST calls from Flutter at all, keeping one single consistent trust boundary instead of two. RPC functions that need "which user is this" take it as an explicit parameter (`p_user_id`) passed by the already-authenticated route, not `auth.uid()` — see `rpc_set_default_address` (`migrations/005`) for the reference shape, including why it deliberately has *no* internal re-check of the caller's identity (it trusts its one intended caller, the Edge Function, completely — and is `REVOKE`d from `authenticated`/`anon` specifically so nothing else can call it).

Cross-table business logic — checkout, order-status transitions, rider assignment, invoice generation — still goes through a `SECURITY DEFINER` Postgres function rather than a raw multi-statement client-side `INSERT`/`UPDATE`, for the same reason as before: correctness that depends on more than one row changing atomically shouldn't live in application code that can partially fail. That part of the original design was right; only the "how the client reaches it" part needed fixing.

**Second correction, made during Sprint 9 implementation** (see `Sprint planning/Sprint 9.md`): the paragraph above is complete for `proximity_backend`'s own connection, but Sprint 9 is the first sprint to make `proximity_app` talk to Supabase over a *second*, genuinely different path — Supabase Realtime's "Postgres Changes" feature (§7.5's buyer-tracking subscription, §8.5's rider-assignment-notification fallback). That path is **not** mediated by the Edge Function at all: it authorizes itself directly against the app's own ambient Supabase Auth session (the ordinary ID-token session every signed-in user already holds, the same one `dio_client.dart`'s interceptor reads a JWT copy from), and Supabase evaluates every change against *that* session's own RLS policies before ever sending it to the client. So, for Realtime specifically: **RLS is not a backstop, it is the live and only enforcement mechanism** — a row a policy doesn't cover is invisible to a Realtime subscriber, silently, not an error. `migrations/038` exists specifically because this was checked and found true: `orders`/`order_status_history` had no rider-facing SELECT policy at all before that migration, which would have made the rider-side subscription receive nothing. Nothing else in this project's data flow changes — `supabase.rpc()`/direct PostgREST calls for business data are still never used, per the rule above — this is additive: a second, narrower trust boundary that only Realtime subscriptions exercise, layered on top of the first.

### 5.2 RLS pattern by data-ownership class

| Ownership class | Tables (examples) | Policy shape |
|---|---|---|
| Own-user data | `addresses`, `carts`/`cart_items`, `wishlists`, `recurring_lists`, `order_groups`, `orders` (as buyer) | `USING (user_id = auth.uid())` |
| Shop-team data | `products`, `product_variants`, `shop_sub_categories`, `orders`/`order_items` (as shop), `shop_ledger_entries`, `invoices` | `USING (shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid()))`, write access further narrowed by `member_role` (§5.3) |
| Rider-own data | `riders` (own row), assigned `orders` (read + status update only) | `USING (rider_id = (SELECT id FROM riders WHERE user_id = auth.uid()))` |
| Admin-only | `categories`, `platform_settings`, `shops.status`/`platform_commission_pct`, `riders.is_verified`, `discounts` | `USING (get_role() = 'admin')`, reusing the same JWT-claim-role helper function pattern as Baker Ally's custom access-token hook |
| Public/global read | `categories`, active `shops`/`products`/`product_variants` for browsing | Permissive `SELECT`, no user match — but never a permissive `INSERT`/`UPDATE`/`DELETE` policy on these |

### 5.3 Shop team permission matrix

| Action | `owner` | `staff` | `delivery` |
|---|---|---|---|
| Edit shop settings, delivery mode, business hours | ✅ | ❌ | ❌ |
| Manage team members | ✅ | ❌ | ❌ |
| Add/edit catalog (products, variants, stock) | ✅ | ✅ | ❌ |
| View orders & accept/advance status (`self`-fulfilled deliveries, pickups) | ✅ | ✅ | ✅ (status advance only) |
| View sales summary / ledger / invoices | ✅ | ✅ (read-only) | ❌ |

### 5.4 Core RPCs to build

| RPC | Called by | What it enforces |
|---|---|---|
| `rpc_add_to_cart(variant_id, qty)` | buyer | Upsert into `cart_items`, stock-status check |
| `rpc_place_order(cart_id, per_shop_fulfillment[], payment_mode)` | buyer | Groups cart by shop → validates each shop's chosen slot/mode against `shops.delivery_mode`/`shop_business_hours` → computes per-shop `subtotal`/`discount`/`delivery_fee` (§4.6/§4.8) → creates one `order_groups` + N `orders` + `order_items` in one transaction → for `pay_at_shop`, refuses if any shop-group uses `platform_rider` (§1.4) |
| `rpc_confirm_payment(gateway_payment_id, signature)` | webhook (service role, not end-user) | Verifies gateway signature → sets `order_groups.payment_status='paid'` → cascades every child `orders.status` to `confirmed` → inserts `payout_due` ledger entries per shop |
| `rpc_shop_advance_order_status(order_id, new_status)` | shop team (`owner`/`staff`/`delivery` per §5.3) | Validates the status transition is legal for this shop's own order, writes `order_status_history` |
| `rpc_assign_rider(order_id)` | shop (or auto-triggered) | Finds nearest `riders.status='available'` via `current_location <-> shop.location`, sets `orders.rider_id`, flips rider to `on_delivery` |
| `rpc_rider_update_status(order_id, new_status)` | rider, only for orders where `rider_id` matches their own row | Same status-history write, scoped to assigned orders only |
| `rpc_generate_invoice(order_id)` | system, triggered on `orders.status → confirmed` | Creates the `invoices` row + PDF |

---

## 6. Design system <a name="6-design-system"></a>

Unchanged from v1 — nothing about the roles/cart/delivery/payment redesign touches visual identity. Restated briefly for completeness:

- **Primary/brand:** deep teal `#0F7A5C` (deliberately not red/orange/yellow, avoiding the Zomato/Swiggy/Blinkit color space).
- **Accent (marigold):** `#F2A73C` for badges/ratings, used sparingly, never as body text (fails AA at that lightness for text).
- **Urgent (terracotta):** `#E4572E` for low-stock/errors/destructive actions.
- **Neutrals:** warm cream `#FBF7F2` background, ink `#221B1A` text, soft ink `#7A7370` metadata, hairline `#E9E2D8`.
- **Display font:** Baloo 2 (rounded, warm, strong Indic-script sibling support for future regional-language UI).
- **Body/UI font:** Plus Jakarta Sans, `tabular-nums` on all price/quantity text.

Full contrast/rationale detail from the v1 pass stands unmodified.

---

## 7. Buyer app UX spec <a name="7-buyer-app-ux-spec"></a>

### 7.1 App shell, Home, Shop detail — unchanged in structure from v1

Four bottom tabs (Home, Categories, Cart, Order Again), top bar (address left, search+avatar right, no cart icon), Home section order (categories chip row → conditional Frequently Bought at ≥3 patterns → Recommended for you, 2-row horizontal scroll → Shops near you, 1/row with auto-scrolling photo carousel + distance), and the shop-detail vertical category rail with icon-on-select — none of this changed. What's new sits in the cart/checkout/tracking flow below.

### 7.2 New: live slot-countdown badge

Both the shop card (Home/Shop detail) and the checkout slot picker show a computed countdown to the next fulfillment-slot boundary, matching your worked example exactly: current time 9:20, next slot starts 10:00 → badge reads **"40 min."** Once inside the current slot's window, switch the label to "Now – closes in Xh Ym." Trivial to compute (`slot_start - now()`) once `orders`/the slot-generation endpoint expose real timestamps (§4.6) — no new backend work beyond what §4.6 already provides, purely a display component (`NextSlotBadge`).

### 7.3 Cart screen — multi-shop

Single scrollable list, **grouped into collapsible sections by shop** (shop logo + name as the section header, "Remove all from this shop" as a section-level action). Quantity-discount progress banners (Baker Ally's `quantity_promo_banner.dart`, ported as-is) render per item as before — they're already shop/variant-scoped so nothing changes there.

### 7.4 Checkout — per-shop fulfillment, one payment

1. **Per-shop fulfillment step:** for each shop group in the cart, in sequence: choose Pickup or Delivery (only the modes that shop's `supports_pickup`/`supports_delivery` allow), then pick a slot from `GET /v1/shops/:id/fulfillment-slots` (§4.6), grouped by day, disabled slots shown grayed with a reason rather than hidden.
2. **Address step:** one delivery address selection applies to every shop-group that chose delivery (a buyer isn't going to want three different delivery addresses in one checkout — if that's ever needed it's a Phase-2 edge case, not MVP).
3. **Payment mode step:** `Pay Online` always available; `Pay at Shop` only offered if every shop-group in this checkout is pickup or `delivery_mode='self'` — if a `platform_rider` group is present, the toggle is hidden entirely with a one-line explanation rather than shown-then-rejected.
4. **Review & pay:** one combined total, itemized per shop-group (subtotal + that group's delivery fee if any), one Razorpay/PayU sheet (or one "Confirm — pay at shop" tap) triggers `rpc_place_order` (§5.4).
5. **Confirmation screen:** one card per shop-group, each showing its own fulfillment type, slot, and (if applicable) delivery-fee line — never a single merged summary line, per your explicit instruction.

### 7.5 Order tracking

Same per-shop-card treatment as confirmation, now live via Supabase Realtime subscription on `order_status_history` filtered to this `order_group_id`'s child orders — each shop's card updates independently ("Shop A: out for delivery," "Shop B: ready for pickup") with no polling.

### 7.6 Profile overlay, Order Again tab — unchanged from v1

Structural port of `profile_overlay_sheet.dart` and the `group_tile`/`group_detail_sheet` pattern stands as designed; menu items unchanged.

---

## 8. Shopkeeper, rider & admin spec <a name="8-shopkeeper-rider-admin"></a>

### 8.1 Shopkeeper onboarding & delivery-mode choice

Signup → shop creation (name, geocoded address, GSTIN, FSSAI if food categories selected, business hours) → **delivery-mode selection** (`self`/`platform`/`both`, §1.3) → `status='pending'` → admin approval. If `platform` or `both` is chosen, no further shop-side setup is needed for delivery — Proximity's rider pool handles it automatically per order via `rpc_assign_rider`.

### 8.2 Catalog / inventory management — unchanged from v1

"Add things they like" = browse platform `categories`, create `shop_sub_categories`, add products/variants with the coarse `stock_status` toggle defaulting over precise counts.

### 8.3 Orders & team

Order list scoped to their own shop only (RLS, §5.2 — confirmed, nothing changed here despite the cart redesign). `owner` can invite `staff`/`delivery` team members (creates a `shop_team_members` row, invite via phone/email + OTP-style acceptance, same auth primitives already in place). `delivery`-role members see only the status-advance controls (§5.3), not catalog or settings.

### 8.4 Sales summary, invoices, ledger

Sales aggregation (`/v1/shop/analytics`) unchanged in concept from v1. **New:** a ledger view (`shop_ledger_entries` filtered to their shop) showing what the platform owes them (`payout_due`, from online-paid orders) versus what they owe the platform (`commission_due`, from `pay_at_shop` orders) — makes the settlement obligation visible even before automated payouts exist in Phase 2.

### 8.5 Rider touchpoint (new)

Lightweight in-app view in `proximity_app` for `role='rider'` users, same "don't build a whole second app for a narrow task" philosophy as the shopkeeper touchpoint: onboarding/KYC upload, an online/offline toggle (`riders.status`), incoming-assignment notification (push, via `rpc_assign_rider`), Accept, then a status ladder (`picked_up → out_for_delivery → delivered`) writing to `order_status_history` via `rpc_rider_update_status`, plus periodic `current_location` updates while `on_delivery` (feeding the buyer's live tracking — a text status in MVP, a live map pin is a §10 backlog item, not required for launch).

### 8.6 Admin panel

Shop approval queue, **rider approval queue** (new), global `categories` CRUD, `platform_settings` editor (delivery fee, slot window/granularity — your explicit "admin controls the delivery fee" instruction, §4.6), per-shop `platform_commission_pct` override, discount authoring, and a platform-wide ledger view across all shops (aggregate `payout_due`/`commission_due`).

---

## 9. What we're reusing from Baker Ally <a name="9-reuse-map"></a>

Unchanged from v1's traceability table for the pieces that didn't change (Drift two-layer cart mechanics, immutable order-item snapshot pattern, `product_cross_sell`, `pg_net` webhook-from-trigger pattern for organizer reminders, `group_tile`/`group_detail_sheet`, `profile_overlay_sheet.dart`, `app_shell.dart` structure, `checkout_repository.dart`'s typed-exception-from-error-code pattern — now extended with new error codes `rpc_place_order` needs, e.g. `PAY_AT_SHOP_NOT_ALLOWED` when a platform-rider group is present). The single-shop cart trigger specifically is **no longer reused** — v1 borrowed the *idea* of DB-level enforcement from Baker Ally's general RLS-everywhere discipline, but the specific mechanism doesn't apply to a multi-shop cart; that discipline now shows up instead as the `orders` CHECK constraints in §4.8 (delivery fee only with a platform rider) and the RPC validation in `rpc_place_order`.

**Revised again in Sprint 10, same "check it's actually there before claiming reuse" discipline Sprint 6 applied to "Drift two-layer cart mechanics" and Sprint 8 applied to `checkout_repository.dart`:** `group_tile`/`group_detail_sheet`/`profile_overlay_sheet.dart` **do not exist anywhere in Baker Ally's actual working tree either** — checked directly (grepped the whole reference project, case-insensitive, zero matches in code or planning docs beyond this project's own prior references to them), and `baker_ally_flutter/lib` itself is nearly empty (`main.dart` + `core/providers.dart` only). What IS real and recoverable: `Planning docs/Architecture/03_order_again_tab.md`, a complete prose spec for exactly this tab, apparently never implemented as code. Sprint 10's Order Again tab is a fresh design against that prose (same "recoverable spec, not recoverable code" situation `discounts`/`carts`/`product_cross_sell` hit in Sprints 6/7, except there the *code* was real too) — see `Sprint planning/Sprint 10.md` for the full account and the one real data-model decision this forced (what "a group" means in this project's own multi-shop `order_groups`/`orders` schema, since Baker Ally's single-shop-cart model predates that redesign entirely). `profile_overlay_sheet.dart`'s own port is still nobody's job yet (`account_screen.dart` remains the Sprint 2 placeholder) — flagging that it's the same "named in the reuse map, not actually there" situation, not assuming it'll be fine when some future sprint finally gets to it.

---

## 10. Feature backlog <a name="10-feature-backlog"></a>

Unchanged from v1 except **the rider network moves out of "explicitly deferred" and into MVP scope** (§4.7, §8.5) since you asked for both fulfillment paths from the start. Live GPS map-pin tracking (as opposed to text status updates) stays a Phase-2 refinement on top of the now-MVP rider infrastructure — the hard part (rider assignment, status ladder, Realtime plumbing) ships in Sprint 9; a live-moving map pin is a UI enhancement on data that already exists (`riders.current_location`), cheap to add once the core loop is proven. Everything else from v1 §9 (open-now badges, price-per-unit, notify-me-back-in-stock, voice search, favorite shops, map view of shops, ratings/reviews, referral program, slab delivery fees, dark mode) stands unchanged.

---

## 11. Sprint plan — full draft <a name="11-sprint-plan"></a>

2-week sprints except Sprint 0. **~29 weeks (≈7 months) to store submission** — longer than v1's ~25-week estimate specifically because riders, the multi-shop/single-charge cart, the pay-at-shop settlement path, and the formal RPC/access-control layer are real scope, not free additions. Flagging that plainly rather than pretending the timeline didn't move.

### Sprint 0 (1 week) — Prerequisites & scaffolding
- Toolchain: Flutter, Android cmdline-tools + JDK, Node 20, Supabase CLI, Deno.
- Git repo initialized (§3.4), branch protection on `main`.
- Two Supabase projects (`staging`/`prod`), PostGIS + `pg_cron` + `pg_net` enabled on both.
- Accounts: Google Cloud, Firebase, Apple Developer, Razorpay (test), PayU (sandbox), Maps/Geocoding.
- App identity confirmed (bundle ID, deep-link scheme).
- Repo scaffolding for all three deployables (`proximity_app`, `proximity_web`, `proximity_backend`), empty Edge Function deployed as a smoke test.

### Sprint 1 (2 weeks) — Identity, roles, geo core
- **Migrations already drafted and committed** (`migrations/000`–`004`): `postgis`/`pg_cron`/`pg_net` extensions, `users`, `addresses` (w/ PostGIS `location`), `categories` (seeded, 20-item list), `custom_access_token_hook` + `get_role()` helper.
- `shop_team_members` **moved to Sprint 2** — it references `shops(id)`, which doesn't exist until then; listing it here in the original draft was a sequencing bug, caught while actually writing the SQL rather than left for a migration-time failure.
- RLS baseline policies per §5.2 on every table created so far (drafted alongside each migration above, not a separate pass).
- Auth in `proximity_app`: Email OTP, Google Sign-In, **Apple Sign-In** (§1.1).
- First end-to-end RPC built to prove the SECURITY DEFINER + RLS pattern before it's relied on everywhere else — **`rpc_set_default_address`** (unset the buyer's current default, set the new one, atomically) is the right minimal case here, not `rpc_add_to_cart` as originally drafted: carts/variants don't exist until Sprint 3/6, but addresses do, and "exactly one default" is a real enough cross-row invariant to prove the pattern on.
- **Exit criteria:** a real user can sign up on both platforms, has a role, has an address with a resolved lat/lng.

### Sprint 2 (2 weeks) — Shop & rider onboarding, platform settings
- Migrations: `shops`, `shop_team_members` (moved here from Sprint 1, see above), `shop_business_hours`, `shop_media`, `shop_sub_categories`, `riders`, `platform_settings` (seeded with delivery fee + slot window + default commission), `shop_blackout_dates`.
- `proximity_web` scaffolded (Next.js 16/Tailwind/shadcn), shopkeeper signup → shop creation form (incl. `delivery_mode` choice) → `pending` status.
- Rider signup + KYC upload flow (mobile, minimal) → `is_verified=false`.
- Admin panel skeleton: shop approval queue, rider approval queue.
- **Exit criteria:** a shop and a rider can be created and admin-approved end to end.

### Sprint 3 (2 weeks) — Catalog & inventory
- Migrations: `products`, `product_variants` (unit fields, `stock_status`), `product_images`.
- Shopkeeper dashboard catalog CRUD (§8.2).
- **Exit criteria:** a shopkeeper can list a real product with variants and see it queryable via the buyer-facing read API.

### Sprint 4 (2 weeks) — Buyer Home
- Top bar, category chip row, Shops-near-you (PostGIS query + `NextSlotBadge`, §7.2), category-click filtering across sections.
- **Exit criteria:** Home renders real nearby shops sorted by distance, filterable by category, on a physical device.

### Sprint 5 (2 weeks) — Shop detail, PDP, wishlist
- Vertical category rail w/ icon-on-select, product detail + variant selection, `wishlists`.
- **Exit criteria:** full browse path from Home → shop → product → variant works.

### Sprint 6 (2 weeks) — Multi-shop cart
- Migrations: `carts`/`cart_items` (no shop lock, §1.5).
- Cart screen grouped by shop (§7.3), Recommended-for-you baseline (`product_cross_sell` + trending fallback).
- **Exit criteria:** a cart can hold items from two different shops simultaneously and displays them grouped correctly.

### Sprint 7 (2 weeks) — Checkout core (no payment gateway yet)
- Migrations: `order_groups`, `orders` (new shape, §4.8), `order_items`, `order_status_history`, `shop_ledger_entries`.
- `rpc_place_order` (§5.4) — per-shop fulfillment selection, unified slot generation endpoint (§4.6), delivery-fee CHECK constraint enforcement, discounts engine wired (banner still hidden per your original instruction, table live).
- Checkout UX (§7.4) steps 1–4, ending in a stubbed "payment" step (mocked success) so the rest of the flow can be tested before gateway integration lands.
- **Exit criteria:** a full multi-shop checkout produces one `order_groups` row and correct per-shop `orders` rows with the right fulfillment/slot/fee data, verified by hand against the CHECK constraints.

### Sprint 8 (2 weeks) — Payments
- `PaymentGateway` abstraction (§1.4) in both Edge Function and Flutter.
- Razorpay adapter (real integration, ported from Baker Ally's proven pattern), PayU adapter stub.
- `rpc_confirm_payment` webhook route, `order_groups.payment_status` cascade to child `orders`, `pay_at_shop` path (with the platform-rider exclusion check), `shop_ledger_entries` insertion on both paths.
- Invoice generation (`rpc_generate_invoice`) on order confirmation.
- **Exit criteria:** a real (test-mode) payment completes and correctly produces confirmed orders, ledger entries, and an invoice PDF.

### Sprint 9 (2 weeks) — Rider network live
- `rpc_assign_rider` (nearest-available), rider app touchpoint (§8.5) — accept, status ladder, location updates.
- Buyer-side order tracking (§7.5) via Supabase Realtime, per-shop-card live status.
- **Exit criteria:** a `platform`-mode shop's delivery order gets auto-assigned to a real test rider, and the buyer sees live status changes with no polling.

### Sprint 10 (2 weeks) — Order history & personalization
- Order history, Order Again tab (`group_tile`/`group_detail_sheet` port), Frequently-Bought engine + ≥3-groups Home gate.
- **Exit criteria:** a test account with ≥3 qualifying repeat-purchase patterns sees the Home section; an account with fewer does not.

### Sprint 11 (2 weeks) — Organizer
- `recurring_lists`/`recurring_list_items`, `pg_cron` reminder job (reminder + pre-filled-cart mode only, per your confirmed decision), FCM (Android) + APNs (iOS) push wiring.
- **Exit criteria:** a scheduled recurring list fires a real push notification that deep-links into a pre-filled cart at the right time.

### Sprint 12 (2 weeks) — Shopkeeper analytics, ledger, admin completion, cancellation & reversal
- Sales summary aggregation views, ledger view (§8.4), admin: `platform_settings` editor UI (delivery fee/slot window), commission override, discount authoring UI.
- **Added in Sprint 10, given a real scheduled line here rather than deferred a third time (§13's open decisions log has the full reasoning):** a real cancellation flow — buyer-initiated (before a shop accepts) and shop-initiated (before dispatch/handoff), a legal `orders.status` transition into `cancelled` from more than just `rpc_place_order`'s own pre-payment paths — plus everything Sprint 7/8/9 each found this depends on and left open: `shop_ledger_entries` reversal for both payment paths (a cancelled online order's `payout_due` row, a cancelled pay_at_shop order's `commission_due`/matching `payout_due` pair, migrations/036's own discount-absorption rows included), and rider decline/reassignment (§8.5 only ever built "Accept" — a rider who declines, or goes unreachable mid-delivery, currently leaves `orders.rider_id`/`riders.status='on_delivery'` stuck with no way back). This is real, non-trivial scope on top of this sprint's own named work, not a footnote — flagged explicitly here rather than silently expanding the sprint's time estimate without saying so.
- **Exit criteria:** a shopkeeper can see their own real revenue numbers and outstanding ledger balance; admin can change the platform delivery fee and see it reflected on the next new order; a cancelled order (buyer- or shop-initiated, at least one of each payment mode) leaves correct, reversed ledger entries and — if a rider was involved — a rider who's actually back to `available`, not stuck `on_delivery`.

### Sprint 13 (2 weeks) — Polish & hardening
- Design-system audit against §6, accessibility pass, empty/error states, Crashlytics + Sentry, image caching/list virtualization, `Platform.isAndroid`/`isIOS` centralization audit (§1.1's "keep it organised" checked against actual code, not just planned).
- **Exit criteria:** no untriaged crash-reporting gaps, no unhandled empty states on any list screen.

### Sprint 14 (2 weeks) — iOS build & store submission
- Xcode build/sign pipeline finalized (Mac or Codemagic, decided when this sprint starts per §1.1), TestFlight beta.
- Play Store listing + Data Safety form, Play Internal Testing.
- App Store listing, **Sign in with Apple compliance re-check**, privacy policy, staged rollout plan.
- **Exit criteria:** both stores have a submitted (or approved) build.

---

## 12. Requirements traceability <a name="12-traceability"></a>

Original 19-item brief, unchanged from v1 (§11 there), plus this session's additions:

| # | Requirement | Addressed in |
|---|---|---|
| 1 | iOS — stop treating as a constant risk, scope into one sprint, keep code organised | §1.1, Sprint 14 |
| 2 | Both delivery paths; no fee for shop-fulfilled; admin controls the fee; roles planned; RPC-organized access control | §1.2, §1.3, §4.4, §4.6, §5 entire section |
| 3 | Draft every sprint now | §11 |
| 4 | PayU vs Razorpay evaluation, pay-at-shop for shop-fulfilled orders | §1.4 |
| 5 | Multi-shop cart, one charge, correct per-shop delivery/status display, 6 AM–12 AM/2-hr slots with live countdown, shopkeeper dashboard stays shop-scoped | §1.5, §1.6, §4.8, §7.2–§7.5, §8.3 |
| 6 | Start writing sprints | §11 |

---

## 13. Open decisions log <a name="13-open-decisions"></a>

**Decided this session:**
- iOS handled on a Mac (own or cloud CI) when Sprint 14 arrives — not an ongoing risk to manage.
- Roles: `buyer`/`shop_owner`/`rider`/`admin` + shop-scoped `shop_team_members` (`owner`/`staff`/`delivery`).
- Both shop-self-delivery and platform riders, shop-selectable via `delivery_mode`.
- No delivery fee for self-fulfilled orders; fee is admin-controlled platform setting for rider-fulfilled ones.
- Cart is multi-shop; checkout produces one `order_groups` (one charge) + N `orders` (one per shop).
- Pickup and delivery share one slot mechanism, defaulting to 06:00–24:00/2-hour, admin-configurable.
- Pay-at-shop is a first-class MVP payment mode, excluded whenever a platform rider is involved.
- Payment gateway built behind a swappable abstraction; Razorpay implemented first, PayU stubbed, live quotes needed from both before Sprint 8.

**Decided in Sprint 9** (full reasoning in `Sprint planning/Sprint 9.md` and in each migration's own header):
- `rpc_shop_advance_order_status` (§5.4) — flagged by Sprint 8.md as having no scheduled sprint anywhere in this plan — is built THIS sprint, not deferred a second time: the rider status ladder cannot legally advance an order past `ready_for_pickup` without it, so the gap was load-bearing, not cosmetic.
- `rpc_assign_rider` fires **automatically**, chained off `rpc_confirm_payment`'s own cascade to `confirmed`, for every order with `delivery_fulfilled_by='platform_rider'` (§1.4 guarantees such an order is always `payment_mode='online'`, so "confirmed" and "needs a rider" are the same moment). A shop-triggered manual retry (owner/staff only) is the documented fallback for "no rider was available yet."
- The rider's own three-word status ladder (`picked_up`/`out_for_delivery`/`delivered`, §5.4/§8.5) is a genuinely different vocabulary from `orders.status`'s own CHECK-constrained enum (§4.8) — reconciled, not silently merged; see `migrations/042`'s header for the exact mapping and why `orders.status` itself was left untouched.
- §8.5's "incoming-assignment notification (push, via `rpc_assign_rider`)" is **not built as push** — checked directly (grepped the whole repo), this project has no FCM/APNs wiring at all yet (that's Sprint 11). The fallback is a Supabase Realtime subscription, the same primitive §7.5's buyer tracking uses — which surfaced a real, previously-undocumented architectural point now captured in §5.1 above: Realtime authorizes itself via RLS against the client's own session, a second trust boundary this project hadn't exercised before this sprint.
- §7.5's live tracking needed a way back into an in-flight order once the confirmation screen stopped being the only path to it — a minimal `GET /v1/order-groups` list + a "My Orders" mobile entry point were added THIS sprint (not Sprint 10's full "Order history / Order Again," which still owns reorder/filtering/pagination).

**Decided in Sprint 10** (full reasoning in `Sprint planning/Sprint 10.md` and in each new file's own header):
- **Rider decline/reassignment and cancellation-triggered ledger reversal** — flagged by Sprint 9.md as having no scheduled sprint for the third sprint running. Decided explicitly, not deferred a fourth time: **both get a real, named line in Sprint 12's own §11 entry** (above), alongside that sprint's already-planned ledger-view work, since a cancellation flow is the one missing piece both the ledger view and the rider ladder actually need to be honest about. Not built this sprint — Sprint 10's own scope (order history/personalization) doesn't touch order lifecycle at all — but explicitly scheduled rather than silently carried forward a fourth time.
- **Order History vs. Sprint 9's minimal "My Orders"** — decided to **extend `GET /v1/order-groups` and its one screen in place**, not build a second, parallel list surface. The underlying data (the buyer's own `order_groups`, most-recent-first) was always what a real Order History screen needs; what Sprint 9's stopgap was missing was status filtering and real (cursor) pagination, both added as optional query params so nothing that already called the unfiltered route broke. `MyOrdersScreen` was renamed to `OrderHistoryScreen` rather than kept alongside it.
- **What "a group" means for Order Again's "Frequently Bought Together" section** — Baker Ally's own single-shop-cart/single-order model (which this feature's prose spec, `03_order_again_tab.md`, was written against) predates this project's Sprint 6/7 multi-shop-cart/`order_groups` redesign entirely. Decided: a group is the item-set of one per-shop `orders` row (§4.8), never one `order_groups` row — `order_items` FKs to `orders`, not `order_groups`, and a group's own "Add All to Cart" action only makes sense scoped to one shop. Full reasoning in `lib/frequentlyBoughtGroups.ts`'s header.
- **What counts as "a qualifying repeat-purchase pattern"** for Home's own conditional section (§7.1 names the ">=3" threshold but never defines the unit) — decided: a distinct product ordered on >=2 of the buyer's own `orders` rows that reached at least `confirmed` (excludes unpaid-`pending` and `cancelled`). Home's section shows once the buyer has >=3 such products. A deliberately simpler, product-level definition than Order Again's own multi-item "group" concept above — the two features sound alike but answer different questions; `lib/repeatPurchases.ts`'s header has the full reasoning.
- **`group_tile`/`group_detail_sheet`/`profile_overlay_sheet.dart` don't exist in Baker Ally's actual working tree** — checked directly (§9, above, has the full finding). Order Again was built as a fresh design against `03_order_again_tab.md`'s prose spec instead of a code port.

**Decided in Sprint 11** (full reasoning in `Sprint planning/Sprint 11.md` and in each new file's own header):
- **The rider-assignment-notification path, named as Sprint 11's own forward-reference by Sprint 9.md's decision #2** — decided: real push now SUPPLEMENTS Sprint 9's Realtime subscription, it does not replace it. `lib/riderAssignment.ts`'s `assignRider()` now also calls `sendPushToUser` (best-effort, never throws) on every successful assignment, on both its callers (the automatic post-payment path and the shop's manual retry) — closing Sprint 9's own disclosed "no background/killed-app delivery" gap without removing the live, no-polling Realtime channel that's still the lower-latency path whenever a rider's app is already open. Full reasoning in `lib/riderAssignment.ts`'s own updated header.
- **`recurring_lists`/`recurring_list_items` schema** — a fresh design against §4.10's thin prose (no recoverable original anywhere, including Baker Ally — checked directly). `next_run_at` is a materialized, indexed column the cron job filters on directly and always advances from its OWN previous value (never from `now()`), so a late-running or backlogged cron tick can't drift a buyer's chosen reminder time later indefinitely. Full reasoning in `migrations/043`'s header.
- **IST wall-clock convention for the new `to_ist`/`ist_to_utc`/`ist_now` helpers** — hardcoded `+5:30` offset (same convention `lib/slots.ts` established in Sprint 4), deliberately NOT `AT TIME ZONE 'Asia/Kolkata'` (what `rpc_place_order` used in Sprint 7, flagged there as unconfirmed against a live Postgres tzdata install and still unconfirmed now). India has had no DST since 1945, so a fixed offset isn't an approximation that can drift wrong the way it would elsewhere.
- **"Pre-filled cart" is real, not a UI illusion** — the pg_cron job (`migrations/045`) upserts every item on a due list into the buyer's own actual `cart_items` via `rpc_add_to_cart`, before the push fires; by the time the notification is tapped, the cart already holds the items.
- **Manual `FirebaseOptions` init, not the FlutterFire CLI** — `push_service.dart` passes `.env`-sourced config straight to `Firebase.initializeApp(options: ...)`, with no `google-services.json`/`GoogleService-Info.plist` and no Gradle-plugin change. Decided specifically because `flutterfire configure` needs a live Firebase CLI login and a real project this session doesn't have, and a half-added Gradle plugin with no matching json file would break the next Android build for a reason unrelated to any actual Dart code.

**Decided in Sprint 12** (full reasoning in `Sprint planning/Sprint 12.md` and in each new file's own header):
- **Ledger reversal representation** — a new offsetting row (`payout_reversal`/`commission_reversal`, `migrations/046`), never a mutation of the original `payout_due`/`commission_due` row's amount or status. Same immutable-snapshot principle `order_items`/`invoices` already establish; the outstanding balance is always `SUM(due) - SUM(reversal)`, one formula (`lib/ledger.ts`) regardless of whether the original had already settled.
- **The cancellation state machine** — buyer-legal while `pending`/`confirmed` (before a shop's first real action, `preparing`); shop-legal (`owner`/`staff` only) through `ready_for_pickup`; both refused once `out_for_delivery`/`completed`/`cancelled`. Authorization is checked before any status check (a real ordering bug caught and fixed during this sprint's own second pass, matching `rpc_shop_advance_order_status`'s own precedent). Per-`orders` row, never per-`order_groups` — same "a group is one `orders` row" precedent Sprint 10's Order Again already set.
- **Rider decline/timeout/reassignment** — a decline (`rpc_rider_decline_order`) or a 5-minute timeout (`rpc_expire_stale_rider_assignments`, `pg_cron` every 2 minutes) both immediately retry `rpc_assign_rider` with an exclusion list (`order_rider_declines`), falling back to the shop's existing manual retry when nobody's found. The shop's manual retry itself gained a `force` flag to reassign an order that already has a rider, covering the one gap not auto-detected: a rider gone quiet after accepting but before pickup. **Explicitly NOT solved:** once `out_for_delivery` (the rider already has the package), no mechanism — decline, timeout, or forced reassignment — can help; that's a real-world logistics escalation with no schema-expressible fix, not an oversight.
- **Refunds on a cancelled, already-paid online order** — ledger-corrected (the `payout_due` is reversed) but **no real Razorpay refund is triggered**; still genuinely open below, since no real Razorpay account has ever existed to build that flow against (unchanged since Sprint 8).

**Decided in Sprint 13** (full reasoning in `Sprint planning/Sprint 13.md` and in each new file's own header):
- **§3.2's Sentry "Optional" line** — decided in for real, not left optional a further sprint: `proximity_backend`'s single existing `app.onError` handler now also reports to Sentry (`lib/sentry.ts`). Pinned to `npm:@sentry/deno@^8.55.2`, not npm's newer `latest` tag (`^10`), because Supabase's own current Edge-Functions Sentry guide pins `^8` specifically for their production Edge Runtime — Supabase, not this project, is the authority on what that runtime actually supports.
- **Crashlytics is not simply "blocked on credentials" the way every other integration in this project has been** — a real, disclosed asymmetry, not an oversight. Manual `FirebaseOptions` (the path that made FCM a complete integration without the FlutterFire CLI, Sprint 11) does not substitute for the native Gradle plugin Crashlytics genuinely needs on Android, which only `flutterfire configure` adds. The Dart-side wiring (`lib/core/crash/crash_reporting_service.dart`) is built and ready regardless — it starts sending Dart-level reports the moment real Firebase config lands — but full native crash symbolication needs `flutterfire configure` (or an equivalent native-build change) as a **second**, additional step once a real Firebase project exists, not a given the way it was for FCM.
- **Two real contrast gaps, measured precisely and flagged rather than fixed** — `AppColors.inkSoft` on `AppColors.cream` (4.36:1) and `AppColors.urgent` used as text on either cream or white (3.45–3.68:1) both fall short of WCAG AA's 4.5:1 normal-text minimum (the same colors used as icon/badge fills clear the separate, lower 3:1 non-text threshold comfortably). Not changed, deliberately: both are pinned §6 brand hex values shared verbatim by `proximity_web`'s `globals.css` — changing either is a brand-identity decision, not a "polish" one, and needs a real owner's decision (a recommended path — a separate, darker text-specific variant — is already in `Sprint 13.md`).
- **§6's "tabular-nums on all price/quantity text"** had never actually been wired anywhere (checked directly, zero matches for `FontFeature`/`tabularFigures` across ~40 price-rendering call sites) — fixed once, centrally, in `app_theme.dart`'s own `TextTheme` construction rather than at each of those ~40 call sites individually.

**Still genuinely open:**
- Final bundle ID (needed Sprint 1).
- Actual Razorpay/PayU commercial terms (needed before Sprint 8 starts, not before) — still no real Razorpay/PayU account exists as of Sprint 9 either (checked: `supabase projects list` shows no Proximity project, and no Razorpay keys exist), so Sprint 8's payment flow and this sprint's rider-assignment-off-a-real-confirmed-order dependency both remain unverified against live infrastructure.
- Default `platform_commission_pct` and any launch-promo waiver (needed by Sprint 2, shops will ask at signup).
- Whether `both`-mode shops choose delivery method manually per order or need the auto-escalation-after-N-minutes behavior mentioned in §1.3 — flagged as a Phase-2 refinement, manual choice is enough for Sprint 9.
- A radius cap on `rpc_assign_rider`'s nearest-rider search — none exists yet (finds the globally nearest available verified rider, however far); worth revisiting once a real deployment spans more than one service area.
- ~~Rider re-assignment / cancellation-triggered ledger reversal~~ — built in Sprint 12 (see "Decided in Sprint 12," above), not just scheduled: `rpc_cancel_order`/`rpc_rider_decline_order`/`rpc_expire_stale_rider_assignments` are real, code-complete RPCs, unverified only in the "never run against live Postgres" sense every RPC in this project shares.
- A real Razorpay refund on a cancelled, already-paid online order — Sprint 12's own ledger reversal corrects the internal bookkeeping (the platform no longer records owing the shop a payout) but never calls Razorpay to actually return the buyer's money. No sprint has this scheduled; needs a real Razorpay account to build against regardless (same still-open item above).
- **New from Sprint 13:** whether `AppColors.inkSoft`/`AppColors.urgent` get a dedicated, darker text-specific variant (or stay as-is) — a real design decision with exact contrast numbers and a recommended path already measured, not yet made.
- **New from Sprint 13:** a `flutterfire configure` run (or equivalent native-build change) once a real Firebase project exists — Crashlytics' own second precondition beyond the project simply existing, easy to forget is a separate step from what unblocked FCM.
