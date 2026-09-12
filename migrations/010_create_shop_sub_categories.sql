-- Sprint 2: shop_sub_categories -- SPRINT_PLANNING.md §4.3: "per-shop
-- shop_sub_categories, plus the icon_url field powering the shop-detail
-- rail interaction." Each row is a shop's own subdivision within one of the
-- 20 global `categories` (003) -- e.g. a shop opts into "Dairy, Bread &
-- Eggs" and then defines its own rail entries under it ("Milk", "Bread",
-- "Eggs"). This is the shop-owned half of the two-level taxonomy described
-- in §4.3; `categories` itself stays admin-curated and global.
-- Routes/UI for authoring these land alongside catalog CRUD (Sprint 3, per
-- §8.2 "browse platform categories, create shop_sub_categories") -- this
-- sprint only creates the table, same reasoning as shop_media (009).

CREATE TABLE IF NOT EXISTS shop_sub_categories (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id      UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  category_id  UUID NOT NULL REFERENCES categories(id),
  name         TEXT NOT NULL,
  icon_url     TEXT,
  sort_order   INTEGER NOT NULL DEFAULT 0,
  is_active    BOOLEAN NOT NULL DEFAULT true,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (shop_id, category_id, name)
);

CREATE INDEX IF NOT EXISTS idx_shop_sub_categories_shop_id ON shop_sub_categories(shop_id);
CREATE INDEX IF NOT EXISTS idx_shop_sub_categories_category_id ON shop_sub_categories(category_id);

ALTER TABLE shop_sub_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY shop_sub_categories_select_public ON shop_sub_categories
  FOR SELECT USING (
    is_active = true AND shop_id IN (SELECT id FROM shops WHERE status = 'approved')
  );

CREATE POLICY shop_sub_categories_select_team ON shop_sub_categories
  FOR SELECT USING (
    shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid())
  );

-- Owner + staff manage the catalog taxonomy (§5.3's "Add/edit catalog" row).
CREATE POLICY shop_sub_categories_team_write ON shop_sub_categories
  FOR ALL USING (
    shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid() AND member_role IN ('owner','staff'))
  )
  WITH CHECK (
    shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid() AND member_role IN ('owner','staff'))
  );

CREATE POLICY shop_sub_categories_admin_all ON shop_sub_categories
  FOR ALL USING (public.get_role() = 'admin')
  WITH CHECK (public.get_role() = 'admin');
