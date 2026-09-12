-- Sprint 6: rpc_add_to_cart -- SPRINT_PLANNING.md §5.4 names this RPC
-- explicitly: "Upsert into cart_items, stock-status check." Genuinely
-- cross-table, cross-row business logic (§5.1's bar for "goes through a
-- SECURITY DEFINER function, not a raw client-side INSERT/UPDATE"), for the
-- same reason rpc_set_default_address (005) exists: get-or-create-the-cart
-- then upsert-the-item is a read-then-write sequence with a real race if
-- done as two separate round trips from the route handler (two rapid "add
-- to cart" taps, or two devices signed into the same account, could both
-- try to INSERT the first cart row for this user). One statement per step,
-- both idempotent/atomic via ON CONFLICT, inside one function call.
--
-- p_user_id is explicit, not auth.uid() -- same reason as every other RPC in
-- this codebase (§5.1): this connection is the Edge Function's service-role
-- pooler connection, auth.uid() is always NULL there. Trusts its one
-- intended caller (routes/cart.ts, after authMiddleware) completely --
-- REVOKEd from authenticated/anon/public below, same belt-and-suspenders
-- reasoning as every prior RPC.
--
-- Stock-status check happens here, not just as a disabled button in the
-- Flutter PDP (product_detail_screen.dart already disables "Add to cart"
-- for an out-of-stock variant) -- same defense-in-depth judgment call as
-- every cross-table validation elsewhere in this codebase (e.g. routes/
-- catalog.ts's validateSubCategory): the UI hint isn't the enforcement.

CREATE OR REPLACE FUNCTION public.rpc_add_to_cart(p_user_id UUID, p_variant_id UUID, p_quantity INTEGER)
RETURNS SETOF cart_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_cart_id UUID;
  v_stock_status TEXT;
  v_is_active BOOLEAN;
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'INVALID_QUANTITY' USING ERRCODE = 'P0001';
  END IF;

  SELECT stock_status, is_active INTO v_stock_status, v_is_active
  FROM public.product_variants
  WHERE id = p_variant_id;

  IF NOT FOUND OR NOT v_is_active THEN
    RAISE EXCEPTION 'VARIANT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_stock_status = 'out_of_stock' THEN
    RAISE EXCEPTION 'OUT_OF_STOCK' USING ERRCODE = 'P0003';
  END IF;

  INSERT INTO public.carts (user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO UPDATE SET updated_at = now()
  RETURNING id INTO v_cart_id;

  INSERT INTO public.cart_items (cart_id, variant_id, quantity)
  VALUES (v_cart_id, p_variant_id, p_quantity)
  ON CONFLICT (cart_id, variant_id)
  DO UPDATE SET quantity = public.cart_items.quantity + excluded.quantity;

  UPDATE public.carts SET updated_at = now() WHERE id = v_cart_id;

  RETURN QUERY SELECT * FROM public.cart_items WHERE cart_id = v_cart_id AND variant_id = p_variant_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_add_to_cart(UUID, UUID, INTEGER) FROM authenticated, anon, public;
