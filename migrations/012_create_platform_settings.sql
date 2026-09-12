-- Sprint 2: platform_settings -- SPRINT_PLANNING.md §4.6, verbatim,
-- including the three seeded rows named there (delivery fee, slot window,
-- default commission). Deliberately generic key/value shape so later
-- admin-tunable constants don't each need their own migration+column.
--
-- Public read: the buyer app needs slot_window (checkout, §7.4) and the
-- platform rider delivery fee (order total breakdown) with no auth
-- required to browse -- none of these three seeded values are sensitive.
-- Writes are admin-only; the actual settings-editor UI is Sprint 12
-- (§11's Sprint 12 entry) -- this sprint only seeds the rows the schema
-- names, no PATCH route yet (see Sprint 2.md's "not yet built" section).

CREATE TABLE IF NOT EXISTS platform_settings (
  key         TEXT PRIMARY KEY,
  value       JSONB NOT NULL,
  updated_by  UUID REFERENCES users(id),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE platform_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY platform_settings_select_all ON platform_settings
  FOR SELECT USING (true);

CREATE POLICY platform_settings_admin_write ON platform_settings
  FOR ALL USING (public.get_role() = 'admin')
  WITH CHECK (public.get_role() = 'admin');

INSERT INTO platform_settings (key, value) VALUES
  ('platform_rider_delivery_fee', '{"amount_paise": 3000}'),
  ('slot_window',                 '{"start": "06:00", "end": "24:00", "slot_minutes": 120}'),
  ('default_shop_commission_pct', '{"value": 10.00}')
ON CONFLICT (key) DO NOTHING;
