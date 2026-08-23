-- Sprint 1: users table.
-- Mirrors auth.users 1:1 (id has no default -- it must be set explicitly to
-- the matching Supabase Auth id on insert, same convention Baker Ally used).
-- role is a plain TEXT CHECK rather than Baker Ally's roles/privilege_levels
-- table pair -- Proximity has exactly four fixed platform-level roles
-- (SPRINT_PLANNING.md §1.2/§4.1), so the extra normalization Baker Ally
-- needed for its finer-grained staff permission system isn't earning its
-- keep here. Shop-scoped staff/delivery permissions live in
-- shop_team_members (created in Sprint 2 alongside shops), not in this role
-- column -- see §1.2's reasoning for why that split is deliberate.
-- fcm_token: same addition Baker Ally made beyond the original schema sketch
-- -- there's nowhere else for a push-notification device token to live, and
-- Sprint 11 (Organizer reminders) needs it.

CREATE TABLE IF NOT EXISTS users (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role        TEXT NOT NULL DEFAULT 'buyer'
                CHECK (role IN ('buyer', 'shop_owner', 'rider', 'admin')),
  full_name   TEXT,
  phone       TEXT,
  email       TEXT,
  avatar_url  TEXT,
  fcm_token   TEXT,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);

ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Own-row read/update -- SPRINT_PLANNING.md §5.2 "own-user data" pattern.
CREATE POLICY users_select_own ON users
  FOR SELECT USING (id = auth.uid());

CREATE POLICY users_update_own ON users
  FOR UPDATE USING (id = auth.uid())
  WITH CHECK (id = auth.uid() AND role = (SELECT role FROM users WHERE id = auth.uid()));
  -- role is deliberately excluded from what a user can change about
  -- themselves -- role changes go through the admin RPC path only.
