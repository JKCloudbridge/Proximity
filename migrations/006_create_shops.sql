-- Sprint 2: shops table -- SPRINT_PLANNING.md §4.4, verbatim except
-- `delivery_fee` never existed here to begin with (removed vs. v1, per
-- §4.4's own note -- it's an admin-controlled platform_settings row, not a
-- shopkeeper-set column) and `delivery_mode` is present from the start.
--
-- location is NOT NULL, same "every downstream feature depends on this"
-- reasoning as addresses.location (002) -- shops-near-you, service-radius
-- filtering, and fulfillment-slot generation all need it. Set in the same
-- INSERT as everything else via rpc_create_shop (014), unlike addresses'
-- two-step insert-then-UPDATE (Sprint 1 didn't have the option of doing it
-- in one statement because that insert goes through Drizzle, not raw SQL --
-- this one does, since it's RPC-only from the start).

CREATE TABLE IF NOT EXISTS shops (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id                 UUID NOT NULL REFERENCES users(id),
  name                     TEXT NOT NULL,
  description              TEXT,
  logo_url                 TEXT,
  cover_image_url          TEXT,
  gstin                    TEXT,
  fssai_license_no         TEXT,
  address_line             TEXT NOT NULL,
  city                     TEXT NOT NULL,
  pincode                  TEXT NOT NULL,
  location                 GEOGRAPHY(Point, 4326) NOT NULL,
  service_radius_km        NUMERIC(4,1) NOT NULL DEFAULT 3.0,
  supports_pickup          BOOLEAN NOT NULL DEFAULT true,
  supports_delivery        BOOLEAN NOT NULL DEFAULT true,
  delivery_mode            TEXT NOT NULL DEFAULT 'self' CHECK (delivery_mode IN ('self','platform','both')),
  min_order_value          INTEGER NOT NULL DEFAULT 0,
  status                   TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','suspended')),
  platform_commission_pct  NUMERIC(4,2) NOT NULL DEFAULT 10.00,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_shops_location ON shops USING GIST(location);
CREATE INDEX IF NOT EXISTS idx_shops_owner_id ON shops(owner_id);
CREATE INDEX IF NOT EXISTS idx_shops_status ON shops(status);

ALTER TABLE shops ENABLE ROW LEVEL SECURITY;

-- Public browsing (buyer app, from Sprint 4 on) only ever sees approved
-- shops -- pending/suspended shops don't leak into "shops near you" through
-- this policy. This is a backstop, not the live enforcement (§5.1) -- the
-- Edge Function's buyer-facing shop routes filter on status themselves too
-- once they exist.
DROP POLICY IF EXISTS shops_select_public ON shops;
CREATE POLICY shops_select_public ON shops
  FOR SELECT USING (status = 'approved');

DROP POLICY IF EXISTS shops_admin_all ON shops;
CREATE POLICY shops_admin_all ON shops
  FOR ALL USING (public.get_role() = 'admin')
  WITH CHECK (public.get_role() = 'admin');

-- Two more shops policies (shops_select_team, shops_owner_update) are
-- created in 007_create_shop_team_members.sql, not here -- they need to
-- reference shop_team_members in their USING/WITH CHECK clauses, and that
-- table doesn't exist until 007 (it FKs to shops.id, so it can't come
-- first either -- this is the one circular-looking dependency in this
-- sprint's migrations, resolved by splitting the policy creation across
-- both files rather than reordering the tables themselves).
