-- Sprint 9: rpc_rider_accept_order(rider_user_id, order_id) -- §8.5's
-- "incoming-assignment ... Accept" step, made real rather than a UI-only
-- gate. Not named as its own RPC anywhere in §5.4's table (only
-- rpc_assign_rider and rpc_rider_update_status are) -- §5.4's own
-- rpc_rider_update_status row doesn't leave room for a distinct
-- pre-ladder "I've seen this and I'm taking it" step, and riders.status
-- has no fourth value between 'available' and 'on_delivery' to represent
-- "assigned, not yet acknowledged" (§4.7's enum, untouched here). Rather
-- than stretch rpc_rider_update_status's own ladder to cover a step that
-- isn't part of the picked_up/out_for_delivery/delivered sequence, this is
-- a small, separate, idempotent RPC -- same "one function, one real
-- invariant" shape as rpc_set_default_address (005).
--
-- What "Accept" actually changes: an order_status_history row
-- ('rider_accepted') and nothing else -- riders.status is already
-- 'on_delivery' from rpc_assign_rider (039), and orders.rider_id is already
-- set. This function's real teeth are enforced downstream: rpc_rider_
-- update_status (042) refuses a 'picked_up' call for any order that has no
-- 'rider_accepted' history row yet, so a rider genuinely must tap Accept
-- before advancing the ladder -- not just a client-side button that could
-- be skipped by calling the status endpoint directly.
--
-- Idempotent: calling this twice for the same order is a silent no-op the
-- second time (no duplicate history row), same discipline as every
-- RPC-of-record in this project.

CREATE OR REPLACE FUNCTION public.rpc_rider_accept_order(
  p_rider_user_id UUID,
  p_order_id      UUID
)
RETURNS public.orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order        public.orders%ROWTYPE;
  v_rider_id     UUID;
  v_already      BOOLEAN;
BEGIN
  SELECT id INTO v_rider_id FROM public.riders WHERE user_id = p_rider_user_id;
  IF v_rider_id IS NULL THEN
    RAISE EXCEPTION 'RIDER_PROFILE_NOT_FOUND' USING ERRCODE = 'P0045';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.rider_id IS DISTINCT FROM v_rider_id THEN
    RAISE EXCEPTION 'ORDER_NOT_ASSIGNED_TO_RIDER' USING ERRCODE = 'P0046';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.order_status_history
    WHERE order_id = p_order_id AND status = 'rider_accepted'
  ) INTO v_already;

  IF NOT v_already THEN
    INSERT INTO public.order_status_history (order_id, status, note)
    VALUES (p_order_id, 'rider_accepted', NULL);
  END IF;

  RETURN v_order;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_rider_accept_order(UUID, UUID) FROM authenticated, anon, public;
