-- Sprint 2: shop_business_hours -- SPRINT_PLANNING.md §4.4 names this table
-- ("unchanged from v1") without repeating its DDL inline; the shape below
-- is the standard per-weekday open/close design implied throughout §1.6/§4.6
-- ("clipped by each shop's actual shop_business_hours" -- a shop closed at
-- 9pm simply doesn't offer the 10pm slot). One row per weekday per shop,
-- 0=Sunday..6=Saturday (Postgres's own EXTRACT(DOW) convention, so the
-- fulfillment-slot generator in §4.6 can join on it directly with no
-- reindexing). `opens_at`/`closes_at` are nullable specifically so
-- `is_closed = true` days don't need placeholder times.

CREATE TABLE IF NOT EXISTS shop_business_hours (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id     UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  weekday     SMALLINT NOT NULL CHECK (weekday BETWEEN 0 AND 6),
  opens_at    TIME,
  closes_at   TIME,
  is_closed   BOOLEAN NOT NULL DEFAULT false,
  UNIQUE (shop_id, weekday),
  CHECK (is_closed OR (opens_at IS NOT NULL AND closes_at IS NOT NULL AND closes_at > opens_at))
);

CREATE INDEX IF NOT EXISTS idx_shop_business_hours_shop_id ON shop_business_hours(shop_id);

ALTER TABLE shop_business_hours ENABLE ROW LEVEL SECURITY;

-- Public read only for approved shops -- buyer app needs this to compute
-- "open now" badges (§10 backlog) and fulfillment slots (§4.6) without
-- leaking a pending shop's hours.
CREATE POLICY shop_business_hours_select_public ON shop_business_hours
  FOR SELECT USING (
    shop_id IN (SELECT id FROM shops WHERE status = 'approved')
  );

CREATE POLICY shop_business_hours_select_team ON shop_business_hours
  FOR SELECT USING (
    shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid())
  );

-- Owner-only write (§5.3: "Edit shop settings, delivery mode, business
-- hours" is owner-only).
CREATE POLICY shop_business_hours_owner_write ON shop_business_hours
  FOR ALL USING (
    shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid() AND member_role = 'owner')
  )
  WITH CHECK (
    shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid() AND member_role = 'owner')
  );

CREATE POLICY shop_business_hours_admin_all ON shop_business_hours
  FOR ALL USING (public.get_role() = 'admin')
  WITH CHECK (public.get_role() = 'admin');
