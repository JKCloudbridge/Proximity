-- Sprint 7: order_status_history -- literal DDL from SPRINT_PLANNING.md
-- §4.8, verbatim, no additions.
--
-- Written to by rpc_place_order (032) for the initial 'pending' row, and
-- from Sprint 9 onward by rpc_shop_advance_order_status /
-- rpc_rider_update_status (§5.4). §7.5's live order tracking subscribes to
-- this table via Supabase Realtime, filtered to one order_group_id's child
-- orders -- which is exactly why status changes get their own append-only
-- table instead of just mutating orders.status in place: a Realtime
-- subscriber needs an INSERT to react to, and "when did this order become
-- ready" is genuinely useful history, not redundant with the current value.
--
-- Append-only by intent -- no UPDATE/DELETE policy for anyone below,
-- including admins. A status history you can rewrite isn't one.

CREATE TABLE IF NOT EXISTS order_status_history (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id    UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  status      TEXT NOT NULL,
  note        TEXT,
  changed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_order_status_history_order_changed
  ON order_status_history(order_id, changed_at DESC);

ALTER TABLE order_status_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS order_status_history_select_own ON order_status_history;
CREATE POLICY order_status_history_select_own ON order_status_history
  FOR SELECT USING (order_id IN (SELECT id FROM orders WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS order_status_history_select_shop_team ON order_status_history;
CREATE POLICY order_status_history_select_shop_team ON order_status_history
  FOR SELECT USING (
    order_id IN (
      SELECT o.id FROM orders o
      WHERE o.shop_id IN (SELECT shop_id FROM shop_team_members WHERE user_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS order_status_history_select_admin ON order_status_history;
CREATE POLICY order_status_history_select_admin ON order_status_history
  FOR SELECT USING (public.get_role() = 'admin');
