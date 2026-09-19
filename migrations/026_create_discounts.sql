-- Sprint 7: discounts -- SPRINT_PLANNING.md names this table twice (§5.2's
-- admin-only RLS ownership class, and §11's Sprint 7 line "discounts engine
-- wired ... table live") but never gives its DDL anywhere in §4. Same
-- "fresh design against prose" situation Sprint 3's products, Sprint 5's
-- wishlists, and Sprint 6's carts/product_cross_sell all hit -- and, same as
-- Sprint 6's two, the actual v1 original turned out to be recoverable from
-- the read-only Baker Ally reference project rather than genuinely lost:
-- `C:\Users\hemin\Desktop\Android Project\migrations\016_create_discounts.sql`.
-- Reused directly rather than re-derived from prose alone.
--
-- Deliberate differences from that original, flagged rather than silently
-- folded in (same discipline as migrations/011's kyc_document_url and
-- migrations/022's carts.updated_at):
--   * `created_by` added -- discounts are admin-authored (§8.6), and the
--     admin ledger/audit story is real enough in this project (§4.9) that
--     "who created this code" is worth keeping. Nullable: the seed row
--     below has no author.
--   * `scope_shop_id` deliberately NOT added. Every discount here is
--     platform-wide, because §8.6 only ever describes admin-authored
--     discount authoring -- there is no shop-authored-discount concept
--     anywhere in the plan. See the "who funds the discount" note in
--     migrations/032_rpc_place_order.sql, which is the real open question
--     this raises, and which Sprint 8 (the sprint that actually writes
--     shop_ledger_entries rows) has to answer.
--   * `quantity` type and the `threshold_qty`/`message_template` columns
--     from Baker Ally's later 026_AP migration are NOT carried over. Those
--     exist purely to drive the quantity-discount *progress banner*, and
--     §11's Sprint 7 line says that banner explicitly "stays hidden" this
--     sprint. `product_discounts` (Baker Ally's 017) is deferred with it --
--     nothing this sprint reads or writes it.
--
-- value semantics depend on type (unchanged from the v1 original):
--   percent        -> whole percent off the cart subtotal (10 = 10% off)
--   flat           -> paise off the cart subtotal (5000 = Rs.50 off)
--   free_shipping  -> `value` ignored; zeroes every platform-rider delivery
--                     fee in the checkout (§1.3: no other fulfillment path
--                     charges one in the first place)

CREATE TABLE IF NOT EXISTS discounts (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code             TEXT UNIQUE,
  name             TEXT NOT NULL,
  type             TEXT NOT NULL CHECK (type IN ('percent', 'flat', 'free_shipping')),
  value            INTEGER NOT NULL DEFAULT 0,
  min_order_value  INTEGER NOT NULL DEFAULT 0,
  max_uses         INTEGER,
  uses_count       INTEGER NOT NULL DEFAULT 0,
  is_active        BOOLEAN NOT NULL DEFAULT true,
  starts_at        TIMESTAMPTZ,
  expires_at       TIMESTAMPTZ,
  created_by       UUID REFERENCES users(id),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_discounts_code_active ON discounts(code) WHERE is_active = true;

ALTER TABLE discounts ENABLE ROW LEVEL SECURITY;

-- §5.2's admin-only ownership class, same get_role() helper (004) every
-- other admin-governed table uses. Buyers never read this table directly --
-- code validation goes through the Edge Function (GET /v1/discounts/:code,
-- routes/checkout.ts), which is the trust boundary (§5.1), so there's
-- deliberately no permissive buyer SELECT policy here: a buyer being able
-- to enumerate every unreleased promo code is exactly the kind of thing
-- this backstop should keep closed even on a path that doesn't currently
-- exist.
DROP POLICY IF EXISTS discounts_admin_all ON discounts;
CREATE POLICY discounts_admin_all ON discounts
  FOR ALL USING (public.get_role() = 'admin')
  WITH CHECK (public.get_role() = 'admin');

-- One seeded code so the checkout discount path is demoable end to end
-- before Sprint 12's admin discount-authoring UI exists -- same reason
-- Baker Ally's own 021_seed_discount_bake10.sql existed at this stage.
-- PROX10 = 10% off, no minimum, no expiry, unlimited uses.
INSERT INTO discounts (code, name, type, value, min_order_value, is_active)
VALUES ('PROX10', 'Proximity 10% Off', 'percent', 10, 0, true)
ON CONFLICT (code) DO NOTHING;
