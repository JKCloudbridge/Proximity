import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../data/models/rider_order.dart';
import '../../data/models/rider_profile.dart';
import '../../data/rider_assignment_channel.dart';
import '../../data/rider_document_service.dart';
import '../../data/rider_location_pinger.dart';
import '../../data/rider_repository.dart';

final riderRepositoryProvider = Provider<RiderRepository>((ref) {
  return RiderRepository(dio: ref.watch(dioProvider));
});

final riderDocumentServiceProvider = Provider<RiderDocumentService>((ref) {
  return RiderDocumentService(supabase: ref.watch(supabaseClientProvider));
});

/// Network-only, same "no Drift caching yet" call as addressesProvider --
/// re-fetched via ref.invalidate after a successful submit.
final myRiderProfileProvider = FutureProvider<RiderProfile?>((ref) {
  return ref.watch(riderRepositoryProvider).getMyProfile();
});

/// Sprint 9 -- the rider's own active orders, re-fetched whenever the
/// Realtime assignment ping fires (see below) or the rider pulls to
/// refresh. `.autoDispose` -- RiderHomeScreen is the only consumer, and
/// nothing about a rider's assignment list should survive that screen being
/// popped (same reasoning shop_detail_providers.dart's own `.family`/
/// `.autoDispose` combo gave in Sprint 5).
final riderOrdersProvider = FutureProvider.autoDispose<List<RiderOrder>>((ref) {
  // Re-run this provider every time a ping arrives for this rider -- see
  // _RiderOrdersWatcher below for why that wiring lives on the widget side,
  // not here (a FutureProvider can't watch a StreamProvider keyed by a value
  // only known once myRiderProfileProvider itself resolves, without forcing
  // every consumer through an AsyncValue-of-AsyncValue).
  return ref.watch(riderRepositoryProvider).getMyOrders();
});

/// A live ping stream keyed off the rider's own id, once known -- kept as
/// its own provider (rather than folded into riderOrdersProvider) so
/// RiderHomeScreen can listen to it purely for its *side effect*
/// (invalidating riderOrdersProvider) without the ping value itself needing
/// to flow through the same AsyncValue the order list renders from. Calls
/// watchRiderAssignments directly (see that file's header for why -- no
/// `.stream` modifier exists on this project's actually-resolved riverpod
/// 3.4.2 to forward a nested StreamProvider's output through).
final riderAssignmentPingForSelfProvider = StreamProvider.autoDispose<String>((ref) async* {
  final profile = await ref.watch(myRiderProfileProvider.future);
  if (profile == null) return;

  final supabase = ref.watch(supabaseClientProvider);
  final controller = StreamController<String>.broadcast();
  final channel = watchRiderAssignments(
    supabase: supabase,
    riderId: profile.id,
    onChange: (id) {
      if (!controller.isClosed) controller.add(id);
    },
  );
  ref.onDispose(() {
    controller.close();
    supabase.removeChannel(channel);
  });

  yield* controller.stream;
});

final riderLocationPingerProvider = Provider.autoDispose<RiderLocationPinger>((ref) {
  final pinger = RiderLocationPinger(repository: ref.watch(riderRepositoryProvider));
  ref.onDispose(pinger.stop);
  return pinger;
});
