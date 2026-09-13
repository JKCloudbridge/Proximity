-- Sprint 11: rpc_create_recurring_list / rpc_replace_recurring_list_items,
-- plus two small shared IST wall-clock helpers both this file and
-- migrations/045's cron job need.
--
-- **Timezone convention, decided explicitly:** this project has two
-- different "what time is it in India" approaches on record -- lib/slots.ts
-- (Sprint 4) hardcodes a +5:30 offset specifically because there was (and
-- still is) no live database to confirm a named-zone lookup against;
-- rpc_place_order (migrations/032, Sprint 7) used `AT TIME ZONE
-- 'Asia/Kolkata'` instead, and Sprint 7's own write-up flagged that as
-- genuinely unconfirmed against a real Postgres tzdata install. Picking the
-- **hardcoded +5:30 offset** here, not the named-zone form -- it's the
-- dominant, already-multiply-used convention (lib/slots.ts, and every other
-- IST assumption in this codebase traces back to it), India has had no DST
-- since 1945 so a fixed offset is not an approximation that can go wrong the
-- way it would for most other countries, and this sprint has enough
-- genuinely new unverified surface already (pg_cron, FCM) without also
-- being the second thing resting on Sprint 7's own still-unconfirmed
-- named-zone bet.
CREATE OR REPLACE FUNCTION public.to_ist(p_ts TIMESTAMPTZ)
RETURNS TIMESTAMP
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT (p_ts AT TIME ZONE 'UTC') + INTERVAL '5 hours 30 minutes'
$$;

CREATE OR REPLACE FUNCTION public.ist_to_utc(p_ist TIMESTAMP)
RETURNS TIMESTAMPTZ
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT (p_ist - INTERVAL '5 hours 30 minutes') AT TIME ZONE 'UTC'
$$;

CREATE OR REPLACE FUNCTION public.ist_now()
RETURNS TIMESTAMP
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT public.to_ist(now())
$$;

-- Both helpers above are intentionally public, unrestricted functions (no
-- REVOKE) -- they're pure, side-effect-free time math, not a privileged
-- operation, same "no reason to lock this down" judgment call this
-- codebase's own get_role() helper (004) already made.

-- rpc_create_recurring_list -- atomic list + its starting item set, same
-- cross-table "ownerless row is a real bug, not a UI edge case" bar
-- rpc_create_shop (014) sets for "a shop with no owner-membership row."
-- Here the equivalent invariant is "a recurring list with zero items" --
-- the cron job (045) would faithfully fire a reminder for an empty cart
-- forever, which is a real, silently-broken feature, not just untidy data --
-- so item insertion happens in the same transaction as list creation, not
-- as a separate follow-up call.
--
-- Computes the list's own first next_run_at here rather than pushing that
-- math into the route layer: "the next occurrence of time_of_day, today if
-- it hasn't passed yet, otherwise today+one cadence step" is exactly the
-- same shape of time arithmetic migrations/045's own advance-after-fire
-- step needs, so it belongs next to ist_now()/ist_to_utc() above, not
-- duplicated in TypeScript.
--
-- p_user_id is explicit, not auth.uid() -- same §5.1 reason as every other
-- RPC in this codebase (rpc_set_default_address, 005, is the reference
-- case). p_items is a JSONB array of {variantId, quantity} objects, same
-- "don't widen an already-long parameter list with N more scalars" judgment
-- call rpc_create_shop's own p_business_hours made for 7 weekday rows.
CREATE OR REPLACE FUNCTION public.rpc_create_recurring_list(
  p_user_id       UUID,
  p_name          TEXT,
  p_cadence       TEXT,
  p_interval_days INTEGER,
  p_time_of_day   TIME,
  p_items         JSONB
)
RETURNS SETOF recurring_lists
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_list_id   UUID;
  v_ist_now   TIMESTAMP;
  v_candidate TIMESTAMP;
BEGIN
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'EMPTY_ITEM_LIST' USING ERRCODE = 'P0001';
  END IF;

  v_ist_now := public.ist_now();
  v_candidate := date_trunc('day', v_ist_now) + p_time_of_day;

  IF v_candidate <= v_ist_now THEN
    v_candidate := v_candidate + CASE p_cadence
      WHEN 'daily'       THEN INTERVAL '1 day'
      WHEN 'weekly'      THEN INTERVAL '7 days'
      WHEN 'biweekly'    THEN INTERVAL '14 days'
      WHEN 'monthly'     THEN INTERVAL '1 month'
      WHEN 'custom_days' THEN (GREATEST(p_interval_days, 1)::text || ' days')::interval
      ELSE INTERVAL '1 day'
    END;
  END IF;

  INSERT INTO public.recurring_lists (user_id, name, cadence, interval_days, time_of_day, next_run_at)
  VALUES (p_user_id, p_name, p_cadence, p_interval_days, p_time_of_day, public.ist_to_utc(v_candidate))
  RETURNING id INTO v_list_id;

  INSERT INTO public.recurring_list_items (recurring_list_id, variant_id, quantity)
  SELECT v_list_id, (elem->>'variantId')::uuid, COALESCE((elem->>'quantity')::integer, 1)
  FROM jsonb_array_elements(p_items) elem;

  RETURN QUERY SELECT * FROM public.recurring_lists WHERE id = v_list_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_create_recurring_list(UUID, TEXT, TEXT, INTEGER, TIME, JSONB)
  FROM authenticated, anon, public;

-- rpc_replace_recurring_list_items -- the "edit a list's items" operation
-- (add/remove/change quantity, from the edit screen or a "save this cart as
-- a recurring list" action) is a delete-then-reinsert, same atomicity
-- reasoning as rpc_add_to_cart's own get-or-create-then-upsert (024): a
-- plain client-side DELETE-then-INSERT pair over two round trips would have
-- a real window where the list has zero items if the second call never
-- lands. Ownership-checked explicitly against p_user_id (not just left to
-- RLS, which is a backstop only per §5.1) -- same belt-and-suspenders shape
-- routes/catalog.ts's getOwnedProduct established for "does this id
-- actually belong to this caller" in Sprint 3.
CREATE OR REPLACE FUNCTION public.rpc_replace_recurring_list_items(
  p_list_id UUID,
  p_user_id UUID,
  p_items   JSONB
)
RETURNS SETOF recurring_list_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.recurring_lists WHERE id = p_list_id AND user_id = p_user_id) THEN
    RAISE EXCEPTION 'RECURRING_LIST_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'EMPTY_ITEM_LIST' USING ERRCODE = 'P0001';
  END IF;

  DELETE FROM public.recurring_list_items WHERE recurring_list_id = p_list_id;

  INSERT INTO public.recurring_list_items (recurring_list_id, variant_id, quantity)
  SELECT p_list_id, (elem->>'variantId')::uuid, COALESCE((elem->>'quantity')::integer, 1)
  FROM jsonb_array_elements(p_items) elem;

  RETURN QUERY SELECT * FROM public.recurring_list_items WHERE recurring_list_id = p_list_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_replace_recurring_list_items(UUID, UUID, JSONB)
  FROM authenticated, anon, public;

-- rpc_update_recurring_list_schedule -- editing name/cadence/interval_days/
-- time_of_day needs the exact same "next occurrence of time_of_day, today
-- if it hasn't passed, otherwise today + one cadence step" recompute
-- rpc_create_recurring_list does on insert -- pulled out as its own RPC
-- rather than duplicated inline in routes/recurringLists.ts's PATCH handler,
-- same "the RPC owns this invariant, TypeScript never recomputes it" reason
-- schema.ts's own header gives for nextRunAt. Deliberately does NOT touch
-- is_active -- pausing/resuming is a plain single-column update
-- (routes/recurringLists.ts, same no-RPC-needed shape riders.ts's own
-- online/offline status PATCH already established in Sprint 2) and
-- deliberately does NOT recompute next_run_at on resume either: a paused
-- list's next_run_at simply sits in the past while is_active=false (the
-- cron job's own `AND is_active` filter already skips it regardless), and
-- resuming picks it up on the very next cron tick rather than silently
-- re-anchoring to a fresh "from now" schedule -- a buyer who pauses for two
-- weeks and resumes gets an immediate reminder, not a quiet two-week gap
-- before the next one, which is the more useful default for "I paused this,
-- now I want it again."
CREATE OR REPLACE FUNCTION public.rpc_update_recurring_list_schedule(
  p_list_id       UUID,
  p_user_id       UUID,
  p_name          TEXT,
  p_cadence       TEXT,
  p_interval_days INTEGER,
  p_time_of_day   TIME
)
RETURNS SETOF recurring_lists
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_ist_now   TIMESTAMP;
  v_candidate TIMESTAMP;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.recurring_lists WHERE id = p_list_id AND user_id = p_user_id) THEN
    RAISE EXCEPTION 'RECURRING_LIST_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  v_ist_now := public.ist_now();
  v_candidate := date_trunc('day', v_ist_now) + p_time_of_day;

  IF v_candidate <= v_ist_now THEN
    v_candidate := v_candidate + CASE p_cadence
      WHEN 'daily'       THEN INTERVAL '1 day'
      WHEN 'weekly'      THEN INTERVAL '7 days'
      WHEN 'biweekly'    THEN INTERVAL '14 days'
      WHEN 'monthly'     THEN INTERVAL '1 month'
      WHEN 'custom_days' THEN (GREATEST(p_interval_days, 1)::text || ' days')::interval
      ELSE INTERVAL '1 day'
    END;
  END IF;

  UPDATE public.recurring_lists
  SET name = p_name,
      cadence = p_cadence,
      interval_days = p_interval_days,
      time_of_day = p_time_of_day,
      next_run_at = public.ist_to_utc(v_candidate),
      updated_at = now()
  WHERE id = p_list_id;

  RETURN QUERY SELECT * FROM public.recurring_lists WHERE id = p_list_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_update_recurring_list_schedule(UUID, UUID, TEXT, TEXT, INTEGER, TIME)
  FROM authenticated, anon, public;
