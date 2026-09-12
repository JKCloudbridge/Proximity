import 'package:supabase_flutter/supabase_flutter.dart';

/// Sprint 9 -- §8.5's "incoming-assignment notification," built as a
/// Supabase Realtime subscription rather than push.
///
/// **Why Realtime, not push, checked rather than assumed:** §8.5's own
/// prose names "push, via rpc_assign_rider" as the mechanism, but this
/// project has no FCM/APNs wiring anywhere yet -- confirmed by grepping the
/// whole repo for firebase/fcm/apns/push_token plumbing before writing this
/// file, not assumed from §11's own "FCM (Android) + APNs (iOS) push
/// wiring" line, which is explicitly Sprint 11 scope, two sprints away.
/// `users.fcm_token` (migrations/001) is a placeholder column nothing reads
/// or writes yet. §7.5 already establishes Realtime as this project's
/// live-update primitive for buyer tracking; reusing the exact same
/// mechanism here -- a Postgres Changes subscription on `orders`, filtered
/// to `rider_id = this rider's own id` -- is the documented fallback this
/// sprint chose, not a quiet substitution. A rider only sees this while the
/// app is open and this subscription is alive (no background/killed-app
/// delivery, unlike real push) -- an honest, disclosed limitation Sprint
/// 11's real push wiring will close, not this sprint's job to paper over.
///
/// Same trust-boundary note as order_status_channel.dart: this is a direct
/// client-to-Realtime subscription, authorized by RLS against the app's own
/// ambient Supabase Auth session -- migrations/038's new `orders_select_
/// rider` policy is what makes this subscription see anything at all.
///
/// A plain function, not a provider itself -- riverpod 3.4.2 (the version
/// actually resolved here, checked directly in the pub cache before writing
/// this) only exposes a `.future` modifier on Future/StreamProviders, not
/// the `.stream` companion Riverpod 2.x had, so composing "wait for the
/// rider's own id, then watch a stream keyed by it" across two separate
/// providers has no clean `.stream`-forwarding seam here. Instead
/// riderAssignmentPingForSelfProvider (rider_providers.dart) calls this
/// directly once it knows the rider's id and owns the channel's lifecycle
/// itself via `ref.onDispose`.
RealtimeChannel watchRiderAssignments({
  required SupabaseClient supabase,
  required String riderId,
  required void Function(String orderId) onChange,
}) {
  final channel = supabase.channel('rider-orders-$riderId');
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'rider_id', value: riderId),
        callback: (payload) {
          final id = payload.newRecord['id'] as String?;
          if (id != null) onChange(id);
        },
      )
      .subscribe();
  return channel;
}
