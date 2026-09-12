import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider moved here in Riverpod 3.x, same reorganization
// auth_provider.dart's header already documents for StateNotifier -- see
// that comment for why this is the correct current surface, not a
// deprecated fallback.
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/providers.dart';
import '../../../addresses/data/location_service.dart';
import '../../../addresses/presentation/providers/address_providers.dart';
import '../../../auth/presentation/auth_provider.dart';
import '../../data/home_repository.dart';
import '../../data/models/category.dart';
import '../../data/models/nearby_shop.dart';
import '../../data/models/recommended_product.dart';

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return HomeRepository(dio: ref.watch(dioProvider));
});

/// Network-only, same "no Drift caching yet" call every other Sprint 1-3
/// list provider makes -- Home's own offline cache (if it's ever needed) is
/// a Sprint 13 polish concern, not this sprint's.
final categoriesProvider = FutureProvider<List<Category>>((ref) {
  return ref.watch(homeRepositoryProvider).getCategories();
});

/// §7.1's category chip row selection, shared across every Home section
/// that filters by it. Only one real section reads it this sprint (Shops
/// near you) -- Recommended/Frequently-Bought (Sprint 6/10) are the reason
/// this lives in its own provider instead of being private state inside the
/// shops-near-you widget, so those later sections can `ref.watch` the same
/// selection without Home needing to be restructured to introduce it then.
/// `null` means "All" (no filter).
final selectedCategoryIdProvider = StateProvider<String?>((ref) => null);

typedef BuyerLocation = ({double lat, double lng, String label});

/// The lat/lng (and a human label for the top bar) the "Shops near you"
/// query and address chip both use. Prefers the buyer's saved default
/// address (already resolved, no permission prompt) over a live GPS fix --
/// falls back to GPS for guests (no addresses to have) and signed-in users
/// who haven't added one yet. `null` means neither source resolved (no
/// saved address AND no location permission) -- Home's empty state handles
/// that explicitly rather than silently showing nothing.
final buyerLocationProvider = FutureProvider<BuyerLocation?>((ref) async {
  final auth = ref.watch(authProvider);
  if (auth.isLoggedIn) {
    final addresses = await ref.watch(addressesProvider.future);
    if (addresses.isNotEmpty) {
      var defaultAddress = addresses.first;
      for (final address in addresses) {
        if (address.isDefault) {
          defaultAddress = address;
          break;
        }
      }
      return (lat: defaultAddress.lat, lng: defaultAddress.lng, label: defaultAddress.shortLine);
    }
  }

  final locationService = ref.watch(locationServiceProvider);
  final permission = await locationService.ensurePermission();
  if (permission != LocationPermissionResult.granted) return null;
  final position = await locationService.getCurrentPosition();
  return (lat: position.lat, lng: position.lng, label: 'Current location');
});

/// Re-fetches whenever the resolved location or the selected category
/// changes -- both are plain `ref.watch`es, not `.read`s, specifically so
/// picking a different default address or tapping a category chip drives
/// this without any manual invalidate() call.
final nearbyShopsProvider = FutureProvider<List<NearbyShop>>((ref) async {
  final location = await ref.watch(buyerLocationProvider.future);
  if (location == null) return const [];
  final categoryId = ref.watch(selectedCategoryIdProvider);
  return ref.watch(homeRepositoryProvider).getNearbyShops(lat: location.lat, lng: location.lng, categoryId: categoryId);
});

/// Sprint 6's "Recommended for you" (§7.1) -- the second of Home's three
/// named sections to actually get built (Shops-near-you was Sprint 4;
/// Frequently-Bought is Sprint 10's job, order history doesn't exist yet).
/// Deliberately does NOT watch [selectedCategoryIdProvider] -- §7.1's
/// "category-click filtering across sections" was named for Shops-near-you
/// specifically, and a personalized/trending feed re-filtering by the same
/// chips would need its own product-category join this endpoint doesn't do;
/// revisit if a later sprint's feedback actually asks for it. Re-fetches
/// only when location changes.
final recommendedProductsProvider = FutureProvider<List<RecommendedProduct>>((ref) async {
  final location = await ref.watch(buyerLocationProvider.future);
  if (location == null) return const [];
  return ref.watch(homeRepositoryProvider).getRecommended(lat: location.lat, lng: location.lng);
});
