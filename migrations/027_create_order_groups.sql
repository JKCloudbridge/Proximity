-- Sprint 7: order_groups -- literal DDL from SPRINT_PLANNING.md §4.8,
-- verbatim except for the one documented addition below. "One row per
-- checkout = one payment. This is what gets charged once." (§1.5's
-- multi-shop-cart/single-charge redesign, §4.8's own header.)
--
-- One addition beyond §4.8's literal block, flagged rather than silently
-- folded in (same discipline as migrations/011, 022, 026):
--   * `discount_id UUID REFERENCES discounts(id)` -- §4.8 records
--     `discount_value` (how much came off) but never *which* discount did
--     it. Without the FK there's no way to (a) show "PROX10 applied" back
--     to the buyer on the confirmation/history screens, (b) audit a code's
--     real redemption list against its own `uses_count`, or (c) let Sprint
--     8's ledger work reason about who funded a given discount. Nullable --
--     most checkouts have no code at all.
--
-- `payment_gateway`/`gateway_order_id`/`gateway_payment_id` stay NULL for
-- the whole of this sprint: §11 puts the real gateway in Sprint 8, and this
-- sprint's checkout ends at a stubbed/mocked payment step. The columns are
-- created now because §4.8 defines them now, not because anything here
-- writes them.

CREATE TABLE IF NOT EXISTS order_groups (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  payment_mode        TEXT NOT NULL CHECK (payment_mode IN ('online','pay_at_shop')),
  payment_gateway     TEXT CHECK (payment_gateway IN ('razorpay','payu')),   -- NULL when pay_at_shop
  gateway_order_id    TEXT,
  gateway_payment_id  TEXT UNIQUE,
  discount_id         UUID REFERENCES discounts(id),                         -- documented addition, see header
  subtotal            INTEGER NOT NULL,
  discount_value      INTEGER NOT NULL DEFAULT 0,
  delivery_fee_total  INTEGER NOT NULL DEFAULT 0,
  total               INTEGER NOT NULL,           -- the ONE amount charged to the customer
  payment_status      TEXT NOT NULL DEFAULT 'pending'
                         CHECK (payment_status IN ('pending','paid','failed','collected_at_shop')),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_order_groups_user_created ON order_groups(user_id, created_at DESC);

ALTER TABLE order_groups ENABLE ROW LEVEL SECURITY;

-- Own-user data (§5.2), same shape as addresses/carts/wishlists. A backstop
-- only (§5.1) -- routes/checkout.ts's authMiddleware plus explicit user_id
-- filtering is the live enforcement.
CREATE POLICY order_groups_all_own ON order_groups
  FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
