-- Sprint 7: shop_ledger_entries -- literal DDL from SPRINT_PLANNING.md
-- §4.9, verbatim, no additions. Replaces v1's `payouts` table; needed in
-- both directions now that pay_at_shop is a real MVP payment mode (§1.4):
--   payout_due     -- platform collected online, owes the shop (total - commission)
--   commission_due -- shop collected pay_at_shop directly, owes the platform its cut
--
-- **Table only this sprint -- nothing writes a row yet.** §11 puts ledger
-- insertion in Sprint 8 ("rpc_confirm_payment ... shop_ledger_entries
-- insertion on both paths"), not here, and rpc_place_order (032)
-- deliberately does not insert either: an order that has been *placed* but
-- not yet *paid* owes nobody anything. Creating the table now, one sprint
-- ahead of its first writer, is what §11's own Sprint 7 migration list asks
-- for -- same "table exists before its route does" situation shop_media /
-- shop_blackout_dates / product_cross_sell have each sat in.
--
-- One real open question this sprint deliberately does NOT answer, recorded
-- here because this is the table where it eventually bites: **when a
-- platform-authored discount code (migrations/026) reduces an order's
-- total, who absorbs it -- the platform or the shop?** rpc_place_order
-- stores enough to decide either way later (`orders.subtotal` is the
-- pre-discount per-shop figure; `orders.discount_value` is that shop's
-- allocated share of the group discount), so the schema forecloses
-- nothing -- but Sprint 8, which actually computes `payout_due` amounts,
-- has to pick one and say so out loud. Flagging it here rather than
-- letting Sprint 8 discover it mid-implementation.

CREATE TABLE IF NOT EXISTS shop_ledger_entries (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id      UUID NOT NULL REFERENCES shops(id),
  order_id     UUID REFERENCES orders(id),
  entry_type   TEXT NOT NULL CHECK (entry_type IN ('payout_due', 'commission_due')),
  amount       INTEGER NOT NULL,      -- paise, always positive; entry_type gives direction
  status       TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','settled')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_shop_ledger_entries_shop_status
  ON shop_ledger_entries(shop_id, status, created_at DESC);

ALTER TABLE shop_ledger_entries ENABLE ROW LEVEL SECURITY;

-- Shop-team data (§5.2), narrowed further by §5.3's permission matrix:
-- "View sales summary / ledger / invoices" is owner + staff (read-only),
-- never `delivery`. §8.4's shop-side ledger view is the consumer.
CREATE POLICY shop_ledger_entries_select_shop_team ON shop_ledger_entries
  FOR SELECT USING (
    shop_id IN (
      SELECT shop_id FROM shop_team_members
      WHERE user_id = auth.uid() AND member_role IN ('owner', 'staff')
    )
  );

-- §8.6's platform-wide ledger view across all shops.
CREATE POLICY shop_ledger_entries_admin_all ON shop_ledger_entries
  FOR ALL USING (public.get_role() = 'admin')
  WITH CHECK (public.get_role() = 'admin');
