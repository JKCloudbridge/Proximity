-- Sprint 7: orders -- literal DDL from SPRINT_PLANNING.md §4.8, verbatim,
-- including both CHECK constraints exactly as written there. "One row per
-- shop inside that checkout -- own fulfillment, own slot, own status."
--
-- No additions at all to this one. The two CHECKs are the point of the
-- table and are quoted from §4.8 unchanged:
--   1. delivery implies an address AND a named fulfiller; pickup implies
--      neither.
--   2. §1.3's instruction, enforced at the DB layer rather than only in the
--      UI: a delivery fee can only exist when a platform rider is actually
--      doing the delivery. A `self`-delivering shop or a pickup can never
--      carry one. rpc_place_order (032) is written to respect this, but the
--      constraint is what actually guarantees it -- if that RPC ever gets a
--      fee-calculation bug, this fails the whole transaction rather than
--      quietly overcharging a buyer for a shop's own delivery.
--
-- `rider_id` stays NULL for the whole of this sprint -- rpc_assign_rider and
-- the rider touchpoint are Sprint 9 (§11). The column exists now because
-- §4.8 defines it now.
--
-- `platform_commission_pct` is snapshotted from shops at order time (§4.8's
-- own comment) rather than joined live, so a later admin change to a shop's
-- commission can't retroactively rewrite what an already-placed order owed.

CREATE TABLE IF NOT EXISTS orders (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_group_id         UUID NOT NULL REFERENCES order_groups(id) ON DELETE CASCADE,
  user_id                UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  shop_id                UUID NOT NULL REFERENCES shops(id),
  fulfillment_type       TEXT NOT NULL CHECK (fulfillment_type IN ('pickup','delivery')),
  delivery_fulfilled_by  TEXT CHECK (delivery_fulfilled_by IN ('shop','platform_rider')),  -- NULL if pickup
  address_id             UUID REFERENCES addresses(id),
  slot_start             TIMESTAMPTZ NOT NULL,
  slot_end               TIMESTAMPTZ NOT NULL,
  rider_id               UUID REFERENCES riders(id),    -- set only when delivery_fulfilled_by='platform_rider'
  status                 TEXT NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending','confirmed','preparing','ready_for_pickup',
                                               'out_for_delivery','completed','cancelled')),
  subtotal               INTEGER NOT NULL,                  -- this shop's share only
  discount_value         INTEGER NOT NULL DEFAULT 0,
  delivery_fee           INTEGER NOT NULL DEFAULT 0,
  platform_commission_pct NUMERIC(4,2) NOT NULL,            -- snapshotted from shops at order time
  total                  INTEGER NOT NULL,                  -- this shop's share of the one combined charge
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (
    (fulfillment_type = 'delivery' AND address_id IS NOT NULL AND delivery_fulfilled_by IS NOT NULL) OR
    (fulfillment_type = 'pickup' AND delivery_fulfilled_by IS NULL)
  ),
  -- Your instruction, enforced at the DB layer, not just the UI: no delivery
  -- fee unless a platform rider is actually doing the delivery.
  CHECK (delivery_fee = 0 OR delivery_fulfilled_by = 'platform_rider')
);

CREATE INDEX IF NOT EXISTS idx_orders_user_created ON orders(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_shop_created ON orders(shop_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_order_group_id ON orders(order_group_id);

ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Two ownership classes read this table (§5.2): the buyer who placed it,
-- and the shop team it belongs to. Both are backstops only (§5.1).
DROP POLICY IF EXISTS orders_select_own ON orders;
CREATE POLICY orders_select_own ON orders
  FOR SELECT USING (user_id = auth.uid());

-- §8.3, restated in §4.8: "the shopkeeper dashboard's order list already
-- only shows their own shop's orders rows by construction" -- this is that,
-- at the DB layer. Any member_role can read (owner/staff/delivery all need
-- to see the order they're fulfilling, §5.3); status advancement goes
-- through rpc_shop_advance_order_status (Sprint 9), not a direct UPDATE.
DROP POLICY IF EXISTS orders_select_shop_team ON orders;
CREATE POLICY orders_select_shop_team ON orders
  FOR SELECT USING (shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS orders_admin_all ON orders;
CREATE POLICY orders_admin_all ON orders
  FOR ALL USING (public.get_role() = 'admin')
  WITH CHECK (public.get_role() = 'admin');
