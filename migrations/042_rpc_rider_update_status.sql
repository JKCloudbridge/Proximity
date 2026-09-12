-- Sprint 9: rpc_rider_update_status(rider_user_id, order_id, new_status) --
-- SPRINT_PLANNING.md §5.4/§8.5: "rider-only, scoped to orders where
-- rider_id matches their own row, status ladder
-- picked_up -> out_for_delivery -> delivered, writing
-- order_status_history."
--
-- ===========================================================================
-- A REAL VOCABULARY MISMATCH THIS FUNCTION HAS TO RECONCILE, FLAGGED HERE
-- RATHER THAN PAPERED OVER: §5.4/§8.5's own rider ladder
-- (picked_up/out_for_delivery/delivered) and orders.status' own CHECK
-- constraint (migrations/028: pending/confirmed/preparing/ready_for_pickup/
-- out_for_delivery/completed/cancelled) are NOT the same three-value set --
-- 'picked_up' and 'delivered' aren't legal orders.status values at all, and
-- were never meant to become one (migrations/028's own header says "no
-- additions at all" and this sprint isn't the one to break that). The two
-- vocabularies serve different readers: orders.status is the strict column
-- every other role's queries/RLS/business logic key off (§4.8), while
-- order_status_history.status is free text (migrations/030, no CHECK) --
-- exactly the column §7.5's buyer-facing Realtime subscription renders as a
-- human-readable timeline. So every rider ladder step below ALWAYS writes
-- its own literal word ('picked_up'/'out_for_delivery'/'delivered') to
-- order_status_history for the buyer to see, and SEPARATELY advances
-- orders.status only on the two steps that have a real enum equivalent:
--
--   picked_up        -- orders.status: ready_for_pickup -> out_for_delivery.
--                        The moment a rider physically has the package, the
--                        order genuinely IS "out for delivery" in the one
--                        vocabulary every other role reads (shop dashboard,
--                        admin ledger views, §4.8 itself) -- there's no
--                        finer distinction those readers need. Requires an
--                        'rider_accepted' history row already exists
--                        (rpc_rider_accept_order, 041) -- a rider must
--                        Accept before the ladder starts, enforced here, not
--                        just gated client-side.
--   out_for_delivery  -- a progress re-ping, not a new orders.status (it's
--                        already 'out_for_delivery' from the step above).
--                        Real, not fake: a fresh order_status_history row
--                        with a live timestamp is exactly what §7.5's
--                        Realtime subscriber renders as "still on the way,
--                        updated 2 min ago" -- the enum has no finer state
--                        to advance to, but the buyer's timeline still gets
--                        a genuine new entry. Requires 'picked_up' to have
--                        already been logged for this order.
--   delivered         -- orders.status: out_for_delivery -> completed (the
--                        one shared terminal state every fulfillment path
--                        uses, §4.8 -- introducing a separate 'delivered'
--                        enum value would fragment every future "show
--                        completed orders" query into checking two values
--                        for no real benefit). Also flips the rider back to
--                        'available' -- their delivery is done, they're
--                        free for the next assignment. Requires
--                        'out_for_delivery' (this ladder's own step, not
--                        just the orders.status value) to have already been
--                        logged.
-- ===========================================================================
--
-- p_rider_user_id, not auth.uid() -- same reasoning as every RPC since 005.

CREATE OR REPLACE FUNCTION public.rpc_rider_update_status(
  p_rider_user_id UUID,
  p_order_id      UUID,
  p_new_status    TEXT
)
RETURNS public.orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order    public.orders%ROWTYPE;
  v_rider_id UUID;
  v_has      BOOLEAN;
  v_result   public.orders%ROWTYPE;
BEGIN
  IF p_new_status NOT IN ('picked_up', 'out_for_delivery', 'delivered') THEN
    RAISE EXCEPTION 'INVALID_NEW_STATUS' USING ERRCODE = 'P0060';
  END IF;

  SELECT id INTO v_rider_id FROM public.riders WHERE user_id = p_rider_user_id;
  IF v_rider_id IS NULL THEN
    RAISE EXCEPTION 'RIDER_PROFILE_NOT_FOUND' USING ERRCODE = 'P0061';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.rider_id IS DISTINCT FROM v_rider_id THEN
    RAISE EXCEPTION 'ORDER_NOT_ASSIGNED_TO_RIDER' USING ERRCODE = 'P0062';
  END IF;

  IF v_order.status IN ('completed', 'cancelled') THEN
    RAISE EXCEPTION 'ORDER_ALREADY_FINAL' USING ERRCODE = 'P0063';
  END IF;

  IF p_new_status = 'picked_up' THEN
    SELECT EXISTS(
      SELECT 1 FROM public.order_status_history
      WHERE order_id = p_order_id AND status = 'rider_accepted'
    ) INTO v_has;
    IF NOT v_has THEN
      RAISE EXCEPTION 'RIDER_HAS_NOT_ACCEPTED' USING ERRCODE = 'P0064';
    END IF;
    IF v_order.status <> 'ready_for_pickup' THEN
      RAISE EXCEPTION 'ORDER_NOT_READY_FOR_PICKUP' USING ERRCODE = 'P0065';
    END IF;
    UPDATE public.orders SET status = 'out_for_delivery', updated_at = now() WHERE id = p_order_id;

  ELSIF p_new_status = 'out_for_delivery' THEN
    SELECT EXISTS(
      SELECT 1 FROM public.order_status_history
      WHERE order_id = p_order_id AND status = 'picked_up'
    ) INTO v_has;
    IF NOT v_has THEN
      RAISE EXCEPTION 'NOT_PICKED_UP_YET' USING ERRCODE = 'P0066';
    END IF;
    -- No orders.status change -- already 'out_for_delivery' from the
    -- 'picked_up' step (header, above). Just a fresh timeline entry.

  ELSIF p_new_status = 'delivered' THEN
    SELECT EXISTS(
      SELECT 1 FROM public.order_status_history
      WHERE order_id = p_order_id AND status = 'out_for_delivery'
    ) INTO v_has;
    IF NOT v_has THEN
      RAISE EXCEPTION 'NOT_OUT_FOR_DELIVERY_YET' USING ERRCODE = 'P0067';
    END IF;
    UPDATE public.orders SET status = 'completed', updated_at = now() WHERE id = p_order_id;
    UPDATE public.riders SET status = 'available' WHERE id = v_rider_id;
  END IF;

  INSERT INTO public.order_status_history (order_id, status, note)
  VALUES (p_order_id, p_new_status, NULL);

  SELECT * INTO v_result FROM public.orders WHERE id = p_order_id;
  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_rider_update_status(UUID, UUID, TEXT) FROM authenticated, anon, public;
