-- Sprint 8: rpc_confirm_payment -- SPRINT_PLANNING.md §5.4: "verifies the
-- gateway signature, sets order_groups.payment_status='paid', cascades every
-- child orders.status from 'pending' to 'confirmed', and inserts the correct
-- shop_ledger_entries row per shop sub-order -- payout_due for online-paid
-- orders, commission_due for pay_at_shop orders."
--
-- One correction to that sentence, made deliberately and documented here
-- rather than silently: **this function does not verify the gateway
-- signature itself.** Signature verification is HMAC-SHA256 over an
-- HTTP-layer payload (a raw request body for the webhook, an order_id|
-- payment_id string for the client-verify path, §5.4/routes/payments.ts) --
-- Postgres has no HTTP/crypto access to that payload shape without either
-- `pgsodium`/`pg_net`-style plumbing this project doesn't otherwise use, or
-- trusting a value the caller could have fabricated. Same "the Edge Function
-- is the one trust boundary" reasoning §5.1 already draws for `auth.uid()`:
-- lib/payments/razorpay.ts verifies the signature in TypeScript BEFORE
-- calling this RPC at all, and this function trusts its one intended caller
-- completely -- exactly the same relationship rpc_set_default_address (005)
-- has with authMiddleware, extended here to "verified by the gateway adapter"
-- instead of "verified by Supabase Auth." REVOKEd from authenticated/anon
-- below, same as every other RPC in this project (§5.1) -- nothing else can
-- call this and skip the verification step.
--
-- ===========================================================================
-- Two real open questions this sprint had to answer that weren't decided
-- anywhere in SPRINT_PLANNING.md -- both are answered here, not deferred:
-- ===========================================================================
--
-- (1) WHO ABSORBS AN ADMIN-AUTHORED DISCOUNT CODE'S COST? --
-- migrations/031's own header flagged this as the open question Sprint 8
-- would have to answer plainly. Decision: **the platform absorbs it,
-- always, on both payment paths.** Reasoning: migrations/026's header
-- already established that every discount in this project is admin-authored
-- and platform-wide -- no shop ever opts into or authors one (there's no
-- `scope_shop_id`, no shop-side discount-creation flow anywhere in this
-- plan). A shop that had no say in a promo running shouldn't have its own
-- payout or commission bill shrink or grow because of it. Concretely, from
-- each order's own already-stored fields (subtotal = this shop's pre-discount
-- share, discount_value = this shop's allocated slice of the code, per
-- migrations/032's largest-remainder apportionment):
--
--   * ONLINE path (payout_due): computed off `subtotal`, never `total`.
--     The shop is paid exactly what it would have earned with no discount at
--     all, minus its own commission. The platform collected `total` (already
--     net of the discount) from the buyer but pays the shop as if it hadn't
--     applied one -- the difference comes out of the platform's own margin,
--     which can genuinely go negative on a steep discount against a
--     low-commission shop. That is a real, disclosed possibility (see
--     Sprint 8.md), not a bug -- it is what "the platform funds the promo"
--     means in money terms.
--   * PAY_AT_SHOP path (commission_due): computed off `subtotal` too, for
--     the same reason and for internal consistency with the online path --
--     the shop owes commission on the full sale value it delivered,
--     regardless of what the platform chose to discount the buyer's price
--     by. But unlike the online path, the platform never touched this
--     order's money at all -- the shop itself only physically collected
--     `total` (post-discount) from the buyer directly. So if this order
--     carries a nonzero `discount_value`, a SECOND ledger entry is inserted:
--     a `payout_due` for exactly `discount_value` -- the platform separately
--     owing the shop back the promo's cost, using the ledger's existing
--     "platform owes shop" entry type rather than inventing a third one.
--     Net effect, both paths: every shop's ledger behaves as if the
--     discount had never existed from that shop's own point of view: it
--     always nets out to `subtotal - commission`, one way or the other.
--
-- (2) WHEN DOES order_groups.payment_status BECOME 'collected_at_shop'? --
-- Neither §1.4 nor §4.7 names an explicit trigger point (this sprint's own
-- brief said so directly: "at order placement? at a shop marking it picked
-- up/delivered? there's no explicit trigger point named yet"). Decision:
-- **at order placement, synchronously** -- routes/checkout.ts's `POST
-- /v1/orders` calls this RPC itself, immediately after rpc_place_order
-- succeeds, whenever `payment_mode = 'pay_at_shop'` (see that file's own
-- comment). Two real reasons, not just convenience:
--   * There is, by construction, no gateway signal to wait for in this mode
--     at all (§1.4's whole premise: "Proximity collects zero money" here) --
--     so "wait for confirmation" has no event to wait for.
--   * The alternative -- gating on a shop explicitly marking the order
--     "picked up"/"delivered" -- would depend on a shop-side order-status-
--     advance surface (`rpc_shop_advance_order_status`, §5.4) that **does
--     not exist anywhere in this codebase yet**, in any sprint through
--     Sprint 7, and is not scheduled by name in any sprint's own §11 entry
--     either (checked directly, not assumed -- grepping this whole repo for
--     it before writing this decision turns up only its own name in §5.4's
--     table). Making Sprint 8's commission bookkeeping depend on a
--     mechanism that doesn't exist and has no scheduled owner would leave
--     `commission_due` permanently unrecorded for every pay_at_shop order
--     until some future sprint happens to build that surface -- worse for
--     the platform's own revenue visibility (§8.4/§8.6's whole point) than
--     recording the obligation on trust at placement, which is already the
--     trust model §1.4 explicitly accepted for this entire payment mode
--     ("payments is anyways done on shopkeeper's UPI or their payment
--     method" -- the platform was never going to verify the cash changed
--     hands either way). Flagged here plainly: a pay_at_shop order that's
--     later cancelled still leaves its ledger entries in place (nothing in
--     this sprint reverses them on cancellation, since no cancellation flow
--     writes to this table at all yet) -- a known, disclosed gap, not
--     silently swept under the rug.
--
-- ===========================================================================
--
-- Idempotent by construction, locked with SELECT ... FOR UPDATE: calling
-- this twice for the same group (the webhook and a client-triggered
-- verify-payment call both landing, in either order -- routes/payments.ts's
-- own header explains why both exist) is a safe no-op the second time,
-- rather than double-inserting ledger rows or raising. Only a group whose
-- payment_status is currently 'pending' or 'failed' does any real work;
-- 'paid'/'collected_at_shop' return immediately.

CREATE OR REPLACE FUNCTION public.rpc_confirm_payment(
  p_group_id           UUID,
  p_payment_gateway    TEXT DEFAULT NULL,
  p_gateway_order_id   TEXT DEFAULT NULL,
  p_gateway_payment_id TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_group      public.order_groups%ROWTYPE;
  v_new_status TEXT;
  v_order      public.orders%ROWTYPE;
  v_commission INTEGER;
  v_note       TEXT;
BEGIN
  SELECT * INTO v_group FROM public.order_groups WHERE id = p_group_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_GROUP_NOT_FOUND' USING ERRCODE = 'P0020';
  END IF;

  -- Idempotent no-op: already resolved by an earlier call (webhook or
  -- client-verify, whichever landed first -- see header).
  IF v_group.payment_status NOT IN ('pending', 'failed') THEN
    RETURN v_group.id;
  END IF;

  IF v_group.payment_mode = 'online' THEN
    IF p_gateway_payment_id IS NULL THEN
      RAISE EXCEPTION 'GATEWAY_PAYMENT_ID_REQUIRED' USING ERRCODE = 'P0021';
    END IF;
    v_new_status := 'paid';
    v_note       := 'Payment confirmed';
  ELSIF v_group.payment_mode = 'pay_at_shop' THEN
    v_new_status := 'collected_at_shop';
    v_note       := 'Order confirmed -- pay at shop';
  ELSE
    -- Unreachable given order_groups' own CHECK constraint, but this
    -- function doesn't trust that alone (§5.1's general discipline).
    RAISE EXCEPTION 'INVALID_PAYMENT_MODE' USING ERRCODE = 'P0022';
  END IF;

  UPDATE public.order_groups
  SET payment_status     = v_new_status,
      payment_gateway    = COALESCE(p_payment_gateway, payment_gateway),
      gateway_order_id   = COALESCE(p_gateway_order_id, gateway_order_id),
      gateway_payment_id = COALESCE(p_gateway_payment_id, gateway_payment_id)
  WHERE id = p_group_id;

  -- Cascade every still-pending child order to 'confirmed', logging history
  -- and inserting this order's ledger obligation(s) in the same loop --
  -- everything each order needs (subtotal/discount_value/
  -- platform_commission_pct) is already snapshotted on the row (§4.8).
  FOR v_order IN
    UPDATE public.orders
    SET status = 'confirmed', updated_at = now()
    WHERE order_group_id = p_group_id AND status = 'pending'
    RETURNING *
  LOOP
    INSERT INTO public.order_status_history (order_id, status, note)
    VALUES (v_order.id, 'confirmed', v_note);

    v_commission := ROUND(v_order.subtotal * v_order.platform_commission_pct / 100.0)::integer;

    IF v_new_status = 'paid' THEN
      -- (1) above: computed off subtotal, discount never touches this.
      INSERT INTO public.shop_ledger_entries (shop_id, order_id, entry_type, amount)
      VALUES (v_order.shop_id, v_order.id, 'payout_due', GREATEST(v_order.subtotal - v_commission, 0));
    ELSE
      INSERT INTO public.shop_ledger_entries (shop_id, order_id, entry_type, amount)
      VALUES (v_order.shop_id, v_order.id, 'commission_due', v_commission);

      IF v_order.discount_value > 0 THEN
        INSERT INTO public.shop_ledger_entries (shop_id, order_id, entry_type, amount)
        VALUES (v_order.shop_id, v_order.id, 'payout_due', v_order.discount_value);
      END IF;
    END IF;
  END LOOP;

  RETURN p_group_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_confirm_payment(UUID, TEXT, TEXT, TEXT) FROM authenticated, anon, public;
