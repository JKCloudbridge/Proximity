-- Sprint 7: rpc_place_order -- SPRINT_PLANNING.md §5.4's biggest named RPC:
-- "Groups cart by shop -> validates each shop's chosen slot/mode against
-- shops.delivery_mode/shop_business_hours -> computes per-shop subtotal/
-- discount/delivery_fee (§4.6/§4.8) -> creates one order_groups + N orders +
-- order_items in one transaction -> for pay_at_shop, refuses if any
-- shop-group uses platform_rider (§1.4)."
--
-- This is the single most important reason §5.1 insists cross-table business
-- logic lives in a SECURITY DEFINER function rather than sequential client
-- statements: a checkout that half-succeeded -- a group row with no orders, a
-- cart cleared without an order, per-shop totals that don't add up to the one
-- amount the buyer was charged -- is not a bug you can apologise your way out
-- of. Everything below happens in one transaction or none of it does.
--
-- p_user_id is explicit, not auth.uid(), same as every other RPC here (§5.1).
-- Note it takes p_user_id and derives the cart from it, rather than taking
-- the `cart_id` §5.4's signature sketch names: carts.user_id is UNIQUE
-- (migrations/022), so the cart is a pure function of the user, and an
-- explicit cart_id parameter would be a cross-user hole the moment anything
-- ever called this with a cart id it didn't own. Deriving it costs one
-- lookup and removes the question entirely.
--
-- p_fulfillment is a JSONB array, one element per shop in the cart, same
-- "related fields travel as JSONB rather than widening the signature"
-- convention rpc_create_shop (014) established:
--   [{ "shop_id": uuid, "fulfillment_type": "pickup"|"delivery",
--      "delivery_fulfilled_by": "shop"|"platform_rider"|null,
--      "slot_start": timestamptz, "slot_end": timestamptz }, ...]
--
-- Error codes are raised as the first token of the exception message so the
-- Edge Function can map them to typed responses by substring, exactly like
-- rpc_set_default_address (005) and rpc_add_to_cart (024) already do --
-- §9's "typed-exception-from-error-code pattern," extended here with the
-- PAY_AT_SHOP_NOT_ALLOWED code that section names by hand.
--
-- Deliberately NOT done here, each for a stated reason:
--   * No stock_qty decrement. An order that has been *placed* but not yet
--     *paid* (payment is Sprint 8) holds nothing, and this project has no
--     reservation/expiry concept to release held stock if payment never
--     happens. §1.7/§4.5 also treat stock_qty as the deliberately
--     unreliable number and stock_status as the real signal -- which this
--     function does check. If stock ever should move, Sprint 8's
--     rpc_confirm_payment is the honest place for it.
--   * No shop_ledger_entries rows. §11 puts ledger insertion in Sprint 8,
--     and an unpaid order owes nobody anything yet. See migrations/031's
--     header for the real open question that sprint has to answer.
--   * No rider assignment. rpc_assign_rider is Sprint 9 (§11); orders land
--     with rider_id NULL even when delivery_fulfilled_by='platform_rider'.
--
-- Timezone: uses 'Asia/Kolkata' via AT TIME ZONE rather than the hardcoded
-- +5:30 offset lib/slots.ts carries. Both agree for India (no DST), but the
-- named zone is the more correct of the two -- see lib/slots.ts's own header
-- for why that file has no data model to look a zone up from either.

CREATE OR REPLACE FUNCTION public.rpc_place_order(
  p_user_id       UUID,
  p_fulfillment   JSONB,
  p_address_id    UUID,
  p_payment_mode  TEXT,
  p_discount_code TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_cart_id          UUID;
  v_group_id         UUID;
  v_order_id         UUID;
  v_shop_count       INTEGER;
  v_entry_count      INTEGER;
  v_distinct_entries INTEGER;
  v_subtotal         INTEGER := 0;
  v_shop_subtotal    INTEGER;
  v_discount_total   INTEGER := 0;
  v_shop_discount    INTEGER;
  v_shop_ids         UUID[];
  v_shop_discounts   INTEGER[];
  v_delivery_total   INTEGER := 0;
  v_shop_fee         INTEGER;
  v_platform_fee     INTEGER := 0;
  v_group_total      INTEGER;
  v_orders_total     INTEGER := 0;
  v_free_shipping    BOOLEAN := false;
  v_slot_minutes     INTEGER := 120;
  v_discount         public.discounts%ROWTYPE;
  v_shop             public.shops%ROWTYPE;
  v_hours            public.shop_business_hours%ROWTYPE;
  v_entry            JSONB;
  v_shop_id          UUID;
  v_ftype            TEXT;
  v_fulfilled_by     TEXT;
  v_slot_start       TIMESTAMPTZ;
  v_slot_end         TIMESTAMPTZ;
  v_local_start      TIMESTAMP;
  v_local_end        TIMESTAMP;
  v_day              DATE;
  v_settings         JSONB;
BEGIN
  IF p_payment_mode NOT IN ('online', 'pay_at_shop') THEN
    RAISE EXCEPTION 'INVALID_PAYMENT_MODE' USING ERRCODE = 'P0001';
  END IF;

  -- ---------------------------------------------------------------------
  -- 1. Cart
  -- ---------------------------------------------------------------------
  SELECT id INTO v_cart_id FROM public.carts WHERE user_id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CART_EMPTY' USING ERRCODE = 'P0002';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.cart_items WHERE cart_id = v_cart_id) THEN
    RAISE EXCEPTION 'CART_EMPTY' USING ERRCODE = 'P0002';
  END IF;

  -- Every line must still be purchasable *right now* -- the cart screen
  -- flags these (routes/cart.ts's isAvailable), but a buyer can sit on a
  -- checkout screen while a shop deactivates a variant underneath them.
  IF EXISTS (
    SELECT 1
    FROM public.cart_items ci
    JOIN public.product_variants pv ON pv.id = ci.variant_id
    JOIN public.products p ON p.id = pv.product_id
    JOIN public.shops s ON s.id = p.shop_id
    WHERE ci.cart_id = v_cart_id
      AND (pv.is_active = false
           OR pv.stock_status = 'out_of_stock'
           OR p.is_active = false
           OR s.status <> 'approved')
  ) THEN
    RAISE EXCEPTION 'CART_HAS_UNAVAILABLE_ITEMS' USING ERRCODE = 'P0003';
  END IF;

  -- ---------------------------------------------------------------------
  -- 2. The fulfillment array must describe every shop in the cart, exactly
  --    once each -- no missing group (an order nobody agreed to fulfil), no
  --    extra group (an order for a shop with nothing in it), no duplicate
  --    (which would silently leave another shop unhandled while still
  --    matching on count alone).
  -- ---------------------------------------------------------------------
  SELECT COUNT(DISTINCT p.shop_id) INTO v_shop_count
  FROM public.cart_items ci
  JOIN public.product_variants pv ON pv.id = ci.variant_id
  JOIN public.products p ON p.id = pv.product_id
  WHERE ci.cart_id = v_cart_id;

  SELECT COUNT(*), COUNT(DISTINCT e->>'shop_id')
    INTO v_entry_count, v_distinct_entries
  FROM jsonb_array_elements(p_fulfillment) e;

  IF v_entry_count <> v_shop_count OR v_distinct_entries <> v_shop_count THEN
    RAISE EXCEPTION 'SHOP_GROUP_MISMATCH' USING ERRCODE = 'P0004';
  END IF;

  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_fulfillment) e
    WHERE (e->>'shop_id')::uuid NOT IN (
      SELECT DISTINCT p.shop_id
      FROM public.cart_items ci
      JOIN public.product_variants pv ON pv.id = ci.variant_id
      JOIN public.products p ON p.id = pv.product_id
      WHERE ci.cart_id = v_cart_id
    )
  ) THEN
    RAISE EXCEPTION 'SHOP_GROUP_MISMATCH' USING ERRCODE = 'P0004';
  END IF;

  -- ---------------------------------------------------------------------
  -- 3. §1.4/§5.4: pay-at-shop is only legal when no platform rider is
  --    involved anywhere in the checkout. A rider has no business
  --    collecting a shop's cash on that shop's behalf.
  -- ---------------------------------------------------------------------
  IF p_payment_mode = 'pay_at_shop' AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_fulfillment) e
    WHERE e->>'delivery_fulfilled_by' = 'platform_rider'
  ) THEN
    RAISE EXCEPTION 'PAY_AT_SHOP_NOT_ALLOWED' USING ERRCODE = 'P0005';
  END IF;

  -- ---------------------------------------------------------------------
  -- 4. Platform settings: slot granularity (§4.6) + the admin-controlled
  --    rider delivery fee (§1.3 -- the shop never sets this).
  -- ---------------------------------------------------------------------
  SELECT value INTO v_settings FROM public.platform_settings WHERE key = 'slot_window';
  IF FOUND AND v_settings ? 'slot_minutes' THEN
    v_slot_minutes := (v_settings->>'slot_minutes')::integer;
  END IF;

  SELECT value INTO v_settings FROM public.platform_settings WHERE key = 'platform_rider_delivery_fee';
  IF FOUND AND v_settings ? 'amount_paise' THEN
    v_platform_fee := (v_settings->>'amount_paise')::integer;
  END IF;

  -- ---------------------------------------------------------------------
  -- 5. Validate every group, and accumulate the group-level money.
  --    Validation happens entirely before any INSERT so a rejected checkout
  --    never half-writes (the surrounding transaction would roll it back
  --    anyway -- this is for clarity, not correctness).
  -- ---------------------------------------------------------------------
  FOR v_entry IN SELECT * FROM jsonb_array_elements(p_fulfillment) LOOP
    v_shop_id      := (v_entry->>'shop_id')::uuid;
    v_ftype        := v_entry->>'fulfillment_type';
    v_fulfilled_by := v_entry->>'delivery_fulfilled_by';
    v_slot_start   := (v_entry->>'slot_start')::timestamptz;
    v_slot_end     := (v_entry->>'slot_end')::timestamptz;

    SELECT * INTO v_shop FROM public.shops WHERE id = v_shop_id;
    IF NOT FOUND OR v_shop.status <> 'approved' THEN
      RAISE EXCEPTION 'SHOP_NOT_AVAILABLE %', v_shop_id USING ERRCODE = 'P0006';
    END IF;

    IF v_ftype NOT IN ('pickup', 'delivery') THEN
      RAISE EXCEPTION 'INVALID_FULFILLMENT_TYPE %', v_shop_id USING ERRCODE = 'P0007';
    END IF;

    -- The shop must actually offer what was chosen (§4.4's own columns).
    IF v_ftype = 'pickup' AND NOT v_shop.supports_pickup THEN
      RAISE EXCEPTION 'FULFILLMENT_NOT_SUPPORTED %', v_shop_id USING ERRCODE = 'P0007';
    END IF;
    IF v_ftype = 'delivery' AND NOT v_shop.supports_delivery THEN
      RAISE EXCEPTION 'FULFILLMENT_NOT_SUPPORTED %', v_shop_id USING ERRCODE = 'P0007';
    END IF;

    -- §1.3's delivery_mode contract: 'self' shops deliver their own orders,
    -- 'platform' shops always hand off to a Proximity rider, 'both' shops
    -- choose per order. Anything else is a client sending a combination the
    -- shop never agreed to.
    IF v_ftype = 'pickup' THEN
      IF v_fulfilled_by IS NOT NULL THEN
        RAISE EXCEPTION 'DELIVERY_MODE_MISMATCH %', v_shop_id USING ERRCODE = 'P0008';
      END IF;
    ELSE
      IF v_fulfilled_by IS NULL
         OR v_fulfilled_by NOT IN ('shop', 'platform_rider')
         OR (v_shop.delivery_mode = 'self' AND v_fulfilled_by <> 'shop')
         OR (v_shop.delivery_mode = 'platform' AND v_fulfilled_by <> 'platform_rider') THEN
        RAISE EXCEPTION 'DELIVERY_MODE_MISMATCH %', v_shop_id USING ERRCODE = 'P0008';
      END IF;

      -- §7.4 step 2: one address covers every delivery group in the
      -- checkout, and it has to actually belong to the buyer.
      IF p_address_id IS NULL THEN
        RAISE EXCEPTION 'ADDRESS_REQUIRED' USING ERRCODE = 'P0009';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM public.addresses WHERE id = p_address_id AND user_id = p_user_id) THEN
        RAISE EXCEPTION 'ADDRESS_NOT_OWNED' USING ERRCODE = 'P0009';
      END IF;
    END IF;

    -- Slot validation (§4.6/§5.4). The generation endpoint
    -- (GET /v1/shops/:id/fulfillment-slots) only ever offers slots that
    -- satisfy all of this -- but the endpoint is a convenience, not the
    -- enforcement, and a client can post any two timestamps it likes.
    IF v_slot_start IS NULL OR v_slot_end IS NULL THEN
      RAISE EXCEPTION 'SLOT_INVALID %', v_shop_id USING ERRCODE = 'P0010';
    END IF;
    IF v_slot_start < now() THEN
      RAISE EXCEPTION 'SLOT_IN_PAST %', v_shop_id USING ERRCODE = 'P0010';
    END IF;
    IF v_slot_end <> v_slot_start + make_interval(mins => v_slot_minutes) THEN
      RAISE EXCEPTION 'SLOT_INVALID %', v_shop_id USING ERRCODE = 'P0010';
    END IF;

    v_local_start := v_slot_start AT TIME ZONE 'Asia/Kolkata';
    v_local_end   := v_slot_end   AT TIME ZONE 'Asia/Kolkata';
    v_day         := v_local_start::date;

    IF EXISTS (SELECT 1 FROM public.shop_blackout_dates b WHERE b.shop_id = v_shop_id AND b.date = v_day) THEN
      RAISE EXCEPTION 'SLOT_BLACKED_OUT %', v_shop_id USING ERRCODE = 'P0010';
    END IF;

    SELECT * INTO v_hours
    FROM public.shop_business_hours h
    WHERE h.shop_id = v_shop_id
      AND h.weekday = EXTRACT(DOW FROM v_local_start)::smallint;

    IF NOT FOUND OR v_hours.is_closed OR v_hours.opens_at IS NULL OR v_hours.closes_at IS NULL THEN
      RAISE EXCEPTION 'SLOT_OUTSIDE_HOURS %', v_shop_id USING ERRCODE = 'P0010';
    END IF;

    -- Compared as full local timestamps rather than raw ::time values, so a
    -- slot running past midnight can't wrap around to 00:xx and accidentally
    -- compare as "before closing" (§1.6's window ends at 24:00, and
    -- shop_business_hours.closes_at can't hold 24:00 -- see lib/slots.ts).
    IF v_local_start < (v_day + v_hours.opens_at) OR v_local_end > (v_day + v_hours.closes_at) THEN
      RAISE EXCEPTION 'SLOT_OUTSIDE_HOURS %', v_shop_id USING ERRCODE = 'P0010';
    END IF;

    -- This shop's share of the cart.
    SELECT COALESCE(SUM(ci.quantity * pv.price), 0) INTO v_shop_subtotal
    FROM public.cart_items ci
    JOIN public.product_variants pv ON pv.id = ci.variant_id
    JOIN public.products p ON p.id = pv.product_id
    WHERE ci.cart_id = v_cart_id AND p.shop_id = v_shop_id;

    -- §4.4's min_order_value, enforced for the first time here -- the column
    -- has existed since Sprint 2 with nothing reading it.
    IF v_shop_subtotal < v_shop.min_order_value THEN
      RAISE EXCEPTION 'MIN_ORDER_NOT_MET %', v_shop_id USING ERRCODE = 'P0011';
    END IF;

    v_subtotal := v_subtotal + v_shop_subtotal;

    IF v_fulfilled_by = 'platform_rider' THEN
      v_delivery_total := v_delivery_total + v_platform_fee;
    END IF;
  END LOOP;

  -- ---------------------------------------------------------------------
  -- 6. Discount (§11's "discounts engine wired"). Code-based only this
  --    sprint -- product/quantity-scoped auto-discounts are tied to the
  --    progress banner §11 explicitly keeps hidden (see migrations/026).
  -- ---------------------------------------------------------------------
  IF p_discount_code IS NOT NULL AND length(trim(p_discount_code)) > 0 THEN
    SELECT * INTO v_discount FROM public.discounts WHERE code = upper(trim(p_discount_code));

    IF NOT FOUND
       OR NOT v_discount.is_active
       OR (v_discount.starts_at IS NOT NULL AND v_discount.starts_at > now())
       OR (v_discount.expires_at IS NOT NULL AND v_discount.expires_at < now())
       OR (v_discount.max_uses IS NOT NULL AND v_discount.uses_count >= v_discount.max_uses) THEN
      RAISE EXCEPTION 'DISCOUNT_INVALID' USING ERRCODE = 'P0012';
    END IF;

    IF v_subtotal < v_discount.min_order_value THEN
      RAISE EXCEPTION 'DISCOUNT_MIN_ORDER_NOT_MET' USING ERRCODE = 'P0012';
    END IF;

    IF v_discount.type = 'percent' THEN
      v_discount_total := ROUND(v_subtotal * v_discount.value / 100.0)::integer;
    ELSIF v_discount.type = 'flat' THEN
      v_discount_total := LEAST(v_discount.value, v_subtotal);
    ELSIF v_discount.type = 'free_shipping' THEN
      -- Waives the rider fee rather than cutting the subtotal. Harmless on a
      -- checkout that has no platform-rider group at all (§1.3: nothing else
      -- ever carries a fee), which is also why it isn't refused there.
      v_free_shipping  := true;
      v_delivery_total := 0;
      v_discount_total := 0;
    END IF;

    v_discount_total := LEAST(v_discount_total, v_subtotal);
  END IF;

  v_group_total := v_subtotal - v_discount_total + v_delivery_total;

  -- ---------------------------------------------------------------------
  -- 6b. Per-shop discount allocation, via largest-remainder apportionment
  --     -- computed once, into two parallel arrays keyed by shop_id.
  --
  --     Caught during this sprint's own implementation, not after: a naive
  --     "each shop gets its proportional share, rounded, and the last shop
  --     absorbs whatever's left" scheme can drive that last shop's own
  --     discount NEGATIVE once enough shops are in one cart for per-shop
  --     rounding to compound past the total (e.g. three shops whose
  --     proportional shares each round up by close to half a paisa apiece
  --     can together overshoot the total by more than one shop's own exact
  --     share). The buyer's own total is still correct either way -- the
  --     bug was purely in how it got divided up across shops -- but a
  --     negative discount_value on one shop's own order row is real,
  --     visible wrongness that Sprint 8's ledger math would inherit
  --     downstream. Largest-remainder apportionment (used for exactly this
  --     class of problem in real-world seat/tax apportionment) can't
  --     produce that: floor each shop's exact share (always >= 0), then
  --     hand the leftover (always between 0 and shop_count-1, since the
  --     exact shares already sum to v_discount_total) one paisa each to the
  --     shops with the largest fractional remainder. Sums to exactly
  --     v_discount_total by construction; no share can go negative.
  -- ---------------------------------------------------------------------
  IF v_discount_total > 0 THEN
    WITH subtotals AS (
      SELECT p.shop_id, SUM(ci.quantity * pv.price) AS subtotal
      FROM public.cart_items ci
      JOIN public.product_variants pv ON pv.id = ci.variant_id
      JOIN public.products p ON p.id = pv.product_id
      WHERE ci.cart_id = v_cart_id
      GROUP BY p.shop_id
    ),
    computed AS (
      SELECT
        shop_id,
        floor(v_discount_total * subtotal::numeric / v_subtotal)::integer AS floor_share,
        (v_discount_total * subtotal::numeric / v_subtotal)
          - floor(v_discount_total * subtotal::numeric / v_subtotal) AS remainder
      FROM subtotals
    ),
    ranked AS (
      SELECT
        shop_id,
        floor_share,
        SUM(floor_share) OVER () AS total_floor,
        ROW_NUMBER() OVER (ORDER BY remainder DESC, shop_id) AS rn
      FROM computed
    )
    SELECT
      ARRAY_AGG(shop_id ORDER BY shop_id),
      ARRAY_AGG(floor_share + CASE WHEN rn <= (v_discount_total - total_floor) THEN 1 ELSE 0 END ORDER BY shop_id)
    INTO v_shop_ids, v_shop_discounts
    FROM ranked;
  END IF;

  -- ---------------------------------------------------------------------
  -- 7. One order_groups row -- the single amount the buyer is charged.
  -- ---------------------------------------------------------------------
  INSERT INTO public.order_groups (
    user_id, payment_mode, discount_id, subtotal, discount_value, delivery_fee_total, total, payment_status
  ) VALUES (
    p_user_id, p_payment_mode,
    CASE WHEN v_discount.id IS NOT NULL THEN v_discount.id ELSE NULL END,
    v_subtotal, v_discount_total, v_delivery_total, v_group_total, 'pending'
  )
  RETURNING id INTO v_group_id;

  -- ---------------------------------------------------------------------
  -- 8. One orders row per shop, + its items, + its first status-history
  --    entry. Each shop's discount share comes from the arrays step 6b
  --    already computed and proved sum to exactly v_discount_total -- no
  --    per-shop rounding logic lives in this loop at all anymore.
  -- ---------------------------------------------------------------------
  FOR v_entry IN SELECT * FROM jsonb_array_elements(p_fulfillment) LOOP
    v_shop_id      := (v_entry->>'shop_id')::uuid;
    v_ftype        := v_entry->>'fulfillment_type';
    v_fulfilled_by := v_entry->>'delivery_fulfilled_by';
    v_slot_start   := (v_entry->>'slot_start')::timestamptz;
    v_slot_end     := (v_entry->>'slot_end')::timestamptz;

    SELECT * INTO v_shop FROM public.shops WHERE id = v_shop_id;

    SELECT COALESCE(SUM(ci.quantity * pv.price), 0) INTO v_shop_subtotal
    FROM public.cart_items ci
    JOIN public.product_variants pv ON pv.id = ci.variant_id
    JOIN public.products p ON p.id = pv.product_id
    WHERE ci.cart_id = v_cart_id AND p.shop_id = v_shop_id;

    IF v_discount_total = 0 THEN
      v_shop_discount := 0;
    ELSE
      v_shop_discount := v_shop_discounts[array_position(v_shop_ids, v_shop_id)];
    END IF;

    IF v_fulfilled_by = 'platform_rider' AND NOT v_free_shipping THEN
      v_shop_fee := v_platform_fee;
    ELSE
      v_shop_fee := 0;   -- pickup, or a shop delivering its own order (§1.3)
    END IF;

    INSERT INTO public.orders (
      order_group_id, user_id, shop_id, fulfillment_type, delivery_fulfilled_by, address_id,
      slot_start, slot_end, status, subtotal, discount_value, delivery_fee,
      platform_commission_pct, total
    ) VALUES (
      v_group_id, p_user_id, v_shop_id, v_ftype, v_fulfilled_by,
      CASE WHEN v_ftype = 'delivery' THEN p_address_id ELSE NULL END,
      v_slot_start, v_slot_end, 'pending', v_shop_subtotal, v_shop_discount, v_shop_fee,
      v_shop.platform_commission_pct,
      v_shop_subtotal - v_shop_discount + v_shop_fee
    )
    RETURNING id INTO v_order_id;

    v_orders_total := v_orders_total + (v_shop_subtotal - v_shop_discount + v_shop_fee);

    -- §9's immutable order-item snapshot: name/unit/price are copied, never
    -- joined live afterwards (see migrations/029's header).
    INSERT INTO public.order_items (order_id, variant_id, product_name, variant_name, quantity, unit_price)
    SELECT v_order_id, ci.variant_id, p.name,
           trim_scale(pv.unit_value)::text || ' ' || pv.unit_label,
           ci.quantity, pv.price
    FROM public.cart_items ci
    JOIN public.product_variants pv ON pv.id = ci.variant_id
    JOIN public.products p ON p.id = pv.product_id
    WHERE ci.cart_id = v_cart_id AND p.shop_id = v_shop_id;

    INSERT INTO public.order_status_history (order_id, status, note)
    VALUES (v_order_id, 'pending', 'Order placed');
  END LOOP;

  -- ---------------------------------------------------------------------
  -- 9. The invariant that makes the whole "one charge, N shops" model
  --    honest: what the buyer pays must equal the sum of what the shops are
  --    each recorded as owed. Asserted rather than assumed -- if the
  --    allocation math above ever drifts, this fails the transaction
  --    instead of silently shipping mismatched money.
  -- ---------------------------------------------------------------------
  IF v_orders_total <> v_group_total THEN
    RAISE EXCEPTION 'ORDER_TOTAL_MISMATCH group=% orders=%', v_group_total, v_orders_total USING ERRCODE = 'P0013';
  END IF;

  -- ---------------------------------------------------------------------
  -- 10. Burn the discount use, clear the cart, done. The carts row itself
  --     stays (one per user, migrations/022) -- only its lines go.
  -- ---------------------------------------------------------------------
  IF v_discount.id IS NOT NULL THEN
    UPDATE public.discounts SET uses_count = uses_count + 1 WHERE id = v_discount.id;
  END IF;

  DELETE FROM public.cart_items WHERE cart_id = v_cart_id;
  UPDATE public.carts SET updated_at = now() WHERE id = v_cart_id;

  RETURN v_group_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_place_order(UUID, JSONB, UUID, TEXT, TEXT) FROM authenticated, anon, public;
