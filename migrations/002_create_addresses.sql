-- Sprint 1: addresses table (buyer delivery addresses).
-- location is the core new capability vs. anything Baker Ally needed --
-- geography(Point,4326) + a GIST index is what makes "shops near you" and
-- the fulfillment-slot/delivery-fee logic possible at all. Populated at
-- save-time via Google Geocoding API (typed address -> lat/lng) or directly
-- from device GPS for "use my current location" -- see
-- SPRINT_PLANNING.md §4.2.

CREATE TABLE IF NOT EXISTS addresses (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label       TEXT,                 -- "Home", "Work"
  line1       TEXT NOT NULL,
  line2       TEXT,
  city        TEXT NOT NULL,
  state       TEXT NOT NULL,
  pincode     TEXT NOT NULL,
  location    GEOGRAPHY(Point, 4326) NOT NULL,
  is_default  BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_addresses_user_id ON addresses(user_id);
CREATE INDEX IF NOT EXISTS idx_addresses_location ON addresses USING GIST(location);

ALTER TABLE addresses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS addresses_all_own ON addresses;
CREATE POLICY addresses_all_own ON addresses
  FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
