-- Sprint 2: shop_media -- SPRINT_PLANNING.md §4.4 names this table
-- ("unchanged from v1") without repeating its DDL inline. Backs the
-- auto-scrolling photo carousel on the buyer Home "Shops near you" cards
-- (§7.1) -- an ordered list of photo/video URLs per shop, separate from the
-- single `logo_url`/`cover_image_url` columns already on `shops` (006).
-- Routes/UI for managing this land alongside catalog media work (Sprint 3)
-- -- this sprint only needs the table to exist so `shops` isn't blocked on
-- a later migration for something conceptually part of shop setup.

CREATE TABLE IF NOT EXISTS shop_media (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id     UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  media_url   TEXT NOT NULL,
  media_type  TEXT NOT NULL DEFAULT 'photo' CHECK (media_type IN ('photo','video')),
  sort_order  INTEGER NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_shop_media_shop_id ON shop_media(shop_id);

ALTER TABLE shop_media ENABLE ROW LEVEL SECURITY;

CREATE POLICY shop_media_select_public ON shop_media
  FOR SELECT USING (
    shop_id IN (SELECT id FROM shops WHERE status = 'approved')
  );

CREATE POLICY shop_media_select_team ON shop_media
  FOR SELECT USING (
    shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid())
  );

-- Owner + staff can manage media (§5.3's catalog row -- "Add/edit catalog"
-- is owner+staff; shop photos are treated the same, not owner-only, since
-- they're closer to "keeping the storefront current" than a settings
-- change).
CREATE POLICY shop_media_team_write ON shop_media
  FOR ALL USING (
    shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid() AND member_role IN ('owner','staff'))
  )
  WITH CHECK (
    shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid() AND member_role IN ('owner','staff'))
  );

CREATE POLICY shop_media_admin_all ON shop_media
  FOR ALL USING (public.get_role() = 'admin')
  WITH CHECK (public.get_role() = 'admin');
