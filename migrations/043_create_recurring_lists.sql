-- Sprint 11: recurring_lists / recurring_list_items -- the Organizer
-- feature. SPRINT_PLANNING.md §4.10 names these two tables but, same
-- situation every "carries over unchanged from v1" table has hit since
-- Sprint 3 (products/wishlists/carts/discounts/invoices), gives no literal
-- DDL for either -- and this time there isn't even a recoverable original
-- to check against: Baker Ally's actual working tree has no
-- recurring_list/organizer migration, route, or screen anywhere at all (not
-- even a prose spec the way Order Again's 03_order_again_tab.md existed --
-- checked directly, per the standing rule, not assumed). So this is a
-- genuinely fresh design against §4.10's own thin prose ("organizer,
-- reminder-mode per your confirmed decision") plus §11's Sprint 11 entry,
-- not a port of anything.
--
-- **What a recurring list actually needs, decided here:**
--   - A name (buyer-facing label -- "Weekly groceries," "Office snacks").
--   - A cadence + an anchor time-of-day the reminder should fire at, not
--     just a bare interval -- "every Monday at 9am" is what a buyer
--     actually means by "recurring," not "every 7*24 hours from whenever I
--     happened to create this." `time_of_day` + `next_run_at` (below)
--     together express that.
--   - `next_run_at`, not a derived/computed column -- the pg_cron
--     processing job (migrations/045) needs one cheap, indexable
--     "is anything due" query (`WHERE next_run_at <= now() AND is_active`),
--     and storing the materialized next-fire timestamp (advanced forward by
--     that same job after each fire, from the *previous* next_run_at, not
--     from now() -- see 045's header for why) is how every other
--     time-based query in this codebase already works (shop_blackout_dates,
--     order slot generation) -- no new pattern introduced.
--   - `is_active` -- pause/resume without losing the list or its items
--     (delete is a separate, destructive action).
--   - Deliberately NOT included: a `day_of_week`/multi-day schedule (e.g.
--     "every Mon and Thu"). §11's scope is "reminder + pre-filled-cart mode
--     only" with no other mode named -- a single cadence anchor covers
--     daily/weekly/biweekly/monthly/a custom N-day interval, which is
--     already more than any other scheduling concept this project has; a
--     multi-day-of-week schedule is a real Phase-2 refinement on top of
--     this, not required to make "a scheduled recurring list fires a
--     reminder at the right time" (§11's exit criteria) true.
--
-- Own-user data (§5.2's ownership-class table), same RLS shape as
-- wishlists (021): one FOR ALL USING(user_id = auth.uid()) policy, no
-- shop-team or admin policy -- a recurring list is never shop- or
-- admin-visible, same reasoning wishlists already established.

CREATE TABLE IF NOT EXISTS recurring_lists (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name           TEXT NOT NULL,
  cadence        TEXT NOT NULL CHECK (cadence IN ('daily', 'weekly', 'biweekly', 'monthly', 'custom_days')),
  -- Only meaningful (and only allowed to be non-NULL) when cadence is
  -- 'custom_days' -- every other cadence has a fixed, self-describing
  -- interval and doesn't need this column at all. Enforced by CHECK, not
  -- just application-layer discipline, same "don't trust the UI alone" bar
  -- every other cross-column invariant in this schema holds to
  -- (orders' own delivery_fee/delivery_fulfilled_by CHECK, §4.8, is the
  -- precedent this one is modeled on directly).
  interval_days  INTEGER CHECK (
    (cadence = 'custom_days' AND interval_days > 0) OR
    (cadence <> 'custom_days' AND interval_days IS NULL)
  ),
  -- IST wall-clock time-of-day the reminder should fire at, same "no
  -- per-shop/per-platform timezone column exists anywhere in this project,
  -- every date assumption so far implicitly means India wall-clock time"
  -- judgment call lib/slots.ts's own header already made explicit in
  -- Sprint 4 -- not re-litigated here, just inherited.
  time_of_day    TIME NOT NULL DEFAULT '09:00:00',
  next_run_at    TIMESTAMPTZ NOT NULL,
  last_run_at    TIMESTAMPTZ,
  is_active      BOOLEAN NOT NULL DEFAULT true,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Partial index on exactly the predicate migrations/045's cron job filters
-- on -- same "index the query you actually run" discipline idx_shops_location
-- /idx_riders_location already established for their own GIST indexes.
CREATE INDEX IF NOT EXISTS idx_recurring_lists_due ON recurring_lists(next_run_at) WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_recurring_lists_user_id ON recurring_lists(user_id);

ALTER TABLE recurring_lists ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS recurring_lists_all_own ON recurring_lists;
CREATE POLICY recurring_lists_all_own ON recurring_lists
  FOR ALL USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- recurring_list_items -- scoped to a product_variant, not a bare product
-- (unlike wishlists' deliberate product-level scoping, 021): this list's
-- whole point is to pre-fill a real cart via rpc_add_to_cart (024), which
-- takes a variant_id, not a product_id -- there is no "pick the variant
-- later" step the way the PDP's own wishlist-then-buy flow has one. A
-- buyer who wants "500ml milk" in their recurring list names the 500ml
-- variant directly, same granularity cart_items itself already uses.
CREATE TABLE IF NOT EXISTS recurring_list_items (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recurring_list_id  UUID NOT NULL REFERENCES recurring_lists(id) ON DELETE CASCADE,
  variant_id         UUID NOT NULL REFERENCES product_variants(id) ON DELETE CASCADE,
  quantity           INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (recurring_list_id, variant_id)
);

CREATE INDEX IF NOT EXISTS idx_recurring_list_items_list_id ON recurring_list_items(recurring_list_id);

ALTER TABLE recurring_list_items ENABLE ROW LEVEL SECURITY;

-- recurring_list_items has no user_id column of its own (by design, same
-- shape cart_items already established in Sprint 6) -- own-user data is
-- scoped one hop through recurring_lists.
DROP POLICY IF EXISTS recurring_list_items_all_own ON recurring_list_items;
CREATE POLICY recurring_list_items_all_own ON recurring_list_items
  FOR ALL USING (recurring_list_id IN (SELECT id FROM recurring_lists WHERE user_id = auth.uid()))
  WITH CHECK (recurring_list_id IN (SELECT id FROM recurring_lists WHERE user_id = auth.uid()));
