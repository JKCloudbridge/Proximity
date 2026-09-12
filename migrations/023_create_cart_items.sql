-- Sprint 6: cart_items -- literal DDL from SPRINT_PLANNING.md §1.5, verbatim
-- (no shop lock, no trigger -- deliberately simple, per that section's own
-- framing of the multi-shop-cart redesign: the shop grouping is a
-- presentation concern the Flutter cart screen handles client-side, not a
-- data-model constraint). UNIQUE(cart_id, variant_id) is what makes
-- rpc_add_to_cart's upsert (migrations/024) a single atomic statement
-- instead of a read-then-write race -- same role Baker Ally's own recovered
-- cart_items migration (015_create_cart_items.sql, read-only reference)
-- gives this exact constraint, for the exact same reason.

CREATE TABLE IF NOT EXISTS cart_items (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cart_id     UUID NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
  variant_id  UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
  quantity    INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
  added_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (cart_id, variant_id)
);

CREATE INDEX IF NOT EXISTS idx_cart_items_cart_id ON cart_items(cart_id);

ALTER TABLE cart_items ENABLE ROW LEVEL SECURITY;

-- cart_items has no user_id column of its own (by design, per the literal
-- DDL above) -- own-user data is scoped one hop through carts, same shape
-- §5.2 already describes for other join-scoped ownership checks.
CREATE POLICY cart_items_all_own ON cart_items
  FOR ALL USING (cart_id IN (SELECT id FROM carts WHERE user_id = auth.uid()))
  WITH CHECK (cart_id IN (SELECT id FROM carts WHERE user_id = auth.uid()));
