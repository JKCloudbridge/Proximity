-- Sprint 3: product_variants -- SPRINT_PLANNING.md §4.5: "unit_value/
-- unit_label split for price-per-unit math, stock_status coarse toggle
-- alongside precise stock_qty." Every product has ≥1 variant (a "500g" or
-- "1kg" pack, a "1 pc"/"1 dozen" unit) -- price lives here, never on
-- `products`, since two variants of the same product routinely have
-- different prices.
--
-- unit_value/unit_label split (rather than one free-text "500g" string) is
-- what makes price-per-unit comparison possible later (₹/kg across two
-- shops' different pack sizes) without parsing a string -- §7's buyer spec
-- assumes this kind of comparison is a backlog item (§10's "price-per-unit"
-- entry), so the split needs to exist from the start even though nothing
-- reads it that way yet.
--
-- stock_status + stock_qty, both present, is the direct mitigation
-- SPRINT_PLANNING.md §1.7 calls out by name: "Stock-count accuracy from
-- small kirana shops is still a real trust risk; the stock_status coarse
-- toggle mitigation stands." stock_status is the field the buyer app
-- actually renders (in stock / low stock / out of stock) and the one a
-- shopkeeper is expected to keep honest with one tap; stock_qty is an
-- optional, more precise count for shops that want to track it, never
-- required to be accurate, and never itself gates buyability -- only
-- stock_status does. The two are deliberately not wired to auto-derive one
-- from the other in this sprint (a shop that doesn't bother with stock_qty
-- shouldn't have it silently overwrite their manual stock_status toggle);
-- revisit if a later sprint wants real inventory automation.
--
-- price/mrp are paise integers, same convention as orders.total et al.
-- (SPRINT_PLANNING.md §1.7). mrp is optional -- only set when a shop wants
-- to show a strike-through "was ₹X" price, and is CHECKed >= price so the
-- strike-through can never read as a fake discount.

CREATE TABLE IF NOT EXISTS product_variants (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id    UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  unit_value    NUMERIC(10, 2) NOT NULL CHECK (unit_value > 0),
  unit_label    TEXT NOT NULL,
  sku           TEXT,
  price         INTEGER NOT NULL CHECK (price > 0),
  mrp           INTEGER CHECK (mrp IS NULL OR mrp >= price),
  stock_qty     INTEGER NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),
  stock_status  TEXT NOT NULL DEFAULT 'in_stock' CHECK (stock_status IN ('in_stock', 'low_stock', 'out_of_stock')),
  is_active     BOOLEAN NOT NULL DEFAULT true,
  sort_order    INTEGER NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (product_id, unit_value, unit_label)
);

CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON product_variants(product_id);

ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;

-- Same three-condition shape as products_select_public (017) plus the
-- variant's own is_active -- a product can stay listed with one inactive
-- (discontinued) variant among several active ones.
CREATE POLICY product_variants_select_public ON product_variants
  FOR SELECT USING (
    is_active = true
    AND product_id IN (
      SELECT id FROM products
      WHERE is_active = true AND shop_id IN (SELECT id FROM shops WHERE status = 'approved')
    )
  );

CREATE POLICY product_variants_select_team ON product_variants
  FOR SELECT USING (
    product_id IN (
      SELECT id FROM products WHERE shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid())
    )
  );

CREATE POLICY product_variants_team_write ON product_variants
  FOR ALL USING (
    product_id IN (
      SELECT id FROM products
      WHERE shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid() AND member_role IN ('owner', 'staff'))
    )
  )
  WITH CHECK (
    product_id IN (
      SELECT id FROM products
      WHERE shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid() AND member_role IN ('owner', 'staff'))
    )
  );

CREATE POLICY product_variants_admin_all ON product_variants
  FOR ALL USING (public.get_role() = 'admin')
  WITH CHECK (public.get_role() = 'admin');
