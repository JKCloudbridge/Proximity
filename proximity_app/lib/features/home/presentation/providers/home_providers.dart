import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider moved here in Riverpod 3.x, same reorganization
// auth_provider.dart's header already documents for StateNotifier -- see
// that comment for why this is the correct current surface, not a
// deprecated fallback.
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/cache/cache_ttls.dart';
import '../../../../core/cache/swr_notifier.dart';
import '../../../../core/providers.dart';
import '../../../addresses/data/location_service.dart';
import '../../../addresses/presentation/providers/address_providers.dart';
import '../../../auth/presentation/auth_provider.dart';
import '../../../catalog/data/models/repeat_product.dart';
import '../../data/home_repository.dart';
import '../../data/models/category.dart';
import '../../data/models/nearby_shop.dart';
import '../../data/models/recommended_product.dart';

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return HomeRepository(dio: ref.watch(dioProvider));
});

/// Sprint 15 -- stale-while-revalidate (core/cache/swr_notifier.dart):
/// instant repaint from a warm, still-fresh cache while a live refresh runs
/// underneath, cold-cache behavior unchanged from the plain FutureProvider
/// this replaces. `StateNotifierProvider`, not `.autoDispose` -- same
/// lifetime as before (this was a plain, non-autoDispose FutureProvider),
/// the 20-category list is cheap to keep warm for the app's whole session.
final categoriesProvider = StateNotifierProvider<SwrNotifier<List<Category>>, AsyncValue<List<Category>>>((ref) {
  final repository = ref.watch(homeRepositoryProvider);
  return SwrNotifier<List<Category>>(
    cache: ref.watch(localCacheProvider),
    cacheKey: 'categories',
    ttl: CacheTtls.categories,
    fetch: repository.getCategories,
    encode: (categories) => categories.map((c) => c.toJson()).toList(),
    decode: (json) => (json as List<dynamic>).map((e) => Category.fromJson(e as Map<String, dynamic>)).toList(),
  );
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
/// this without any manual invalidate() call. Sprint 15 -- SWR-cached
/// (core/cache), keyed on the same two inputs the query itself depends on;
/// lat/lng rounded to 3 decimal places (~110m) for the cache key only, not
/// the actual query, so ordinary GPS jitter between two visits still hits
/// the same cache entry instead of missing on noise in the 5th decimal
/// place. While [buyerLocationProvider] is itself still resolving, this
/// stays in a plain loading state rather than treating "not resolved yet"
/// the same as "resolved to null" -- the latter would flash the "no shops
/// here" empty state for a moment on every cold start, not a loading
/// spinner, which is a real, visible regression from the FutureProvider
/// this replaces.
final nearbyShopsProvider = StateNotifierProvider<StateNotifier<AsyncValue<List<NearbyShop>>>, AsyncValue<List<NearbyShop>>>((ref) {
  final locationAsync = ref.watch(buyerLocationProvider);
  if (locationAsync.isLoading) return StaticAsyncNotifier<List<NearbyShop>>(const AsyncValue.loading());

  final location = locationAsync.value;
  final categoryId = ref.watch(selectedCategoryIdProvider);
  final repository = ref.watch(homeRepositoryProvider);
  final cacheKey = location == null
      ? 'nearby_shops:none'
      : 'nearby_shops:${location.lat.toStringAsFixed(3)}:${location.lng.toStringAsFixed(3)}:${categoryId ?? 'all'}';

  return SwrNotifier<List<NearbyShop>>(
    cache: ref.watch(localCacheProvider),
    cacheKey: cacheKey,
    ttl: CacheTtls.nearbyShops,
    fetch: () => location == null ? Future.value(const []) : repository.getNearbyShops(lat: location.lat, lng: location.lng, categoryId: categoryId),
    encode: (shops) => shops.map((s) => s.toJson()).toList(),
    decode: (json) => (json as List<dynamic>).map((e) => NearbyShop.fromJson(e as Map<String, dynamic>)).toList(),
  );
});

/// Sprint 6's "Recommended for you" (§7.1) -- the second of Home's three
/// named sections to actually get built (Shops-near-you was Sprint 4;
/// Frequently-Bought is Sprint 10's job, order history doesn't exist yet).
/// Deliberately does NOT watch [selectedCategoryIdProvider] -- §7.1's
/// "category-click filtering across sections" was named for Shops-near-you
/// specifically, and a personalized/trending feed re-filtering by the same
/// chips would need its own product-category join this endpoint doesn't do;
/// revisit if a later sprint's feedback actually asks for it. Re-fetches
/// only when location changes. Sprint 15 -- SWR-cached (core/cache), same
/// "hold at loading while buyerLocationProvider itself resolves" shape as
/// [nearbyShopsProvider] just above, same reasoning.
final recommendedProductsProvider = StateNotifierProvider<StateNotifier<AsyncValue<List<RecommendedProduct>>>, AsyncValue<List<RecommendedProduct>>>((ref) {
  final locationAsync = ref.watch(buyerLocationProvider);
  if (locationAsync.isLoading) return StaticAsyncNotifier<List<RecommendedProduct>>(const AsyncValue.loading());

  final location = locationAsync.value;
  final repository = ref.watch(homeRepositoryProvider);
  final cacheKey = location == null ? 'recommended:none' : 'recommended:${location.lat.toStringAsFixed(3)}:${location.lng.toStringAsFixed(3)}';

  return SwrNotifier<List<RecommendedProduct>>(
    cache: ref.watch(localCacheProvider),
    cacheKey: cacheKey,
    ttl: CacheTtls.recommendedProducts,
    fetch: () => location == null ? Future.value(const []) : repository.getRecommended(lat: location.lat, lng: location.lng),
    encode: (products) => products.map((p) => p.toJson()).toList(),
    decode: (json) => (json as List<dynamic>).map((e) => RecommendedProduct.fromJson(e as Map<String, dynamic>)).toList(),
  );
});

/// Sprint 10 -- §7.1's third, conditional Home section: "Frequently Bought
/// at >=3 patterns" (repeatPurchases.ts's own header on the backend defines
/// exactly what a "qualifying repeat-purchase pattern" means here). Own-user
/// data with no guest fallback (unlike Recommended-for-you, which
/// personalizes but still works for guests) -- a guest has no purchase
/// history to gate on, so this simply isn't fetched at all when signed out,
/// same "gated at the specific data need" shape buyerLocationProvider
/// already uses for its own signed-in-only branch. Sprint 15 -- SWR-cached
/// (core/cache), keyed per-user (own-user data, §5.2) so one signed-in
/// buyer's cached repeat-purchase list on a shared/test device can never be
/// served to another account.
final frequentlyBoughtGateProvider =
    StateNotifierProvider<StateNotifier<AsyncValue<({bool qualifies, List<RepeatProduct> products})>>, AsyncValue<({bool qualifies, List<RepeatProduct> products})>>((ref) {
  final auth = ref.watch(authProvider);
  final repository = ref.watch(homeRepositoryProvider);

  if (!auth.isLoggedIn) {
    return StaticAsyncNotifier<({bool qualifies, List<RepeatProduct> products})>(
      const AsyncValue.data((qualifies: false, products: <RepeatProduct>[])),
    );
  }

  return SwrNotifier<({bool qualifies, List<RepeatProduct> products})>(
    cache: ref.watch(localCacheProvider),
    cacheKey: 'frequently_bought:${auth.userId}',
    ttl: CacheTtls.frequentlyBought,
    fetch: repository.getFrequentlyBought,
    encode: (result) => {'qualifies': result.qualifies, 'products': result.products.map((p) => p.toJson()).toList()},
    decode: (json) {
      final map = json as Map<String, dynamic>;
      return (
        qualifies: map['qualifies'] as bool,
        products: (map['products'] as List<dynamic>).map((e) => RepeatProduct.fromJson(e as Map<String, dynamic>)).toList(),
      );
    },
  );
});
