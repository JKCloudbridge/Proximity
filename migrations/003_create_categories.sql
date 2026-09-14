-- Sprint 1: categories table -- the global, curated top level of the
-- catalog taxonomy (SPRINT_PLANNING.md §4.3). Shop-owned sub-categories
-- reference this table but aren't created until Sprint 2 (they need
-- `shops` to exist first).
--
-- Admin-owned, not shopkeeper-editable -- keeps cross-shop category
-- filtering (buyer taps "Beauty" -> every shop's Beauty items) consistent
-- instead of each shop inventing its own top-level taxonomy.
--
-- LATENT ORDERING BUG, caught applying this to a fresh project in strict
-- numeric order (never surfaced before because every prior apply happened
-- out of order by accident): the policy below calls public.get_role(),
-- which isn't defined until 004_create_custom_jwt_claims_hook.sql. Run 004
-- BEFORE this file on any fresh project. Not fixed by renumbering -- by the
-- time this was caught, 003/004's numbers were already load-bearing across
-- 40+ later migrations and a dozen merged Sprint N.md docs; the one-line
-- reorder-at-apply-time workaround is far lower-risk than a renumber.

CREATE TABLE IF NOT EXISTS categories (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL UNIQUE,
  icon        TEXT,              -- emoji or icon-font key for the home chip row
  image_url   TEXT,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE categories ENABLE ROW LEVEL SECURITY;

-- Public read (anyone browsing, logged in or not); writes are admin-only,
-- enforced via the get_role() helper defined in 004 alongside the JWT hook.
DROP POLICY IF EXISTS categories_select_all ON categories;
CREATE POLICY categories_select_all ON categories
  FOR SELECT USING (is_active = true);

DROP POLICY IF EXISTS categories_admin_write ON categories;
CREATE POLICY categories_admin_write ON categories
  FOR ALL USING (public.get_role() = 'admin')
  WITH CHECK (public.get_role() = 'admin');

-- Seed list -- SPRINT_PLANNING.md §4.3, built from "what a local shop
-- actually stocks," not a generic e-commerce taxonomy. Shops opt into
-- whichever subset applies to them via shop_sub_categories (Sprint 2).
INSERT INTO categories (name, icon, sort_order) VALUES
  ('Groceries & Staples',              '🌾', 1),
  ('Fruits & Vegetables',               '🥦', 2),
  ('Dairy, Bread & Eggs',               '🥛', 3),
  ('Snacks & Beverages',                '🥤', 4),
  ('Bakery & Cakes',                    '🍰', 5),
  ('Meat, Fish & Poultry',              '🍗', 6),
  ('Frozen Foods',                      '🧊', 7),
  ('Beauty & Cosmetics',                '💄', 8),
  ('Personal Care',                     '🧴', 9),
  ('Household Essentials',              '🧹', 10),
  ('Baby Care',                         '🍼', 11),
  ('Health & Wellness',                 '💊', 12),
  ('Stationery & Office',               '✏️', 13),
  ('Electronics & Mobile Accessories',  '🔌', 14),
  ('Hardware & Tools',                  '🔧', 15),
  ('Home, Kitchen & Décor',             '🏺', 16),
  ('Toys, Games & Gifts',               '🎁', 17),
  ('Pet Supplies',                      '🐾', 18),
  ('Gardening & Plants',                '🌱', 19),
  ('Festive & Seasonal',                '🎉', 20)
ON CONFLICT (name) DO NOTHING;
