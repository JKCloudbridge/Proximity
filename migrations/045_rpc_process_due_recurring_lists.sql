-- Sprint 11: the pg_cron reminder job itself. migrations/000 already named
-- this file's own purpose back in Sprint 0/1 ("pg_cron drives the Organizer
-- reminder job (Sprint 11)... pg_net is the fire-and-forget internal-webhook
-- mechanism, same pattern Baker Ally proved out for its restock-notify
-- trigger -- reused here for the Organizer reminder job"). This is that.
--
-- **What "fires a reminder" means end-to-end, decided explicitly (§11 asked
-- for this precisely, not just "a cron job exists"):**
--   1. pg_cron invokes public.process_due_recurring_lists() on a fixed
--      schedule (every 10 minutes -- see the cron.schedule call at the
--      bottom for why that granularity, not tighter or looser).
--   2. For every recurring_lists row that's actually due (next_run_at <=
--      now() AND is_active), LOCKed FOR UPDATE SKIP LOCKED so two
--      overlapping cron ticks (the previous run still finishing when the
--      next one fires) can never double-process the same list.
--   3. **"Pre-filled cart" is real, not a UI illusion**: every item on that
--      list is upserted into the buyer's own actual cart_items via the
--      same rpc_add_to_cart (024) the PDP's own "Add to cart" button calls
--      -- same stock-status check, same idempotent upsert-or-increment
--      semantics. By the time the push notification below is actually
--      tapped, the cart IS the pre-filled cart; there's no separate draft/
--      preview object the app has to resolve first. One item failing
--      (out of stock, deactivated, deleted) does NOT stop the rest of the
--      list or the reminder itself from firing -- same best-effort-per-item
--      philosophy routes/cart.ts's own POST /cart/items/batch already
--      established for Order Again's "Add All to Cart" in Sprint 10; a
--      buyer who opens their pre-filled cart and finds one item dimmed
--      "No longer available" (cart_item_tile.dart's own existing,
--      unchanged treatment) is a fine outcome, refusing the whole reminder
--      over one stale item would not be.
--   4. next_run_at is advanced from its OWN previous value (converted to
--      IST wall-clock via to_ist(), one cadence step added, converted back
--      via ist_to_utc() -- both from migrations/044), never from now().
--      Advancing from now() would let a late-running cron tick (or a
--      backlog of missed ticks after downtime) permanently drag a list's
--      fire time later and later, a few minutes at a time, until "every day
--      at 9am" had quietly drifted into "every day at 11am" months later.
--      Anchoring to the previous scheduled instant keeps the buyer's chosen
--      time-of-day stable regardless of how punctually the cron job itself
--      actually runs.
--   5. One net.http_post per fired list to this project's own internal
--      route (proximity_backend's routes/internal.ts, Sprint 11), carrying
--      the recurring_list_id/user_id/name -- that route is the one that
--      actually calls the FCM v1 API (lib/push/fcm.ts) and knows how to
--      build the deep-link payload. This function deliberately does NOT
--      call Firebase directly from Postgres -- the OAuth2/JWT-signing dance
--      FCM's HTTP v1 API needs (lib/push/fcm.ts's own header has the full
--      citation trail) is exactly the kind of thing that belongs in the
--      Edge Function, not hand-rolled a second time in plpgsql.
--
-- **Same accepted trade-off Baker Ally's own migrations/024 documented for
-- this exact pg_net pattern: fire-and-forget, no retry on failure.** If the
-- Edge Function is down or the push send itself fails, this cron tick's
-- reminder is simply lost -- the list's next_run_at has already been
-- advanced by the time net.http_post is called, so it will NOT be retried
-- on the next tick either. Accepted for the same reason Baker Ally accepted
-- it: building real retry/dead-letter handling needs infrastructure (a
-- queue, a worker) this MVP doesn't have anywhere else either, and a missed
-- reminder is a buyer inconvenience, not a correctness/money bug the way a
-- missed payment webhook would be (Sprint 8's rpc_confirm_payment, by
-- contrast, is deliberately called from BOTH a client path and a webhook
-- specifically because that one can't afford to be lost -- this one can).
--
-- **MANUAL STEP REQUIRED AFTER RUNNING THIS MIGRATION**, same precedent as
-- 004's JWT-hook step and Baker Ally's own 024: store two values in
-- Supabase Vault (already-enabled supabase_vault extension on every
-- Supabase-managed project) so neither lands in this file or git history --
--   SELECT vault.create_secret('<a random shared secret>', 'internal_notify_secret');
--   SELECT vault.create_secret('https://<project-ref>.supabase.co/functions/v1/api', 'internal_api_base_url');
-- and set INTERNAL_NOTIFY_SECRET to that same shared-secret value as a
-- proximity_backend Edge Function secret (`supabase secrets set
-- INTERNAL_NOTIFY_SECRET=<value>`) -- routes/internal.ts checks it against
-- the x-internal-secret header. Storing the base URL in Vault too (rather
-- than hardcoding one project's ref into this SQL file, the way Baker
-- Ally's own 024 did) is deliberate: this project plans two Supabase
-- projects, proximity-staging and proximity-prod (§3.2) -- this same
-- migration file runs unmodified against both, each with its own Vault
-- value, rather than needing a per-environment edit to this file. Until
-- both secrets exist, the function silently no-ops the notify step (still
-- pre-fills the cart and advances next_run_at either way) rather than
-- failing every cron tick.

CREATE OR REPLACE FUNCTION public.process_due_recurring_lists()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_list             RECORD;
  v_item             RECORD;
  v_next_ist         TIMESTAMP;
  v_secret           TEXT;
  v_base_url         TEXT;
BEGIN
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'internal_notify_secret' LIMIT 1;
  SELECT decrypted_secret INTO v_base_url FROM vault.decrypted_secrets WHERE name = 'internal_api_base_url' LIMIT 1;

  FOR v_list IN
    SELECT * FROM public.recurring_lists
    WHERE next_run_at <= now() AND is_active
    ORDER BY next_run_at
    FOR UPDATE SKIP LOCKED
  LOOP
    -- One list's own bug (a malformed row that somehow bypassed the CHECK
    -- constraints, an unexpected exception from the cart upsert below)
    -- must not abort every other due list in the same batch -- same
    -- "isolate the blast radius" reasoning routes/cart.ts's batch-add
    -- already applies one level down, at the item level.
    BEGIN
      FOR v_item IN
        SELECT * FROM public.recurring_list_items WHERE recurring_list_id = v_list.id
      LOOP
        BEGIN
          PERFORM public.rpc_add_to_cart(v_list.user_id, v_item.variant_id, v_item.quantity);
        EXCEPTION WHEN OTHERS THEN
          -- VARIANT_NOT_FOUND / OUT_OF_STOCK / INVALID_QUANTITY (or anything
          -- else) -- skip this one item, keep pre-filling the rest. Same
          -- per-item best-effort contract routes/cart.ts's own
          -- POST /cart/items/batch already promises for Order Again.
          RAISE WARNING 'recurring_list_items upsert failed for list %, variant %: %', v_list.id, v_item.variant_id, SQLERRM;
        END;
      END LOOP;

      v_next_ist := public.to_ist(v_list.next_run_at) + CASE v_list.cadence
        WHEN 'daily'       THEN INTERVAL '1 day'
        WHEN 'weekly'      THEN INTERVAL '7 days'
        WHEN 'biweekly'    THEN INTERVAL '14 days'
        WHEN 'monthly'     THEN INTERVAL '1 month'
        WHEN 'custom_days' THEN (GREATEST(v_list.interval_days, 1)::text || ' days')::interval
        ELSE INTERVAL '1 day'
      END;

      UPDATE public.recurring_lists
      SET next_run_at = public.ist_to_utc(v_next_ist),
          last_run_at = now(),
          updated_at = now()
      WHERE id = v_list.id;

      IF v_secret IS NOT NULL AND v_base_url IS NOT NULL THEN
        PERFORM net.http_post(
          url := v_base_url || '/v1/internal/send-recurring-reminder',
          headers := jsonb_build_object('Content-Type', 'application/json', 'x-internal-secret', v_secret),
          body := jsonb_build_object('recurringListId', v_list.id, 'userId', v_list.user_id, 'listName', v_list.name)
        );
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'process_due_recurring_lists failed for list %: %', v_list.id, SQLERRM;
    END;
  END LOOP;
END;
$$;

-- No REVOKE needed beyond the default -- this function takes no parameters
-- a caller could abuse (it always processes every globally-due list, never
-- one a caller names), and it's only ever invoked by pg_cron's own internal
-- scheduler role, never by the Edge Function or a client. Still, belt-and-
-- suspenders, same as every other RPC in this codebase:
REVOKE EXECUTE ON FUNCTION public.process_due_recurring_lists() FROM authenticated, anon, public;

-- Every 10 minutes -- tight enough that "fires at the right time" (§11's
-- own exit-criteria wording) reads as true to a buyer checking their phone
-- (worst case: 10 minutes late), loose enough not to be a meaningful write
-- load against recurring_lists/cart_items for a table this MVP expects to
-- hold, at most, a few thousand rows for a long while. Revisit downward
-- only if real usage ever asks for tighter punctuality than this.
SELECT cron.schedule(
  'process-due-recurring-lists',
  '*/10 * * * *',
  $$SELECT public.process_due_recurring_lists();$$
);
