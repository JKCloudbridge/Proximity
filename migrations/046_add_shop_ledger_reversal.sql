-- Sprint 12: shop_ledger_entries reversal support -- SPRINT_PLANNING.md
-- §11's Sprint 12 entry names this precisely: "design and document exactly
-- how a reversal entry is represented (a new offsetting row vs. a status
-- change on the original, and why)."
--
-- ===========================================================================
-- DECISION: a new offsetting row, never a mutation of the original entry.
-- ===========================================================================
--
-- Two entry_type values are added -- 'payout_reversal' (cancels a
-- 'payout_due') and 'commission_reversal' (cancels a 'commission_due') --
-- rather than reusing the existing two types with a negative `amount`.
-- Reasoning:
--
--   1. **Immutability, matching this schema's own established convention.**
--      order_items snapshots product_name/variant_name/unit_price at order
--      time and is never edited afterwards (§9); invoices snapshots
--      shop_name/shop_gstin the same way. shop_ledger_entries is a financial
--      record of the same character -- rewriting a 'settled' row's amount or
--      status after money may already have physically moved (Phase 2
--      settlement automation, still not built, but the `status` column
--      already models it) would silently corrupt a historical record with no
--      trace that a correction ever happened. A new row leaves both the
--      original obligation and the fact-of-its-cancellation permanently
--      visible, in order, which is what a real ledger is for.
--   2. **`amount` stays "always positive; entry_type gives direction"**
--      (migrations/031's own column comment, unchanged) -- a signed amount
--      would quietly break that invariant and every existing SUM(amount)
--      call site (this migration's own header is the reason this project
--      never reused the existing two types with a negative value: it would
--      have made "payout_due total" and "payout_due minus reversed" the same
--      naive query, silently wrong the moment a reversal existed).
--   3. **The balance formula stays one shape regardless of timing.** Whether
--      an order is cancelled before or after its original entry was marked
--      'settled', the outstanding balance for a shop is always:
--        net payout owed to shop        = SUM(payout_due)     - SUM(payout_reversal)
--        net commission owed by shop    = SUM(commission_due) - SUM(commission_reversal)
--      lib/ledger.ts (Sprint 12) computes exactly this, both in the shop
--      dashboard's own ledger view and the platform-wide admin one -- no
--      special-casing "was this already settled when it got cancelled."
--
-- `reverses_entry_id` names exactly which original entry a reversal cancels
-- -- nullable (only reversal rows ever set it), self-referencing, no ON
-- DELETE action needed since shop_ledger_entries rows are never deleted (a
-- correction is always another row, never a delete -- same reasoning as #1
-- above). A CHECK ties the two together so a reversal row can't exist
-- without naming its target and a non-reversal row can't carry one by
-- mistake -- caught by name at the schema level rather than left to
-- application-code discipline alone (§5.1's "don't trust the RPC's caller
-- alone" bar, applied to a self-consistency invariant this time rather than
-- an access-control one).
--
-- rpc_cancel_order (migrations/047) is the only writer of reversal rows --
-- see that file's header for the actual reversal algorithm ("mirror every
-- existing non-reversed entry for this order, not recompute the money").

ALTER TABLE shop_ledger_entries
  DROP CONSTRAINT IF EXISTS shop_ledger_entries_entry_type_check;

ALTER TABLE shop_ledger_entries
  ADD CONSTRAINT shop_ledger_entries_entry_type_check
  CHECK (entry_type IN ('payout_due', 'commission_due', 'payout_reversal', 'commission_reversal'));

ALTER TABLE shop_ledger_entries
  ADD COLUMN IF NOT EXISTS reverses_entry_id UUID REFERENCES shop_ledger_entries(id);

ALTER TABLE shop_ledger_entries
  ADD CONSTRAINT shop_ledger_entries_reversal_shape_check
  CHECK (
    (entry_type IN ('payout_reversal', 'commission_reversal') AND reverses_entry_id IS NOT NULL) OR
    (entry_type IN ('payout_due', 'commission_due') AND reverses_entry_id IS NULL)
  );

-- One reversal per original entry, at most -- rpc_cancel_order's own guard
-- (migrations/047) already checks this before inserting, but the constraint
-- makes it true even against a hypothetical second caller, same
-- belt-and-suspenders standard every RPC in this project holds itself to.
CREATE UNIQUE INDEX IF NOT EXISTS idx_shop_ledger_entries_reverses_entry_id
  ON shop_ledger_entries(reverses_entry_id) WHERE reverses_entry_id IS NOT NULL;
