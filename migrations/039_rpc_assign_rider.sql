-- Sprint 9: rpc_assign_rider(order_id) -- SPRINT_PLANNING.md §5.4/§8.1:
-- "shop-triggered or auto-triggered, finds the nearest riders.status
-- ='available' via current_location <-> shop.location (PostGIS), sets
-- orders.rider_id, flips the rider to on_delivery."
--
-- ===========================================================================
-- WHEN DOES THIS ACTUALLY FIRE? -- §11's own Sprint 9 entry doesn't name a
-- trigger point any more explicitly than Sprint 8's pay_at_shop-timing
-- question was left undecided (this sprint's own brief says so directly).
-- Decided here, not deferred:
-- ===========================================================================
--
-- **Primary trigger: automatic**, chained off Sprint 8's own
-- confirmPaymentAndGenerateInvoices (lib/orderConfirmation.ts), the instant
-- an order transitions pending -> confirmed AND
-- delivery_fulfilled_by = 'platform_rider'. Reasoning: §1.4 already
-- guarantees every such order is `payment_mode = 'online'` (pay_at_shop is
-- refused outright whenever a platform rider is involved, migrations/032
-- step 3) -- so "the order just got confirmed" and "a platform rider needs
-- to be found" are the same moment for every order this RPC will ever be
-- called on. Waiting for a separate, later shop action (e.g. the shop
-- marking it 'preparing') would leave a paid, confirmed delivery order with
-- no rider search underway for no operational reason -- the shop still
-- needs to prepare the order regardless of when a rider gets found, and a
-- rider en route or already assigned while the shop preps is strictly
-- better for delivery time than waiting.
--
-- **Documented fallback: an explicit shop-triggered retry**
-- (routes/shopOrders.ts's POST .../assign-rider, owner/staff only) for the
-- one real failure mode the automatic path can't paper over: no
-- `riders.status='available'` row existed at confirmation time. This
-- function is safe to call a second time for the same reason every RPC in
-- this project that might run twice is: idempotent by construction (an
-- order that already has a rider_id returns that assignment immediately,
-- never re-searches or reassigns) -- see the guard below.
--
-- ===========================================================================
--
-- Not this RPC's job, deliberately, same "don't build the mechanism a
-- decision doesn't need yet" discipline as every prior sprint's own cuts:
-- no re-assignment if the first rider goes offline mid-delivery (no
-- cancellation/reassignment flow exists anywhere in this project, Sprint
-- 7/8 both flagged this gap and it's still open), no radius cap on the
-- rider search (finds the globally nearest available verified rider,
-- however far -- a real production deployment spanning multiple cities
-- would want one; this project has exactly one service area in every
-- worked example so far and §5.4's own wording never named a cap), no
-- notification delivery of any kind (§8.5 names "push, via rpc_assign_rider"
-- but this project has no FCM/APNs wiring at all yet -- checked directly,
-- not assumed: grepping this entire repo for firebase/fcm/apns/push_token
-- plumbing turns up nothing beyond users.fcm_token, an unused placeholder
-- column added in Sprint 1 for Sprint 11. Sprint 9.md documents the
-- Realtime-subscription fallback this sprint actually builds instead).

CREATE OR REPLACE FUNCTION public.rpc_assign_rider(p_order_id UUID)
RETURNS TABLE(order_id UUID, rider_id UUID, rider_full_name TEXT, rider_phone TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
-- **Real bug, caught by actually running this against a live database --
-- fixed twice, and the full honest story of both attempts is worth keeping
-- here rather than just the final answer.** Original code: bare
-- `GEOGRAPHY`/`<->` under `SET search_path = ''`, with a comment claiming
-- PostGIS's own schema "is what actually resolves this" -- backwards; an
-- empty search_path resolves nothing outside pg_catalog. First fix tried:
-- `SET search_path = 'public, extensions'`, a guess at which schema
-- PostGIS landed in without querying the live database to check --
-- **run against the real database, and it still failed with the identical
-- error**, confirmed by the error's own line number matching this fixed
-- file exactly. Queried directly this time, not guessed:
-- `SELECT extname, extnamespace::regnamespace FROM pg_extension` on the
-- actual live database shows `postgis` in **`public`** (this project's
-- migrations/000 never gave `CREATE EXTENSION postgis` an explicit
-- `SCHEMA` clause, so it landed wherever the connecting role's own default
-- search_path pointed at creation time -- `public`, on this database. Not
-- necessarily true of every Supabase project; don't copy the schema name
-- here into a new project without checking again). Since the search_path
-- route already failed once for reasons not fully explained even after
-- reasoning through PL/pgSQL's GUC/compile-time semantics by hand, the fix
-- actually applied here sidesteps that whole question: every PostGIS
-- type/function/operator below is explicitly schema-qualified
-- (`public.geography`, `OPERATOR(public.<->)`), which resolves via direct
-- catalog lookup regardless of search_path -- and `SET search_path = ''`
-- is restored to this function's original, tighter security posture,
-- since full qualification makes widening it unnecessary.
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

  -- Idempotent: an order that already has a rider returns that assignment
  -- rather than re-searching -- safe for both the automatic post-payment
  -- caller and the manual shop-triggered retry to call unconditionally.
  IF v_order.rider_id IS NOT NULL THEN
    SELECT * INTO v_rider FROM public.riders WHERE id = v_order.rider_id;
    RETURN QUERY SELECT v_order.id, v_rider.id, v_rider.full_name, v_rider.phone;
    RETURN;
  END IF;

  SELECT location INTO v_shop_point FROM public.shops WHERE id = v_order.shop_id;
  IF v_shop_point IS NULL THEN
    RAISE EXCEPTION 'SHOP_LOCATION_MISSING' USING ERRCODE = 'P0043';
  END IF;

  -- Nearest available, verified rider -- the `<->` KNN distance operator on
  -- a GEOGRAPHY column, same PostGIS pattern GET /v1/shops/near established
  -- (Sprint 4) for exact-distance ordering once idx_riders_location's GIST
  -- index has narrowed the candidate set, except here there's no separate
  -- ST_DWithin pre-filter step needed first -- the KNN operator uses the
  -- index directly for the ORDER BY itself, and this project has no named
  -- radius cap to pre-filter on (see header). FOR UPDATE SKIP LOCKED: if
  -- two orders are being assigned concurrently, the second call skips a
  -- rider the first has already locked rather than blocking on it or
  -- double-assigning the same rider to two deliveries at once -- same
  -- "cross-row race" discipline as rpc_add_to_cart's upsert.
  SELECT * INTO v_rider
  FROM public.riders
  WHERE status = 'available' AND is_verified = true AND current_location IS NOT NULL
  ORDER BY current_location OPERATOR(public.<->) v_shop_point
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'NO_RIDER_AVAILABLE' USING ERRCODE = 'P0044';
  END IF;

  UPDATE public.orders SET rider_id = v_rider.id, updated_at = now() WHERE id = p_order_id;
  UPDATE public.riders SET status = 'on_delivery' WHERE id = v_rider.id;

  -- order_status_history's own status column is free text (migrations/030
  -- carries no CHECK) -- 'rider_assigned' isn't one of orders.status'
  -- enum values and was never meant to be; this is the human-readable
  -- timeline entry §7.5's buyer-tracking Realtime subscription renders,
  -- independent of the strict orders.status column rpc_shop_advance_order_
  -- status/rpc_rider_update_status manage (see those files' own headers for
  -- why the two vocabularies are deliberately not the same).
  INSERT INTO public.order_status_history (order_id, status, note)
  VALUES (p_order_id, 'rider_assigned', 'Assigned to ' || v_rider.full_name);

  RETURN QUERY SELECT v_order.id, v_rider.id, v_rider.full_name, v_rider.phone;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_assign_rider(UUID) FROM authenticated, anon, public;
