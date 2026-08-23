-- Sprint 1: Custom Access Token (JWT) Claims hook + get_role() helper.
-- Same mechanism Baker Ally proved out (6_JWT_create_custom_jwt_claims_hook.sql),
-- adapted for Proximity's plain users.role column instead of a roles table
-- join. Writes the user's role into app_metadata.role on every issued JWT
-- so RLS policies and the Edge Function's auth middleware can read it
-- straight off the token, no DB round trip.
--
-- MANUAL STEP REQUIRED AFTER RUNNING THIS MIGRATION (cannot be done via SQL
-- alone, same as Baker Ally's note): Supabase Dashboard -> Authentication ->
-- Hooks -> "Customize Access Token (JWT) Claims" -> select
-- public.custom_access_token_hook.

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  claims jsonb;
  role_name text;
BEGIN
  SELECT u.role INTO role_name
  FROM public.users u
  WHERE u.id = (event->>'user_id')::uuid;

  claims := event->'claims';

  IF role_name IS NOT NULL THEN
    claims := jsonb_set(claims, '{app_metadata,role}', to_jsonb(role_name), true);
  END IF;

  event := jsonb_set(event, '{claims}', claims);
  RETURN event;
END;
$$;

GRANT USAGE ON SCHEMA public TO supabase_auth_admin;
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook FROM authenticated, anon, public;

-- Read-side helper so every RLS policy that needs "is this caller an admin"
-- (categories, platform_settings, shop/rider approval, discounts -- see
-- SPRINT_PLANNING.md §5.2) can call one function instead of repeating the
-- JWT-claim-extraction expression everywhere. STABLE + SECURITY INVOKER:
-- it only reads the caller's own JWT claims, no elevated privilege needed.
CREATE OR REPLACE FUNCTION public.get_role()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', 'buyer');
$$;
