-- Sprint 1: rpc_set_default_address -- the first end-to-end RPC, chosen to
-- prove the "cross-row invariant goes through a function, not a raw
-- multi-statement client update" pattern from SPRINT_PLANNING.md §5 before
-- it's relied on everywhere else (checkout, rider assignment, etc.). Picked
-- over the originally-drafted rpc_add_to_cart because carts/variants don't
-- exist until Sprint 3/6 -- addresses do, and "exactly one default address"
-- is a real enough cross-row invariant to exercise the pattern honestly.
--
-- CORRECTED from the first draft of this file, which had auth.uid() do the
-- ownership check. That's wrong for how this backend actually connects to
-- Postgres: proximity_backend's Edge Function talks to the database via
-- postgres.js over the Supavisor pooler using the service-role connection
-- string (see proximity_backend/supabase/functions/api/lib/db.ts) -- the
-- exact same connection shape Baker Ally's baker_ally_backend/.../lib/db.ts
-- already proved out. That connection is never mediated by PostgREST, so no
-- `request.jwt.claims` GUC is ever set on it and auth.uid() always
-- evaluates to NULL there -- it would have silently matched zero rows and
-- every call would have failed with ADDRESS_NOT_FOUND_OR_NOT_OWNED, even for
-- the address's real owner. Caught this while actually wiring the Edge
-- Function route in Sprint 1, not left for a runtime surprise.
--
-- The actual trust boundary in this architecture (again, matching Baker
-- Ally) is the Edge Function's own authMiddleware, which verifies the
-- caller's JWT via supabaseAdmin.auth.getUser(token) before any route
-- handler runs. Everything downstream, including this function, trusts the
-- already-verified user id the route passes in explicitly as p_user_id.
-- RLS stays enabled on `addresses` (004/002) as a defense-in-depth backstop
-- for any access path that *does* go through PostgREST with a real user JWT
-- (the Supabase dashboard's table editor, for instance) -- it just isn't
-- what protects this specific call path.

CREATE OR REPLACE FUNCTION public.rpc_set_default_address(p_user_id UUID, p_address_id UUID)
RETURNS SETOF addresses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.addresses
    WHERE id = p_address_id AND user_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'ADDRESS_NOT_FOUND_OR_NOT_OWNED' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.addresses
  SET is_default = false
  WHERE user_id = p_user_id AND is_default = true AND id <> p_address_id;

  UPDATE public.addresses
  SET is_default = true
  WHERE id = p_address_id;

  RETURN QUERY SELECT * FROM public.addresses WHERE user_id = p_user_id ORDER BY created_at;
END;
$$;

-- Not exposed to PostgREST's public RPC surface at all (REVOKE from
-- authenticated/anon) -- this function is only ever meant to be called from
-- the Edge Function's own privileged connection, which isn't subject to
-- GRANT/REVOKE the same way a PostgREST-authenticated role is. The REVOKE
-- here is belt-and-suspenders: it keeps this function from being callable
-- via a stray `supabase.rpc(...)` from the Flutter client, which would be
-- able to pass an arbitrary p_user_id and set someone else's default
-- address -- there is no re-check of "is the caller actually p_user_id"
-- inside this function, by design, because it trusts its one intended
-- caller completely. Keep it that way; don't relax this REVOKE later
-- without adding that check back.
REVOKE EXECUTE ON FUNCTION public.rpc_set_default_address(UUID, UUID) FROM authenticated, anon, public;
