-- Sprint 2: riders -- SPRINT_PLANNING.md §4.7, with one real addition on
-- top of the SQL given there: `kyc_document_url`. §4.7's own prose says
-- onboarding is "signup -> KYC documents to the private rider-documents
-- bucket -> is_verified=false -> admin approval," and §3.6 names the bucket
-- -- but the literal CREATE TABLE block in §4.7 has no column to hold that
-- document's reference. Caught while wiring the actual signup route (same
-- kind of gap as Sprint 1's shop_team_members sequencing bug): without this
-- column an admin approving a rider would have no document to check against
-- at all. Kept deliberately minimal (one URL, not a documents table) per
-- this sprint's explicit "(mobile, minimal)" scope -- a richer
-- multi-document model (separate ID proof / driving license / vehicle RC)
-- is a straightforward follow-up migration if KYC review later needs it,
-- not a redesign.
--
-- Upload itself goes Flutter -> Supabase Storage directly (not proxied
-- through the Edge Function), same precedent as Baker Ally's avatar upload
-- (baker_ally_flutter/lib/features/profile/data/user_repository.dart) --
-- Storage has its own auth surface backed by the real user JWT (unlike the
-- backend's own DB connection, which is the service-role pooler connection
-- with no populated auth.uid(), see lib/db.ts), so it's a legitimately
-- different, already-authenticated path, not a second weaker copy of the
-- §5.1 trust boundary. Only the resulting URL crosses into `riders` via the
-- Edge Function's rpc_create_rider_profile (015).

CREATE TABLE IF NOT EXISTS riders (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  full_name          TEXT NOT NULL,
  phone              TEXT NOT NULL,
  vehicle_type       TEXT CHECK (vehicle_type IN ('bike','scooter','bicycle','on_foot')),
  vehicle_number     TEXT,
  kyc_document_url   TEXT,
  status             TEXT NOT NULL DEFAULT 'offline' CHECK (status IN ('offline','available','on_delivery')),
  current_location   GEOGRAPHY(Point, 4326),
  is_verified        BOOLEAN NOT NULL DEFAULT false,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_riders_location ON riders USING GIST(current_location);
CREATE INDEX IF NOT EXISTS idx_riders_is_verified ON riders(is_verified);

ALTER TABLE riders ENABLE ROW LEVEL SECURITY;

-- Own-row read/update -- same "own-user data" shape as addresses (002),
-- narrowed to the fields a rider should actually self-service (status,
-- location pings once approved). `is_verified` is deliberately excluded
-- from the self-update WITH CHECK, same "pin the admin-only column" pattern
-- as users_update_own (001) and shops_owner_update (007) -- a rider can't
-- verify themselves any more than a shopkeeper can approve their own shop.
DROP POLICY IF EXISTS riders_select_own ON riders;
CREATE POLICY riders_select_own ON riders
  FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS riders_update_own ON riders;
CREATE POLICY riders_update_own ON riders
  FOR UPDATE USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid() AND is_verified = (SELECT is_verified FROM riders r2 WHERE r2.id = riders.id));

DROP POLICY IF EXISTS riders_admin_all ON riders;
CREATE POLICY riders_admin_all ON riders
  FOR ALL USING (public.get_role() = 'admin')
  WITH CHECK (public.get_role() = 'admin');
