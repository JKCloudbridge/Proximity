-- Sprint 7: order_items -- literal DDL from SPRINT_PLANNING.md §4.8,
-- verbatim, no additions.
--
-- Note the deliberate denormalization §4.8 builds in and §9's reuse map
-- names explicitly ("immutable order-item snapshot pattern," carried over
-- from Baker Ally): `product_name`, `variant_name` and `unit_price` are
-- COPIED onto the row at order time rather than joined live from
-- products/product_variants. A shop renaming a product, repricing a
-- variant, or deleting either outright must never retroactively rewrite
-- what a buyer actually ordered and was charged -- which is also why
-- `variant_id` here is a plain REFERENCES with no ON DELETE CASCADE
-- (unlike cart_items, migrations/023, where cascading away is exactly
-- right): deleting a variant that has already been ordered should fail
-- loudly, not silently erase order history.
--
-- That FK is the one thing routes/catalog.ts's DELETE-variant route hasn't
-- had to reckon with until now -- its own comment says "No orders reference
-- product_variants yet (Sprint 6+), so there's no 'can't delete, it's been
-- sold' invariant to worry about this sprint; revisit once order_items
-- exists." This is that sprint. See Sprint 7.md's "Bugs caught" for what
-- that revisit actually found.

CREATE TABLE IF NOT EXISTS order_items (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id      UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  variant_id    UUID NOT NULL REFERENCES product_variants(id),
  product_name  TEXT NOT NULL,
  variant_name  TEXT NOT NULL,
  quantity      INTEGER NOT NULL,
  unit_price    INTEGER NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);

ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

-- Scoped one hop through orders, same shape cart_items (023) uses through
-- carts -- order_items has no user_id/shop_id of its own (by design, per
-- §4.8's literal DDL above).
DROP POLICY IF EXISTS order_items_select_own ON order_items;
CREATE POLICY order_items_select_own ON order_items
  FOR SELECT USING (order_id IN (SELECT id FROM orders WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS order_items_select_shop_team ON order_items;
CREATE POLICY order_items_select_shop_team ON order_items
  FOR SELECT USING (
    order_id IN (
      SELECT o.id FROM orders o
      WHERE o.shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS order_items_admin_all ON order_items;
CREATE POLICY order_items_admin_all ON order_items
  FOR ALL USING (public.get_role() = 'admin')
  WITH CHECK (public.get_role() = 'admin');
