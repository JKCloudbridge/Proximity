-- Sprint 2: shop_team_members -- SPRINT_PLANNING.md §1.2, verbatim. Moved
-- here from its original Sprint 1 slot because it FKs to shops(id), which
-- didn't exist until this migration's predecessor (006) -- see Sprint 1.md
-- bug #2 for the original catch, and 006's tail comment for the other half
-- of this same ordering story (two of shops' RLS policies are created down
-- here instead, since they need this table to exist).
--
-- This is the fine-grained membership table: shop staff and shop-employed
-- delivery people are NOT a global users.role value (§1.2's reasoning --
-- "staff of *which* shop" is exactly what RLS needs answered on every
-- query). Every shop, including the creator's own, gets its owner row
-- inserted here atomically alongside the shop itself, via rpc_create_shop
-- (014) -- a shop with no owner-membership row would be locked out of its
-- own RLS-gated data (§4.4).

CREATE TABLE IF NOT EXISTS shop_team_members (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id      UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  member_role  TEXT NOT NULL CHECK (member_role IN ('owner','staff','delivery')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (shop_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_shop_team_members_user_id ON shop_team_members(user_id);
CREATE INDEX IF NOT EXISTS idx_shop_team_members_shop_id ON shop_team_members(shop_id);

ALTER TABLE shop_team_members ENABLE ROW LEVEL SECURITY;

-- A team member can see their shop's own team list (self-referential
-- subquery against the same table -- standard, if slightly unusual-looking,
-- pattern for "who else is on my team").
CREATE POLICY shop_team_members_select_own_shop ON shop_team_members
  FOR SELECT USING (
    shop_id IN (SELECT shop_id FROM shop_team_members m WHERE m.user_id = auth.uid())
  );

-- Only the owner manages the roster (§5.3: "Manage team members" is
-- owner-only). Deliberately no self-service INSERT for a brand-new shop's
-- first owner row -- that one is written by rpc_create_shop under
-- SECURITY DEFINER, not through PostgREST/RLS at all, so it doesn't need a
-- policy that would otherwise have to allow "insert a row for yourself with
-- no existing owner row to check against."
CREATE POLICY shop_team_members_owner_manage ON shop_team_members
  FOR ALL USING (
    shop_id IN (SELECT shop_id FROM shop_team_members m WHERE m.user_id = auth.uid() AND m.member_role = 'owner')
  )
  WITH CHECK (
    shop_id IN (SELECT shop_id FROM shop_team_members m WHERE m.user_id = auth.uid() AND m.member_role = 'owner')
  );

CREATE POLICY shop_team_members_admin_all ON shop_team_members
  FOR ALL USING (public.get_role() = 'admin')
  WITH CHECK (public.get_role() = 'admin');

-- The two shops policies deferred from 006 -- see that file's tail comment.
CREATE POLICY shops_select_team ON shops
  FOR SELECT USING (id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid()));

-- Owner can edit their own shop's settings (§5.3), but NOT `status` or
-- `platform_commission_pct` -- those are admin-only levers (shop approval,
-- commission overrides). WITH CHECK pins both columns to their current
-- value, same "exclude this column from self-service edits" pattern as
-- users_update_own (001) pinning `role`.
CREATE POLICY shops_owner_update ON shops
  FOR UPDATE USING (
    id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid() AND member_role = 'owner')
  )
  WITH CHECK (
    id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid() AND member_role = 'owner')
    AND status = (SELECT status FROM shops s2 WHERE s2.id = shops.id)
    AND platform_commission_pct = (SELECT platform_commission_pct FROM shops s2 WHERE s2.id = shops.id)
  );
