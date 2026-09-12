-- Sprint 2: rpc_create_rider_profile -- same cross-table-invariant shape as
-- rpc_create_shop (014): inserting into `riders` and flipping the caller's
-- `users.role` to 'rider' need to happen together, atomically, for the same
-- reason a shop needs its owner-membership row written alongside it (§4.4).
-- Idempotent like /v1/auth/me (routes/auth.ts) -- a rider re-submitting the
-- onboarding form (e.g. to update a KYC document after a rejected one)
-- updates the existing row instead of erroring on the UNIQUE(user_id)
-- constraint, mirroring how /auth/me treats "row already exists" as success
-- rather than a conflict.
--
-- p_user_id is explicit, not auth.uid(), for the same connection-shape
-- reason as rpc_set_default_address (005) and rpc_create_shop (014).

CREATE OR REPLACE FUNCTION public.rpc_create_rider_profile(
  p_user_id          UUID,
  p_full_name        TEXT,
  p_phone            TEXT,
  p_vehicle_type     TEXT,
  p_vehicle_number   TEXT,
  p_kyc_document_url TEXT
)
RETURNS SETOF riders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Aliased to `r` so the DO UPDATE SET below can reference the existing
  -- row's value unambiguously -- SET search_path='' means the bare table
  -- name isn't resolvable as a correlation name here without one.
  INSERT INTO public.riders AS r (user_id, full_name, phone, vehicle_type, vehicle_number, kyc_document_url)
  VALUES (p_user_id, p_full_name, p_phone, p_vehicle_type, p_vehicle_number, p_kyc_document_url)
  ON CONFLICT (user_id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    phone = EXCLUDED.phone,
    vehicle_type = EXCLUDED.vehicle_type,
    vehicle_number = EXCLUDED.vehicle_number,
    kyc_document_url = COALESCE(EXCLUDED.kyc_document_url, r.kyc_document_url);
    -- Resubmitting the form without a new document keeps the previously
    -- uploaded one rather than nulling it out.

  UPDATE public.users
  SET role = 'rider', updated_at = now()
  WHERE id = p_user_id AND role <> 'admin';

  RETURN QUERY SELECT * FROM public.riders WHERE user_id = p_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_create_rider_profile(UUID, TEXT, TEXT, TEXT, TEXT, TEXT)
  FROM authenticated, anon, public;
