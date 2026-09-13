-- Sprint 12: rpc_expire_stale_rider_assignments -- the timeout half of
-- migrations/048's decline/reassignment flow (see that file's header for the
-- full design). Runs on pg_cron, same fire-and-forget-tolerant primitive
-- migrations/045 already established for the Organizer reminder job --
-- except this job has no external push side effect to lose, only internal
-- DB state to correct, so there's no equivalent "accepted trade-off" note to
-- make here.
--
-- **Threshold: 5 minutes, a documented constant, not (yet) an admin-
-- configurable platform_setting.** Unlike the delivery fee/slot window
-- (§4.6, admin-editable per your explicit instruction), no requirement
-- anywhere in this project names rider-response SLA as something admin
-- needs to tune -- inventing a settings row for a number nobody asked to
-- control would be speculative scope, not a real need. Revisit as a real
-- platform_settings key the moment an actual admin need for it shows up
-- (the migrations/046 comment on shop_ledger_entries makes the same kind
-- of "don't build for a hypothetical" call).
--
-- Every 2 minutes -- tight enough that a stale assignment is caught within
-- 2-7 minutes of actually going stale (worst case: it became stale one
-- second after the last tick), loose enough not to be a meaningful write
-- load against orders/riders for this MVP's expected volume. Same
-- granularity trade-off reasoning migrations/045 already gives for its own
-- 10-minute cadence, just tighter here because a rider assignment is more
-- time-sensitive than a recurring-list reminder.

CREATE OR REPLACE FUNCTION public.rpc_expire_stale_rider_assignments()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order    RECORD;
  v_excluded UUID[];
BEGIN
  FOR v_order IN
    WITH latest_assignment AS (
      SELECT DISTINCT ON (order_id) order_id, changed_at
      FROM public.order_status_history
      WHERE status = 'rider_assigned'
      ORDER BY order_id, changed_at DESC
    )
    SELECT o.*
    FROM public.orders o
    JOIN latest_assignment la ON la.order_id = o.id
    WHERE o.rider_id IS NOT NULL
      AND o.status NOT IN ('cancelled', 'completed', 'out_for_delivery')
      AND la.changed_at <= now() - INTERVAL '5 minutes'
      -- No 'rider_accepted' row logged since the most recent assignment --
      -- an accepted rider is mid-commitment, not stale; the manual
      -- shop-side reassign action (routes/shopOrders.ts) is the escape
      -- hatch for that case (migrations/048's own header, "mid-delivery
      -- unreachability").
      AND NOT EXISTS (
        SELECT 1 FROM public.order_status_history h
        WHERE h.order_id = o.id AND h.status = 'rider_accepted' AND h.changed_at > la.changed_at
      )
    FOR UPDATE OF o SKIP LOCKED
  LOOP
    -- Same "one bad row must not sink the whole batch" isolation
    -- migrations/045's own cron loop applies per-list.
    BEGIN
      UPDATE public.riders SET status = 'available' WHERE id = v_order.rider_id AND status = 'on_delivery';

      INSERT INTO public.order_rider_declines (order_id, rider_id, reason)
      VALUES (v_order.id, v_order.rider_id, 'assignment timed out (no response within 5 minutes)')
      ON CONFLICT (order_id, rider_id) DO NOTHING;

      UPDATE public.orders SET rider_id = NULL, updated_at = now() WHERE id = v_order.id;

      -- Logged as its own distinct status word, not 'rider_declined' --
      -- migrations/048's own header: operationally identical, but a
      -- shopkeeper or admin reading order_status_history later should be
      -- able to tell "the rider actively declined" from "the rider never
      -- responded at all."
      INSERT INTO public.order_status_history (order_id, status, note)
      VALUES (v_order.id, 'rider_assignment_timed_out', 'No response within 5 minutes -- reassigning');

      SELECT array_agg(rider_id) INTO v_excluded FROM public.order_rider_declines WHERE order_id = v_order.id;

      BEGIN
        PERFORM public.rpc_assign_rider(v_order.id, v_excluded);
      EXCEPTION WHEN OTHERS THEN
        -- NO_RIDER_AVAILABLE is the expected/common case -- the order is
        -- left with rider_id = NULL either way (the shop's manual retry is
        -- the documented fallback), so this is caught and logged, never
        -- allowed to abort the outer per-order block.
        RAISE WARNING 'rpc_expire_stale_rider_assignments: reassignment for order % failed: %', v_order.id, SQLERRM;
      END;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'rpc_expire_stale_rider_assignments: failed for order %: %', v_order.id, SQLERRM;
    END;
  END LOOP;
END;
$$;

-- No caller-supplied parameters to abuse (same reasoning migrations/045
-- gives for process_due_recurring_lists) -- only ever invoked by pg_cron's
-- own internal scheduler role.
REVOKE EXECUTE ON FUNCTION public.rpc_expire_stale_rider_assignments() FROM authenticated, anon, public;

SELECT cron.schedule(
  'expire-stale-rider-assignments',
  '*/2 * * * *',
  $$SELECT public.rpc_expire_stale_rider_assignments();$$
);
