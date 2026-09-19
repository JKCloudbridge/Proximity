-- Sprint 2: rpc_create_shop -- the cross-table invariant SPRINT_PLANNING.md
-- §4.4 calls out explicitly: "On shop creation, insert a shop_team_members
-- row for the creator in the same transaction -- a shop with no
-- owner-membership row would be locked out of its own RLS-gated data."
-- Same pattern §5.1 establishes for all cross-table business logic
-- (checkout, rider assignment, ... and now this): a SECURITY DEFINER
-- function, not a raw multi-statement client-side INSERT/INSERT, so a
-- partial failure can't leave an ownerless shop behind. Also flips the
-- creator's users.role to 'shop_owner' in the same transaction (§1.2:
-- "shop_owner: Created a shop") -- guarded to never downgrade an existing
-- admin account.
--
-- p_owner_id is an explicit parameter, not auth.uid(), for the same reason
-- as rpc_set_default_address (005): this function is only ever called from
-- the Edge Function's service-role pooler connection, where auth.uid() is
-- always NULL. Trusts its one intended caller (the already-authenticated
-- Edge Function route) completely -- REVOKEd from authenticated/anon below,
-- same belt-and-suspenders reasoning as 005.
--
-- p_business_hours is a JSONB array of {weekday, opens_at, closes_at,
-- is_closed} objects (matching the shape the web dashboard's business-hours
-- form posts) rather than 7 more scalar parameters -- keeps this already
-- wide parameter list from getting wider, and mirrors platform_settings'
-- own JSONB-value convention (012) for "a handful of related fields that
-- don't need their own columns on the call signature." Can be an empty
-- array or NULL -- a shop can finish onboarding without setting hours yet
-- and add them later via the dashboard.
--
-- Unlike addresses' two-step insert-then-UPDATE for `location` (Sprint 1's
-- routes/addresses.ts, forced by that insert going through Drizzle), this
-- sets `location` in the same INSERT statement, since the whole thing is
-- raw SQL to begin with -- a small improvement, not a pattern change.

CREATE OR REPLACE FUNCTION public.rpc_create_shop(
  p_owner_id           UUID,
  p_name               TEXT,
  p_description        TEXT,
  p_address_line       TEXT,
  p_city               TEXT,
  p_pincode            TEXT,
  p_lat                DOUBLE PRECISION,
  p_lng                DOUBLE PRECISION,
  p_gstin              TEXT,
  p_fssai_license_no   TEXT,
  p_service_radius_km  NUMERIC,
  p_supports_pickup    BOOLEAN,
  p_supports_delivery  BOOLEAN,
  p_delivery_mode      TEXT,
  p_min_order_value    INTEGER,
  p_business_hours     JSONB
)
RETURNS SETOF shops
LANGUAGE plpgsql
SECURITY DEFINER
-- Same real bug migrations/039's own header now documents the full story
-- of (two attempts, the second one confirmed against a live query, not
-- guessed): the original unqualified `ST_SetSRID(ST_MakePoint(...))
-- ::geography` below can't resolve under `SET search_path = ''`, and
-- widening the search_path (rather than schema-qualifying directly) turned
-- out not to fix it for reasons that weren't fully pinned down even after
-- reasoning through PL/pgSQL's own compile/GUC semantics by hand. Fixed
-- here the same confirmed way: every PostGIS function/type explicitly
-- schema-qualified to `public` (confirmed via `pg_extension`/
-- `extnamespace` against the live database, not assumed), search_path
-- restored to its original, tighter `''`.
SET search_path = ''
AS $$
DECLARE
  v_shop_id UUID;
BEGIN
  INSERT INTO public.shops (
    owner_id, name, description, address_line, city, pincode, location,
    gstin, fssai_license_no, service_radius_km, supports_pickup,
    supports_delivery, delivery_mode, min_order_value
  ) VALUES (
    p_owner_id, p_name, p_description, p_address_line, p_city, p_pincode,
    public.ST_SetSRID(public.ST_MakePoint(p_lng, p_lat), 4326)::public.geography,
    p_gstin, p_fssai_license_no, p_service_radius_km, p_supports_pickup,
    p_supports_delivery, p_delivery_mode, p_min_order_value
  )
  RETURNING id INTO v_shop_id;

  INSERT INTO public.shop_team_members (shop_id, user_id, member_role)
  VALUES (v_shop_id, p_owner_id, 'owner');

  -- Never downgrade an existing admin account that happens to also create a
  -- shop (e.g. testing) -- everyone else moves buyer/rider -> shop_owner.
  UPDATE public.users
  SET role = 'shop_owner', updated_at = now()
  WHERE id = p_owner_id AND role <> 'admin';

  IF p_business_hours IS NOT NULL THEN
    -- Sprint 14 fix: this project's whole backend uses camelCase JSON keys
    -- everywhere (every route response, every request schema, including
    -- shop-creation-form.tsx's own BusinessHourRow this JSONB is built
    -- from) -- these three keys were the one place still reading
    -- snake_case, so every real submission silently produced NULL
    -- opens_at/closes_at + is_closed=false for every weekday, which then
    -- failed shop_business_hours' own CHECK constraint. Never caught until
    -- this sprint's first real POST /shop/shops against a live database.
    INSERT INTO public.shop_business_hours (shop_id, weekday, opens_at, closes_at, is_closed)
    SELECT
      v_shop_id,
      (elem->>'weekday')::smallint,
      NULLIF(elem->>'opensAt', '')::time,
      NULLIF(elem->>'closesAt', '')::time,
      COALESCE((elem->>'isClosed')::boolean, false)
    FROM jsonb_array_elements(p_business_hours) elem;
  END IF;

  RETURN QUERY SELECT * FROM public.shops WHERE id = v_shop_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_create_shop(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION,
  TEXT, TEXT, NUMERIC, BOOLEAN, BOOLEAN, TEXT, INTEGER, JSONB
) FROM authenticated, anon, public;
