import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers.dart';

/// Sprint 9 -- §7.5's live order tracking, finally wired: a Supabase
/// Realtime "Postgres Changes" subscription on `order_status_history`,
/// filtered to one order_group's child orders, with **no polling** anywhere
/// in this file.
///
/// A real architectural point, checked live against Supabase's current docs
/// before writing this (this project's standing rule for anything
/// Realtime-specific) rather than assumed from SPRINT_PLANNING.md §5.1's own
/// wording: **this is a genuinely different trust boundary from every other
/// data call in this app.** §5.1 says "all business data ... goes through
/// Dio -> the Edge Function, no direct supabase.rpc()/PostgREST calls from
/// Flutter at all" -- true, and still true here, this isn't a PostgREST
/// call. But Realtime's Postgres Changes feature authorizes itself using
/// THIS APP'S OWN ambient Supabase Auth session (`Supabase.instance.client`,
/// the same session `auth_provider.dart`'s `syncSessionToStorage` already
/// keeps live for Dio's own JWT copy) -- not the Edge Function's
/// service-role pooler connection at all. Supabase evaluates every change
/// against the SUBSCRIBING client's own RLS policies before ever sending it;
/// a row a policy doesn't cover is invisible here, silently, not an error.
/// migrations/038 is what makes the rider-side subscription
/// (rider_assignment_channel.dart) legal at all; the buyer-side one below
/// already had a covering policy since Sprint 7
/// (`order_status_history_select_own`, migrations/030) and needed no schema
/// change.
///
/// Checked live against the actually-installed `realtime_client` (2.13.0,
/// resolved via `supabase_flutter: ^2.17.2` -- see pubspec.lock) before
/// writing this, per this project's standing "check the real installed API,
/// not training-data memory" rule for anything Supabase-Realtime-specific:
/// `channel(name).onPostgresChanges(event:, schema:, table:, filter:,
/// callback:).subscribe()`, with `PostgresChangeFilter(type:
/// PostgresChangeFilterType.inFilter, column:, value: Iterable)` for a
/// multi-value filter -- confirmed directly from
/// realtime_channel.dart/types.dart in the pub cache, not remembered from
/// an older Realtime API shape.

class OrderStatusEvent {
  const OrderStatusEvent({required this.orderId, required this.status, this.note, required this.changedAt});

  final String orderId;
  final String status;
  final String? note;
  final DateTime changedAt;

  factory OrderStatusEvent.fromRow(Map<String, dynamic> row) {
    return OrderStatusEvent(
      orderId: row['order_id'] as String,
      status: row['status'] as String,
      note: row['note'] as String?,
      changedAt: DateTime.parse(row['changed_at'] as String),
    );
  }
}

/// Keyed by a stable, comma-joined string of order ids rather than a
/// `List<String>` directly -- Riverpod's `.family` compares the parameter
/// with `==`, and two `List` instances holding the same elements are never
/// `==` to each other in Dart, which would resubscribe on every rebuild
/// instead of once. `OrderConfirmationScreen`/`order_group.dart`'s own
/// `orders` list is what builds this key.
final orderStatusEventsProvider = StreamProvider.autoDispose.family<OrderStatusEvent, String>((ref, orderIdsKey) {
  final orderIds = orderIdsKey.split(',').where((id) => id.isNotEmpty).toList();
  if (orderIds.isEmpty) return const Stream<OrderStatusEvent>.empty();

  final supabase = ref.watch(supabaseClientProvider);
  final channel = supabase.channel('order-status-$orderIdsKey');

  final controller = StreamController<OrderStatusEvent>.broadcast();

  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'order_status_history',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.inFilter, column: 'order_id', value: orderIds),
        callback: (payload) {
          if (!controller.isClosed) controller.add(OrderStatusEvent.fromRow(payload.newRecord));
        },
      )
      .subscribe();

  ref.onDispose(() {
    controller.close();
    supabase.removeChannel(channel);
  });

  return controller.stream;
});
