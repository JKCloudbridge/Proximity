-- Sprint 2: shop_blackout_dates -- SPRINT_PLANNING.md §4.6, verbatim. Feeds
-- the fulfillment-slot generator (§4.6's GET .../fulfillment-slots) once
-- that endpoint exists (Sprint 7, alongside checkout) -- a shop marks a
-- date closed (festival, personal leave) without touching its recurring
-- weekly `shop_business_hours`. No management route/UI this sprint (same
-- "table exists, feature lands with the sprint that consumes it" reasoning
-- as shop_media/shop_sub_categories) -- flagged in Sprint 2.md.

CREATE TABLE IF NOT EXISTS shop_blackout_dates (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id   UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  date      DATE NOT NULL,
  reason    TEXT,
  UNIQUE (shop_id, date)
);

CREATE INDEX IF NOT EXISTS idx_shop_blackout_dates_shop_id ON shop_blackout_dates(shop_id);

ALTER TABLE shop_blackout_dates ENABLE ROW LEVEL SECURITY;

CREATE POLICY shop_blackout_dates_select_public ON shop_blackout_dates
  FOR SELECT USING (
    shop_id IN (SELECT id FROM shops WHERE status = 'approved')
  );

CREATE POLICY shop_blackout_dates_select_team ON shop_blackout_dates
  FOR SELECT USING (
    shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid())
  );

-- Owner-only write, same rationale as shop_business_hours (008) -- both are
-- "when are we open" settings, §5.3's owner-only row.
CREATE POLICY shop_blackout_dates_owner_write ON shop_blackout_dates
  FOR ALL USING (
    shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid() AND member_role = 'owner')
  )
  WITH CHECK (
    shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid() AND member_role = 'owner')
  );

CREATE POLICY shop_blackout_dates_admin_all ON shop_blackout_dates
  FOR ALL USING (public.get_role() = 'admin')
  WITH CHECK (public.get_role() = 'admin');
