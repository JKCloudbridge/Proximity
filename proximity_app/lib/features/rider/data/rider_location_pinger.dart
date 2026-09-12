import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'rider_repository.dart';

/// Sprint 9 -- §8.5's "periodic current_location updates while on_delivery,"
/// reusing `geolocator` (already a dependency since Sprint 1's address
/// geocoding, per this project's standing "don't add a second location
/// package without checking this one can't already do what's needed" rule
/// -- checked directly: `Geolocator.getPositionStream` is the real,
/// installed API for continuous updates, confirmed against the actual
/// `geolocator: 14.0.3` source in the pub cache before writing this, not
/// assumed).
///
/// A distance filter, not a fixed timer -- `LocationSettings.distanceFilter`
/// only emits a new position once the device has actually moved, which is
/// both cheaper (no pings while the rider is stationary at a red light or
/// the shop counter) and more useful (a rider standing still doesn't need
/// rpc_assign_rider's next search to re-read the same point every N
/// seconds). 50m is a reasonable street-level granularity for "which rider
/// is nearest" without flooding the backend on every few steps.
class RiderLocationPinger {
  RiderLocationPinger({required RiderRepository repository}) : _repository = repository;

  final RiderRepository _repository;
  StreamSubscription<Position>? _subscription;

  void start() {
    if (_subscription != null) return;
    _subscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 50),
    ).listen((position) {
      // Fire-and-forget: a dropped ping is not worth surfacing to the rider
      // mid-delivery, and the next movement-triggered ping supersedes it
      // anyway.
      _repository.updateLocation(lat: position.latitude, lng: position.longitude).catchError((_) {});
    });
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }
}
