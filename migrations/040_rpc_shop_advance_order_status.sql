-- Sprint 9: rpc_shop_advance_order_status(order_id, user_id, new_status) --
-- SPRINT_PLANNING.md §5.4: "shop team (owner/staff/delivery per §5.3),
-- validates the status transition is legal for this shop's own order,
-- writes order_status_history."
--
-- ===========================================================================
-- WHY THIS IS IN SPRINT 9 AT ALL -- Sprint 8.md's own closing section flagged
-- this RPC as having no scheduled sprint anywhere in §11's plan, and asked
-- this sprint to decide explicitly rather than leave it unaddressed a second
-- time. Checked directly, not assumed: §11's Sprint 9 entry names
-- rpc_assign_rider and the RIDER's own status ladder
-- (rpc_rider_update_status) by name, but never this one. Decision:
-- **in scope for this sprint, not deferred again** -- not scope creep, a
-- load-bearing dependency this sprint's own rider ladder cannot work
-- without. rpc_rider_update_status (042) requires an order to already be
-- 'ready_for_pickup' before a rider can mark it 'picked_up' -- with no way
-- for ANY order to ever reach 'ready_for_pickup' (orders.status has sat at
-- 'confirmed' forever, in every sprint through Sprint 8, since nothing
-- writes past it), this sprint's own exit criteria ("the buyer sees live
-- status changes") would have nothing to show beyond the one
-- rider-assignment event. Building it now, small and exactly to §5.4's own
-- spec, closes a gap two sprints have now pointed at rather than leaving a
-- third session to rediscover it.
-- ===========================================================================
--
-- Legal forward-only ladder, by fulfillment shape -- orders.status' own
-- CHECK constraint (migrations/028, untouched, "no additions at all") is the
-- ceiling on what's representable; this function is what actually gates
-- which of those values a SHOP may set, and when:
--   pending      -> (never shop-settable; rpc_confirm_payment's own cascade,
--                     Sprint 8, is the only path into 'confirmed')
--   confirmed    -> preparing        (any order, any fulfillment shape)
--   preparing    -> ready_for_pickup (any order, any fulfillment shape --
--                     "ready" means the shop is done, regardless of who
--                     collects it next)
--   ready_for_pickup -> completed    (ONLY fulfillment_type = 'pickup' --
--                     the buyer collects it themselves; there's no rider or
--                     shop-delivery leg left to run)
--   ready_for_pickup -> out_for_delivery -> completed
--                     (ONLY delivery_fulfilled_by = 'shop' -- the shop's own
--                     delivery person, a shop_team_members row with
--                     member_role='delivery', §5.3's "status advance only"
--                     right -- uses THIS RPC, not rpc_rider_update_status,
--                     because a self-delivery order was never assigned a
--                     `riders` row to begin with)
--   ready_for_pickup -> [refused]     for delivery_fulfilled_by =
--                     'platform_rider' orders -- from here on, a real
--                     Proximity rider owns the remaining ladder through
--                     rpc_rider_update_status (042), not the shop. Refusing
--                     this explicitly (PLATFORM_RIDER_HANDLES_REMAINING_
--                     STATUS below) rather than silently allowing a shop to
--                     race a rider's own status writes on the same order.
--
-- Deliberately NOT built here, same "don't build a mechanism a decision
-- doesn't need yet" discipline as every prior cut in this project:
-- cancellation from any state (no cancellation flow exists anywhere in this
-- codebase, Sprint 7/8 both flagged this and it's still open -- adding a
-- 'cancelled' transition here without the ledger-reversal/refund logic that
-- would need to accompany it would be a half-built feature, worse than none).
--
-- p_user_id, not auth.uid() -- same reasoning as every RPC since 005: this
-- function is only ever reached over the service-role pooler connection,
-- where auth.uid() is always NULL. The Edge Function route (routes/
-- shopOrders.ts) has already authenticated the caller; this function
-- additionally re-verifies shop-team membership itself (a cross-table check
-- a bare authMiddleware pass can't express) rather than trusting the route
-- alone -- same belt-and-suspenders discipline rpc_confirm_payment's own
-- header describes for its one intended caller.

CREATE OR REPLACE FUNCTION public.rpc_shop_advance_order_status(
  p_order_id   UUID,
  p_user_id    UUID,
  p_new_status TEXT
)
RETURNS public.orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order     public.orders%ROWTYPE;
  v_is_member BOOLEAN;
  v_result    public.orders%ROWTYPE;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND' USING ERRCODE = 'P0050';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.shop_team_members
    WHERE shop_id = v_order.shop_id AND user_id = p_user_id
  ) INTO v_is_member;
  IF NOT v_is_member THEN
    RAISE EXCEPTION 'NOT_SHOP_TEAM_MEMBER' USING ERRCODE = 'P0051';
  END IF;

  IF v_order.status IN ('cancelled', 'completed') THEN
    RAISE EXCEPTION 'ORDER_ALREADY_FINAL' USING ERRCODE = 'P0052';
  END IF;

  IF p_new_status = 'preparing' THEN
    IF v_order.status <> 'confirmed' THEN
      RAISE EXCEPTION 'INVALID_STATUS_TRANSITION' USING ERRCODE = 'P0053';
    END IF;

  ELSIF p_new_status = 'ready_for_pickup' THEN
    IF v_order.status <> 'preparing' THEN
      RAISE EXCEPTION 'INVALID_STATUS_TRANSITION' USING ERRCODE = 'P0053';
    END IF;

  ELSIF p_new_status = 'out_for_delivery' THEN
    -- A pickup order has no "out for delivery" leg at all -- checked FIRST
    -- and separately from the platform_rider check below, so a shop
    -- mistakenly calling this on a pickup order gets a plain "not valid"
    -- rather than a misleading "a rider handles this" (caught during this
    -- sprint's own second verification pass -- the first draft folded both
    -- conditions into one, which mislabeled the pickup case).
    IF v_order.fulfillment_type <> 'delivery' THEN
      RAISE EXCEPTION 'INVALID_STATUS_TRANSITION' USING ERRCODE = 'P0053';
    END IF;
    -- Self-delivery only from here -- a platform_rider order's remaining
    -- ladder belongs to rpc_rider_update_status (042), not this RPC
    -- (header, above).
    IF v_order.delivery_fulfilled_by = 'platform_rider' THEN
      RAISE EXCEPTION 'PLATFORM_RIDER_HANDLES_REMAINING_STATUS' USING ERRCODE = 'P0055';
    END IF;
    IF v_order.delivery_fulfilled_by <> 'shop' THEN
      RAISE EXCEPTION 'INVALID_STATUS_TRANSITION' USING ERRCODE = 'P0053';
    END IF;
    IF v_order.status <> 'ready_for_pickup' THEN
      RAISE EXCEPTION 'INVALID_STATUS_TRANSITION' USING ERRCODE = 'P0053';
    END IF;

  ELSIF p_new_status = 'completed' THEN
    IF v_order.fulfillment_type = 'pickup' THEN
      IF v_order.status <> 'ready_for_pickup' THEN
        RAISE EXCEPTION 'INVALID_STATUS_TRANSITION' USING ERRCODE = 'P0053';
      END IF;
    ELSIF v_order.delivery_fulfilled_by = 'shop' THEN
      IF v_order.status <> 'out_for_delivery' THEN
        RAISE EXCEPTION 'INVALID_STATUS_TRANSITION' USING ERRCODE = 'P0053';
      END IF;
    ELSE
      -- delivery_fulfilled_by = 'platform_rider' -- a real Proximity rider
      -- owns this order's completion via rpc_rider_update_status's own
      -- 'delivered' step, not this RPC.
      RAISE EXCEPTION 'PLATFORM_RIDER_HANDLES_REMAINING_STATUS' USING ERRCODE = 'P0055';
    END IF;

  ELSE
    RAISE EXCEPTION 'INVALID_NEW_STATUS' USING ERRCODE = 'P0056';
  END IF;

  UPDATE public.orders SET status = p_new_status, updated_at = now() WHERE id = p_order_id;

  INSERT INTO public.order_status_history (order_id, status, note)
  VALUES (p_order_id, p_new_status, NULL);

  SELECT * INTO v_result FROM public.orders WHERE id = p_order_id;
  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_shop_advance_order_status(UUID, UUID, TEXT) FROM authenticated, anon, public;
