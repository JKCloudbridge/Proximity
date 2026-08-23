import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../data/address_repository.dart';
import '../../data/location_service.dart';
import '../../data/models/address.dart';

final addressRepositoryProvider = Provider<AddressRepository>((ref) {
  return AddressRepository(dio: ref.watch(dioProvider));
});

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());

/// Network-only for Sprint 1 -- no Drift caching yet (nothing here needs
/// offline support before Cart/Home exist). Simple FutureProvider rather
/// than a StateNotifier since there's no local mutation logic yet beyond
/// "refetch after a write", which `ref.invalidate` handles.
final addressesProvider = FutureProvider<List<Address>>((ref) {
  return ref.watch(addressRepositoryProvider).getAddresses();
});
