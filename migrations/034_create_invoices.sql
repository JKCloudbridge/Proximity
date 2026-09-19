-- Sprint 8: invoices -- SPRINT_PLANNING.md §4.10 says this table "stays keyed
-- to orders.id (the per-shop sub-order, not order_groups) because each shop
-- needs its own GST invoice under its own GSTIN," and §5.4 names
-- `rpc_generate_invoice(order_id)`. Same as the standing rule §4.10's own
-- prose has followed for wishlists/discounts before it, no literal DDL is
-- given anywhere in §4 -- and unlike carts/product_cross_sell/discounts
-- (Sprint 6/7's own "fresh design against prose, but recoverable from Baker
-- Ally" situations), **this one really is a fresh design with no original to
-- recover**: Baker Ally's own working tree has no invoices migration either
-- (checked directly -- `grep -ri invoice` over its migrations/ turns up
-- nothing; RAZORPAY_INTEGRATION.md and friends describe an invoice concept
-- in prose only). Flagging that plainly rather than implying this was
-- ported from somewhere real, per this sprint's own instructions.
--
-- Design decisions made here, each because §4.10 doesn't specify them:
--   * `shop_id` is denormalized alongside `order_id` (derivable via
--     orders.shop_id, but stored directly anyway) -- same shape
--     shop_ledger_entries (031) already chose, for the same reason: every
--     shop-team RLS policy in this project reads `shop_id IN (SELECT ...)`
--     directly off the table being scoped, not through a join.
--   * `shop_name`/`shop_gstin` are snapshotted at generation time, not
--     joined live from `shops` -- same §9 immutable-snapshot principle
--     order_items (029) already applies to product name/price. A shop
--     renaming itself or updating its GSTIN after an invoice already exists
--     must not silently rewrite a document that's supposed to be a fixed
--     legal record of what was true at sale time.
--   * `pdf_path` is the object path inside the private `invoices` bucket
--     (035) -- NOT a public URL. See that migration's header for why this
--     bucket, unlike product-images/rider-documents, has no direct
--     client-facing Storage RLS read policy at all: every read goes through
--     an authenticated Edge Function route (routes/invoices.ts) that decides
--     ownership itself and hands back a short-lived signed URL, the same
--     "the Edge Function is the trust boundary" reasoning §5.1 states for
--     everything else in this backend.
--   * `invoice_number` is unique per shop (`UNIQUE(shop_id, invoice_number)`),
--     not globally unique -- see migrations/033's header for why it's a
--     per-shop counter, not a global sequence.
--   * No tax breakup (CGST/SGST/IGST), no HSN code, no `discounts`
--     line-item-level detail. **A real, disclosed limitation, not an
--     oversight:** `products`/`product_variants` (Sprint 3) carry no HSN code
--     or GST-rate column anywhere in this project's schema, so a
--     line-item-level tax breakup has nothing to compute it from. This
--     invoice records amounts (subtotal/discount/delivery fee/total) and the
--     seller's own GSTIN -- the minimum §4.10 actually asks for -- not a
--     professionally-reviewed GST-compliant document. Flagged here rather
--     than implied to be more complete than it is; see Sprint 8.md.

CREATE TABLE IF NOT EXISTS invoices (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id        UUID NOT NULL UNIQUE REFERENCES orders(id),
  shop_id         UUID NOT NULL REFERENCES shops(id),
  invoice_number  TEXT NOT NULL,
  shop_name       TEXT NOT NULL,
  shop_gstin      TEXT,
  subtotal        INTEGER NOT NULL,
  discount_value  INTEGER NOT NULL DEFAULT 0,
  delivery_fee    INTEGER NOT NULL DEFAULT 0,
  total           INTEGER NOT NULL,
  pdf_path        TEXT NOT NULL,
  generated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (shop_id, invoice_number)
);

CREATE INDEX IF NOT EXISTS idx_invoices_shop_generated ON invoices(shop_id, generated_at DESC);

ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;

-- Backstops only (§5.1) -- routes/invoices.ts's own ownership check (buyer
-- via orders.user_id, shop team via shop_id, admin via get_role()) is the
-- live enforcement, same split every other RPC-written table in this project
-- already uses.
DROP POLICY IF EXISTS invoices_select_buyer ON invoices;
CREATE POLICY invoices_select_buyer ON invoices
  FOR SELECT USING (order_id IN (SELECT id FROM orders WHERE user_id = auth.uid()));

-- §5.3's "View sales summary / invoices" row: owner + staff, never delivery.
DROP POLICY IF EXISTS invoices_select_shop_team ON invoices;
CREATE POLICY invoices_select_shop_team ON invoices
  FOR SELECT USING (
    shop_id IN (
      SELECT shop_id FROM shop_team_members
      WHERE user_id = auth.uid() AND member_role IN ('owner', 'staff')
    )
  );

DROP POLICY IF EXISTS invoices_admin_all ON invoices;
CREATE POLICY invoices_admin_all ON invoices
  FOR ALL USING (public.get_role() = 'admin')
  WITH CHECK (public.get_role() = 'admin');
