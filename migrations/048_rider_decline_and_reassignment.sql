-- Sprint 12: rider decline / reassignment -- SPRINT_PLANNING.md §11's
-- Sprint 12 entry: "§8.5 only ever built 'Accept.' A rider who declines, or
-- goes unreachable mid-delivery, currently leaves orders.rider_id/
-- riders.status='on_delivery' stuck with no way back. Design the decline/
-- timeout/reassignment flow explicitly."
--
-- ===========================================================================
-- THE FLOW, DECIDED EXPLICITLY
-- ===========================================================================
--
-- **Decline (rider-initiated, before Accept only).** A rider who has been
-- assigned (rpc_assign_rider, migrations/039) but hasn't yet tapped Accept
-- (rpc_rider_accept_order, migrations/041 -- gated on no 'rider_accepted'
-- row existing for the order) can decline. Declining:
--   1. Records the decline in a new `order_rider_declines` table (below) --
--      not just an order_status_history free-text note -- because the
--      reassignment step needs a real, queryable exclusion list, and parsing
--      "which riders declined this order" back out of free-text history
--      notes would be fragile in a way a real table isn't.
--   2. Frees the rider: `orders.rider_id` -> NULL, `riders.status` ->
--      'available'. `order_status_history` gets a 'rider_declined' entry
--      (Realtime-visible to the buyer's own tracking screen, §7.5 -- an
--      honest "still finding you a rider" moment rather than the screen
--      silently stalling on a rider who will never show up).
--   3. **Immediately retries rpc_assign_rider**, excluding every rider who
--      has ever declined this specific order (the new
--      p_exclude_rider_ids param, below) -- decided explicitly, not left
--      ambiguous: a decline should not require the shop to notice and
--      manually intervene when another available rider might already be
--      right there. If reassignment finds nobody (NO_RIDER_AVAILABLE, the
--      normal/expected outcome whenever the rider pool is thin), the order
--      is left with rider_id = NULL and falls back to the shop's own manual
--      retry (routes/shopOrders.ts's existing POST .../assign-rider,
--      Sprint 9, owner/staff-gated) -- exactly the same documented fallback
--      migrations/039's own header already names for "no rider was
--      available at confirmation time." Decline just becomes a second way
--      to reach that same, already-real fallback path.
--
-- **Timeout (system-initiated, same effect as a decline).** §8.5 named no
-- rider-side timeout at all -- decided here: **yes, a real one.**
-- `rpc_expire_stale_rider_assignments` (migrations/049) runs on `pg_cron`
-- (same primitive migrations/045 already established for the Organizer
-- reminder job) and finds every order assigned to a rider for more than a
-- documented threshold with no 'rider_accepted' row yet -- an
-- assignment nobody has acknowledged is operationally identical to a
-- decline (the rider is unreachable, asleep, or the app is closed), so it
-- is handled by calling the exact same decline-and-reassign path, logged
-- as a distinct 'rider_assignment_timed_out' history entry rather than
-- 'rider_declined' so the two are still distinguishable after the fact.
--
-- **Post-acceptance unreachability, before pickup -- a real, disclosed gap
-- this sprint DOES close, with a manual (not automatic) escape hatch.** A
-- rider who accepted but then goes quiet before actually reaching the shop
-- (order still 'ready_for_pickup', `orders.rider_id` set) is exactly the
-- case `forceReassignRider` (lib/riderAssignment.ts) exists for --
-- routes/shopOrders.ts's existing assign-rider retry (Sprint 9) is EXTENDED
-- this sprint (see that file's own updated comment) to also work on an
-- order that already HAS a rider assigned, releasing them and searching
-- again. Decided manual, not automatic: there is no reliable signal this
-- project can act on (`riders.current_location` updates are best-effort
-- pings, rider_location_pinger.dart, Sprint 9, whose *absence* doesn't
-- distinguish "phone is off" from "stuck in traffic" -- inventing a
-- staleness threshold here would be guessing at an SLA nobody has
-- specified). An owner/staff who has confirmed by phone (or otherwise) that
-- the current rider genuinely can't continue triggers it themselves.
--
-- **Once genuinely out for delivery (`orders.status = 'out_for_delivery'`,
-- the rider has physically picked up the order) -- deliberately NOT
-- reassignable at all, by either this mechanism or a cancellation
-- (migrations/047's own state machine refuses both past this point).**
-- Reassigning to a *different* rider can't fix "the package is with an
-- unreachable rider" -- the new rider has nothing to collect from the shop.
-- That failure mode is a real-world logistics escalation (call the rider,
-- send someone after them, treat the order as lost) with no software fix
-- this schema can express, and inventing one would be exactly the kind of
-- unscoped feature this project's standing discipline avoids. Named here
-- plainly as the actual boundary of what "decline/timeout/reassignment"
-- means in this sprint, not left to be discovered as a surprise 409 later.
--
-- ===========================================================================

CREATE TABLE IF NOT EXISTS order_rider_declines (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id     UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  rider_id     UUID NOT NULL REFERENCES riders(id) ON DELETE CASCADE,
  reason       TEXT,
  declined_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (order_id, rider_id)
);

CREATE INDEX IF NOT EXISTS idx_order_rider_declines_order_id ON order_rider_declines(order_id);

ALTER TABLE order_rider_declines ENABLE ROW LEVEL SECURITY;

-- Own-rider data, read-only -- a rider can see which orders they've
-- personally declined (e.g. to render "you declined this" in their own
-- history), never anyone else's declines. No shop/admin policy: this table
-- is an internal reassignment mechanism, not a customer-facing or
-- shop-facing record the way shop_ledger_entries is -- nothing in this
-- sprint's scope names a UI surface for it beyond the rider's own app, and
-- RLS here is a backstop only anyway (§5.1) since the Edge Function never
-- queries this table through PostgREST.
DROP POLICY IF EXISTS order_rider_declines_select_own_rider ON order_rider_declines;
CREATE POLICY order_rider_declines_select_own_rider ON order_rider_declines
  FOR SELECT USING (
    rider_id = (SELECT id FROM riders WHERE user_id = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- rpc_assign_rider, extended with an exclusion list -- DROP + CREATE rather
-- than CREATE OR REPLACE because adding a parameter changes the function's
-- own identity (name + argument types) in Postgres; a bare REPLACE would
-- have left the original single-argument version registered alongside this
-- one as a separate overload instead of actually changing it.
-- `p_exclude_rider_ids UUID[] DEFAULT NULL` keeps every existing
-- single-argument call site (lib/riderAssignment.ts's assignRider(),
-- unchanged this sprint) working exactly as before -- NULL means "exclude
-- nobody," the same behavior as the pre-Sprint-12 function.
-- ---------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.rpc_assign_rider(UUID);

-- OR REPLACE, not a bare CREATE, so *this* file is itself safe to re-run
-- once the two-argument signature above already exists (the DROP above only
-- ever needs to fire once, to clear the old one-argument overload from
-- migrations/039 -- on any later re-run it's a harmless no-op, and without
-- OR REPLACE here the CREATE FUNCTION below would then fail with "function
-- already exists" the same way this project's CREATE POLICY statements did
-- before every one of them got a DROP POLICY IF EXISTS guard).
CREATE OR REPLACE FUNCTION public.rpc_assign_rider(
  p_order_id           UUID,
  p_exclude_rider_ids  UUID[] DEFAULT NULL
)
RETURNS TABLE(order_id UUID, rider_id UUID, rider_full_name TEXT, rider_phone TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
-- Carried over from migrations/039, including the same real bug that
-- file's own header now documents the full two-attempt story of (caught by
-- actually running this against a live database; the first fix attempted
-- -- widening search_path rather than schema-qualifying -- was ALSO
-- verified against the live database and still failed). Fixed here too,
-- not just upstream, the same confirmed way: every PostGIS type/operator
-- below explicitly qualified to `public` (confirmed via `pg_extension` on
-- the live database, not guessed), search_path back to `''` -- this
-- DROP+CREATE would otherwise reintroduce the exact bug migrations/039
-- fixed, the moment it runs.
SET search_path = ''
AS $$
DECLARE
  v_order      public.orders%ROWTYPE;
  v_shop_point public.geography;
  v_rider      public.riders%ROWTYPE;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND' USING ERRCODE = 'P0040';
  END IF;

  IF v_order.delivery_fulfilled_by IS DISTINCT FROM 'platform_rider' THEN
    RAISE EXCEPTION 'NOT_PLATFORM_RIDER_ORDER' USING ERRCODE = 'P0041';
  END IF;

  IF v_order.status IN ('completed', 'cancelled') THEN
    RAISE EXCEPTION 'ORDER_NOT_ASSIGNABLE' USING ERRCODE = 'P0042';
  END IF;

  -- Idempotent, unchanged from migrations/039 -- an order that already has a
  -- rider returns that assignment rather than re-searching. Sprint 12's own
  -- callers (rpc_rider_decline_order, rpc_expire_stale_rider_assignments,
  -- both migrations/048-049) always clear orders.rider_id to NULL before
  -- calling this, specifically so this guard doesn't short-circuit the
  -- reassignment they're asking for.
  IF v_order.rider_id IS NOT NULL THEN
    SELECT * INTO v_rider FROM public.riders WHERE id = v_order.rider_id;
    RETURN QUERY SELECT v_order.id, v_rider.id, v_rider.full_name, v_rider.phone;
    RETURN;
  END IF;

  SELECT location INTO v_shop_point FROM public.shops WHERE id = v_order.shop_id;
  IF v_shop_point IS NULL THEN
    RAISE EXCEPTION 'SHOP_LOCATION_MISSING' USING ERRCODE = 'P0043';
  END IF;

  SELECT * INTO v_rider
  FROM public.riders
  WHERE status = 'available' AND is_verified = true AND current_location IS NOT NULL
    AND (p_exclude_rider_ids IS NULL OR id <> ALL(p_exclude_rider_ids))
  ORDER BY current_location OPERATOR(public.<->) v_shop_point
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NO_RIDER_AVAILABLE' USING ERRCODE = 'P0044';
  END IF;

  UPDATE public.orders SET rider_id = v_rider.id, updated_at = now() WHERE id = p_order_id;
  UPDATE public.riders SET status = 'on_delivery' WHERE id = v_rider.id;

  INSERT INTO public.order_status_history (order_id, status, note)
  VALUES (p_order_id, 'rider_assigned', 'Assigned to ' || v_rider.full_name);

  RETURN QUERY SELECT v_order.id, v_rider.id, v_rider.full_name, v_rider.phone;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_assign_rider(UUID, UUID[]) FROM authenticated, anon, public;

-- ---------------------------------------------------------------------------
-- rpc_rider_decline_order -- the rider-initiated half of the flow above.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.rpc_rider_decline_order(
  p_rider_user_id UUID,
  p_order_id      UUID,
  p_reason        TEXT DEFAULT NULL
)
RETURNS public.orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_rider_id UUID;
  v_order    public.orders%ROWTYPE;
  v_accepted BOOLEAN;
  v_excluded UUID[];
  v_result   public.orders%ROWTYPE;
BEGIN
  SELECT id INTO v_rider_id FROM public.riders WHERE user_id = p_rider_user_id;
  IF v_rider_id IS NULL THEN
    RAISE EXCEPTION 'RIDER_PROFILE_NOT_FOUND' USING ERRCODE = 'P0045';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.rider_id IS DISTINCT FROM v_rider_id THEN
    RAISE EXCEPTION 'ORDER_NOT_ASSIGNED_TO_RIDER' USING ERRCODE = 'P0046';
  END IF;

  IF v_order.status IN ('cancelled', 'completed') THEN
    RAISE EXCEPTION 'ORDER_ALREADY_FINAL' USING ERRCODE = 'P0052';
  END IF;

  -- A rider who has already tapped Accept is mid-commitment -- declining
  -- past that point is the "goes unreachable mid-delivery" case this
  -- migration's own header hands to the shop's manual reassign action
  -- instead, not this RPC.
  SELECT EXISTS(
    SELECT 1 FROM public.order_status_history
    WHERE order_id = p_order_id AND status = 'rider_accepted'
  ) INTO v_accepted;
  IF v_accepted THEN
    RAISE EXCEPTION 'ALREADY_ACCEPTED_CANNOT_DECLINE' USING ERRCODE = 'P0070';
  END IF;

  INSERT INTO public.order_rider_declines (order_id, rider_id, reason)
  VALUES (p_order_id, v_rider_id, p_reason)
  ON CONFLICT (order_id, rider_id) DO NOTHING;

  UPDATE public.orders SET rider_id = NULL, updated_at = now() WHERE id = p_order_id;
  UPDATE public.riders SET status = 'available' WHERE id = v_rider_id;

  INSERT INTO public.order_status_history (order_id, status, note)
  VALUES (p_order_id, 'rider_declined', COALESCE('Declined: ' || p_reason, 'Rider declined the assignment'));

  SELECT array_agg(rider_id) INTO v_excluded FROM public.order_rider_declines WHERE order_id = p_order_id;

  BEGIN
    PERFORM public.rpc_assign_rider(p_order_id, v_excluded);
  EXCEPTION WHEN OTHERS THEN
    -- NO_RIDER_AVAILABLE is the expected, common outcome here -- the order
    -- is left with rider_id = NULL either way, which is the correct, safe
    -- state regardless of why reassignment didn't happen this instant. The
    -- shop's own manual retry is always the documented fallback (header,
    -- above) -- a decline must succeed even when nobody else is free right
    -- now, so this is caught broadly and logged, never re-raised.
    RAISE WARNING 'rpc_rider_decline_order: immediate reassignment for order % failed: %', p_order_id, SQLERRM;
  END;

  SELECT * INTO v_result FROM public.orders WHERE id = p_order_id;
  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_rider_decline_order(UUID, UUID, TEXT) FROM authenticated, anon, public;
