-- Sprint 12: rpc_cancel_order -- SPRINT_PLANNING.md §11's Sprint 12 entry:
-- "a real cancellation flow -- buyer-initiated (before a shop accepts) and
-- shop-initiated (before dispatch/handoff), a legal orders.status transition
-- into 'cancelled' from more than just rpc_place_order's own pre-payment
-- paths" -- plus the ledger reversal (migrations/046) and rider release this
-- same transition has to trigger atomically.
--
-- ===========================================================================
-- THE STATE MACHINE, DECIDED EXPLICITLY (§11 asks for this precisely, same
-- bar every prior sprint's own "decided here, not deferred" section held to)
-- ===========================================================================
--
-- This schema has no distinct "shop accepted" status -- `orders.status`
-- moves pending -> confirmed automatically the instant payment resolves
-- (rpc_confirm_payment, migrations/036, for BOTH payment paths: online via
-- the gateway, pay_at_shop synchronously at placement per that migration's
-- own header). The first status a SHOP ever actually sets by hand is
-- 'preparing' (rpc_shop_advance_order_status, migrations/040). So "before a
-- shop accepts" is defined here as: the order hasn't reached 'preparing'
-- yet. Concretely, by actor:
--
--   BUYER-initiated -- legal only while status IN ('pending', 'confirmed').
--     Once a shop has moved an order to 'preparing' they've started real
--     work (and, for a platform_rider order, the automatic rider search has
--     already run off the 'confirmed' transition, migrations/039) -- a
--     buyer backing out past that point needs to go through the shop, not a
--     unilateral self-serve cancel. Enforced by checking `orders.user_id =
--     p_actor_user_id` (own-order, same ownership check every buyer-facing
--     RPC in this codebase applies) AND the status gate above.
--
--   SHOP-initiated -- legal while status IN ('pending', 'confirmed',
--     'preparing', 'ready_for_pickup') -- i.e. anything before dispatch/
--     handoff: 'out_for_delivery' (a rider or the shop's own delivery
--     person is already moving) and 'completed' are both refused. Gated to
--     shop_team_members membership with member_role IN ('owner','staff')
--     ONLY -- deliberately narrower than rpc_shop_advance_order_status's own
--     "any member_role" bar (§5.3's "advance status" right extends to
--     `delivery`, but voiding an order outright -- with the ledger-reversal
--     and rider-release consequences below -- is an operational/business
--     call, the same tier routes/shopOrders.ts's own manual assign-rider
--     retry already restricts to owner/staff, not every team member).
--
-- Both actors are refused outright once status is 'out_for_delivery' or
-- 'completed' (ORDER_OUT_FOR_DELIVERY / ORDER_ALREADY_COMPLETED), or if the
-- order is already 'cancelled' (ORDER_ALREADY_CANCELLED, not a silent
-- idempotent no-op -- same "tell the truth about what already happened"
-- choice rpc_shop_advance_order_status's own ORDER_ALREADY_FINAL makes,
-- rather than merging "double-tapped my own cancel" and "this is a fresh
-- request" into one response).
--
-- ===========================================================================
-- WHAT ELSE ONE CANCELLATION HAS TO DO, ATOMICALLY, IN THE SAME TRANSACTION
-- ===========================================================================
--
-- (a) orders.status -> 'cancelled', order_status_history logged with which
--     actor cancelled it and why (p_reason, buyer- or shop-typed free text,
--     nullable -- this schema has no reason-code enum anywhere else either).
--
-- (b) Rider release. If `orders.rider_id` is set (only possible for
--     delivery_fulfilled_by='platform_rider' orders that already went
--     through rpc_assign_rider), that rider's own `riders.status` is reset
--     to 'available'. Safe unconditionally at this point in the function:
--     by construction, reaching here means status was NOT 'out_for_delivery'
--     or 'completed', so the rider (if any) was, at most, assigned-and-
--     possibly-accepted but never actually dispatched -- rpc_assign_rider
--     only ever puts one rider `on_delivery` per order, and this order can
--     no longer proceed, so there is no scenario where releasing them here
--     is wrong. `orders.rider_id` itself is deliberately left set, not
--     cleared -- same "the historical record stays, a correction is a new
--     fact layered on top" reasoning migrations/046 gives for ledger rows,
--     applied here to "who was assigned when this was cancelled."
--
-- (c) Ledger reversal (migrations/046). For every existing, not-yet-reversed
--     shop_ledger_entries row on this order (`payout_due` or
--     `commission_due`), insert one mirrored reversal row for the SAME
--     amount, linked via `reverses_entry_id`. Deliberately does NOT
--     recompute the commission/discount math from scratch (subtotal *
--     platform_commission_pct, the discount-absorption second row for
--     pay_at_shop -- rpc_confirm_payment's own header, migrations/036) --
--     mirroring whatever rows actually exist is strictly more correct than
--     re-deriving them a second time, and it naturally covers every real
--     case this project has: an online order (one payout_due to reverse), a
--     pay_at_shop order with no discount (one commission_due), a
--     pay_at_shop order WITH a discount (a commission_due AND a payout_due,
--     both reversed), and an order cancelled before payment ever confirmed
--     (zero ledger rows exist yet, so the loop reverses nothing -- correct,
--     since nothing was ever owed).
--
-- p_actor_user_id, not auth.uid() -- same §5.1 reasoning as every RPC since
-- 005: reached only over the service-role pooler connection.

CREATE OR REPLACE FUNCTION public.rpc_cancel_order(
  p_order_id      UUID,
  p_actor_type    TEXT,
  p_actor_user_id UUID,
  p_reason        TEXT DEFAULT NULL
)
RETURNS public.orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order        public.orders%ROWTYPE;
  v_is_shop_mgr  BOOLEAN;
  v_ledger       RECORD;
  v_reverse_type TEXT;
  v_note         TEXT;
  v_result       public.orders%ROWTYPE;
BEGIN
  IF p_actor_type NOT IN ('buyer', 'shop') THEN
    RAISE EXCEPTION 'INVALID_ACTOR_TYPE' USING ERRCODE = 'P0060';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND' USING ERRCODE = 'P0061';
  END IF;

  -- Authorization checked BEFORE any status check, deliberately -- same
  -- ordering rpc_shop_advance_order_status (migrations/040) already
  -- establishes (membership checked before ORDER_ALREADY_FINAL). Checking
  -- status first would let an unauthorized caller learn "this order is
  -- already cancelled/completed" for an order that isn't theirs at all,
  -- before ever being told they have no business asking -- a minor but
  -- real information leak this ordering avoids for free.
  IF p_actor_type = 'buyer' THEN
    IF v_order.user_id IS DISTINCT FROM p_actor_user_id THEN
      RAISE EXCEPTION 'NOT_ORDER_OWNER' USING ERRCODE = 'P0065';
    END IF;
  ELSE
    SELECT EXISTS(
      SELECT 1 FROM public.shop_team_members
      WHERE shop_id = v_order.shop_id AND user_id = p_actor_user_id AND member_role IN ('owner', 'staff')
    ) INTO v_is_shop_mgr;
    IF NOT v_is_shop_mgr THEN
      RAISE EXCEPTION 'NOT_SHOP_MANAGER' USING ERRCODE = 'P0067';
    END IF;
  END IF;

  IF v_order.status = 'cancelled' THEN
    RAISE EXCEPTION 'ORDER_ALREADY_CANCELLED' USING ERRCODE = 'P0062';
  ELSIF v_order.status = 'completed' THEN
    RAISE EXCEPTION 'ORDER_ALREADY_COMPLETED' USING ERRCODE = 'P0063';
  ELSIF v_order.status = 'out_for_delivery' THEN
    RAISE EXCEPTION 'ORDER_OUT_FOR_DELIVERY' USING ERRCODE = 'P0064';
  END IF;

  IF p_actor_type = 'buyer' THEN
    IF v_order.status NOT IN ('pending', 'confirmed') THEN
      RAISE EXCEPTION 'BUYER_CANCEL_WINDOW_CLOSED' USING ERRCODE = 'P0066';
    END IF;
    v_note := COALESCE('Cancelled by buyer: ' || p_reason, 'Cancelled by buyer');
  ELSE
    -- status is already known to be one of pending/confirmed/preparing/
    -- ready_for_pickup at this point (the three terminal/in-flight statuses
    -- were all refused above) -- every remaining status is legal for a shop.
    v_note := COALESCE('Cancelled by shop: ' || p_reason, 'Cancelled by shop');
  END IF;

  UPDATE public.orders SET status = 'cancelled', updated_at = now() WHERE id = p_order_id;
  INSERT INTO public.order_status_history (order_id, status, note) VALUES (p_order_id, 'cancelled', v_note);

  IF v_order.rider_id IS NOT NULL THEN
    UPDATE public.riders SET status = 'available' WHERE id = v_order.rider_id AND status = 'on_delivery';
    INSERT INTO public.order_status_history (order_id, status, note)
    VALUES (p_order_id, 'rider_released', 'Rider freed back to available -- order cancelled');
  END IF;

  FOR v_ledger IN
    SELECT * FROM public.shop_ledger_entries
    WHERE order_id = p_order_id
      AND entry_type IN ('payout_due', 'commission_due')
      AND id NOT IN (
        SELECT reverses_entry_id FROM public.shop_ledger_entries WHERE reverses_entry_id IS NOT NULL
      )
  LOOP
    v_reverse_type := CASE v_ledger.entry_type
      WHEN 'payout_due' THEN 'payout_reversal'
      ELSE 'commission_reversal'
    END;
    INSERT INTO public.shop_ledger_entries (shop_id, order_id, entry_type, amount, reverses_entry_id)
    VALUES (v_ledger.shop_id, v_ledger.order_id, v_reverse_type, v_ledger.amount, v_ledger.id);
  END LOOP;

  SELECT * INTO v_result FROM public.orders WHERE id = p_order_id;
  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_cancel_order(UUID, TEXT, UUID, TEXT) FROM authenticated, anon, public;
