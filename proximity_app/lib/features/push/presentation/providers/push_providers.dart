import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../core/push/push_service.dart';
import '../../data/push_repository.dart';

final pushRepositoryProvider = Provider<PushRepository>((ref) {
  return PushRepository(dio: ref.watch(dioProvider));
});

/// One instance for the app's lifetime -- `PushService` holds no per-call
/// state beyond its own one-time "is the tap listener already wired" guard,
/// so a single shared instance (not `.autoDispose`) is correct. Wires
/// notification-tap handling the moment it's first read (see this
/// provider's own constructor call below) -- `ProximityApp.build()`
/// (main.dart) reads it once alongside `routerProvider`, which is what
/// actually triggers that first-and-only wiring.
final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(ref);
  service.wireNotificationTapHandling();
  return service;
});
