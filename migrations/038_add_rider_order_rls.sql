-- Sprint 9: RLS policies letting a rider read their own assigned orders and
-- those orders' status history -- a real, checked-not-assumed gap found
-- while designing this sprint's Realtime work, not named in §4.8/§4.9's own
-- policy lists (which predate `orders.rider_id` ever being set by anything).
--
-- Why this migration exists at all, when §5.1 otherwise treats RLS as a
-- defense-in-depth backstop the Edge Function's own service-role connection
-- never relies on: **Supabase Realtime's "Postgres Changes" feature is a
-- SECOND, genuinely different trust boundary from the Edge Function's own
-- pooler connection**, and this sprint is the first time this project uses
-- it. Checked live against Supabase's current docs before writing this
-- (this project's standing rule for anything Realtime-specific, same
-- discipline as the supabase_flutter API version check below): a Realtime
-- "Postgres Changes" subscription authorizes itself using the CONNECTING
-- CLIENT'S OWN JWT (proximity_app's ambient Supabase Auth session --
-- Supabase.instance.client, the same session dio_client.dart's interceptor
-- already reads a copy of, per auth_provider.dart's syncSessionToStorage) --
-- not the Edge Function's service-role pooler connection at all. Realtime
-- evaluates each change against the SUBSCRIBING user's own RLS policies
-- before ever sending it to that client; a row a policy doesn't cover is
-- invisible to Realtime, full stop, regardless of what the Edge Function's
-- own routes allow. This is the one place in this whole project where RLS
-- is the live, load-bearing enforcement mechanism, not a backstop --
-- documented explicitly here, and in SPRINT_PLANNING.md §5.1's own text,
-- rather than left to be rediscovered the hard way.
--
-- Without this migration, a rider's Flutter app subscribing to `orders`
-- (to learn about a new assignment, §8.5 -- see Sprint 9.md's own decision
-- on why Realtime is this sprint's chosen mechanism, not push) or to
-- `order_status_history` (to read their own delivery's timeline) would
-- receive precisely zero rows -- not an error, just silence -- because
-- neither table had a rider-facing SELECT policy at all until now. §5.2's
-- own RLS-pattern table already named "Rider-own data ... assigned orders
-- (read + status update only)" as a planned ownership class back in Sprint
-- 1 -- this is that class, finally implemented once a real consumer
-- (Realtime) needs it to actually exist.

DROP POLICY IF EXISTS orders_select_rider ON orders;
CREATE POLICY orders_select_rider ON orders
  FOR SELECT USING (rider_id = (SELECT id FROM riders WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS order_status_history_select_rider ON order_status_history;
CREATE POLICY order_status_history_select_rider ON order_status_history
  FOR SELECT USING (
    order_id IN (
      SELECT o.id FROM orders o
      WHERE o.rider_id = (SELECT id FROM riders WHERE user_id = auth.uid())
    )
  );

-- No rider-facing UPDATE/INSERT policy on either table, deliberately: every
-- write a rider makes (accepting an assignment, advancing the delivery
-- ladder) goes through rpc_rider_accept_order / rpc_rider_update_status
-- (both SECURITY DEFINER, both REVOKEd from authenticated/anon, §5.1) via
-- the Edge Function -- never a direct client-side UPDATE, Realtime or
-- otherwise. Matches the "rider-own data" row in §5.2 exactly: read
-- (backstop AND, now, live-enforcement for Realtime) + status update
-- through the RPC layer, nothing else.
