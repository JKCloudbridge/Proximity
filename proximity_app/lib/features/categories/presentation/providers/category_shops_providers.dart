import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider/StateNotifier live here in this resolved Riverpod version --
// same reorganization home_providers.dart's own import comment documents.
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/cache/cache_ttls.dart';
import '../../../../core/cache/swr_notifier.dart';
import '../../../../core/providers.dart';
import '../../../catalog/data/models/shop_product.dart';
import '../../../home/data/models/nearby_shop.dart';
import '../../../home/presentation/providers/home_providers.dart';
import '../../data/categories_repository.dart';

final categoriesRepositoryProvider = Provider<CategoriesRepository>((ref) {
  return CategoriesRepository(dio: ref.watch(dioProvider));
});

/// The Categories tap-through's left rail (Sprint 15.md: "left rail lists
/// nearby shops carrying that category"). `.family`-keyed on `categoryId`
/// and `.autoDispose` -- this screen is pushed per category the buyer taps
/// from the grid, same lifetime reasoning as shop_detail_providers.dart's
/// own header. Bound to *this* screen's `categoryId` directly rather than
/// Home's shared `selectedCategoryIdProvider` -- tapping into a category
/// here shouldn't also change what Home's own chip row has selected.
///
/// SWR-cached (core/cache); same "hold at loading while buyerLocationProvider
/// resolves" shape as home_providers.dart's `nearbyShopsProvider`, same
/// reasoning -- see that provider's header.
final categoryNearbyShopsProvider =
    StateNotifierProvider.autoDispose.family<StateNotifier<AsyncValue<List<NearbyShop>>>, AsyncValue<List<NearbyShop>>, String>((ref, categoryId) {
  final locationAsync = ref.watch(buyerLocationProvider);
  if (locationAsync.isLoading) return StaticAsyncNotifier<List<NearbyShop>>(const AsyncValue.loading());

  final location = locationAsync.value;
  final repository = ref.watch(homeRepositoryProvider);
  final cacheKey = location == null
      ? 'category_shops:$categoryId:none'
      : 'category_shops:$categoryId:${location.lat.toStringAsFixed(3)}:${location.lng.toStringAsFixed(3)}';

  return SwrNotifier<List<NearbyShop>>(
    cache: ref.watch(localCacheProvider),
    cacheKey: cacheKey,
    ttl: CacheTtls.nearbyShops,
    fetch: () => location == null ? Future.value(const []) : repository.getNearbyShops(lat: location.lat, lng: location.lng, categoryId: categoryId),
    encode: (shops) => shops.map((s) => s.toJson()).toList(),
    decode: (json) => (json as List<dynamic>).map((e) => NearbyShop.fromJson(e as Map<String, dynamic>)).toList(),
  );
});

/// The rail's current selection -- `null` means "nothing explicitly picked
/// yet," in which case the screen falls back to the first shop in the
/// list, same "don't write the default into state, recompute it cheaply on
/// every build" rule product_detail_providers.dart's own
/// `selectedVariantIdProvider` already established. Unlike
/// `selectedSubCategoryIdProvider`'s "All" default, there's no "every
/// shop's products at once" view here (Sprint 15.md: the grid shows one
/// selected shop's products), so falling back to "nothing" isn't a
/// meaningful state to render.
final selectedCategoryShopIdProvider = StateProvider.autoDispose.family<String?, String>((ref, categoryId) => null);

/// The right grid -- one shop's products within this category (Sprint
/// 15.md: `GET /v1/shop/shops/:shopId/products?categoryId=` "or
/// equivalent" -- routes/catalog.ts's public `GET /shops/:shopId/products`
/// already existed with a `subCategoryId` filter; this sprint added
/// `categoryId` to it as a second, independent optional param rather than a
/// new route, see that route's own comment). `.family`-keyed on the
/// (shopId, categoryId) pair together -- a grid for one shop's products in
/// one category, re-fetched fresh whenever either half of that pair
/// changes (a different rail selection, or -- impossible today, but not
/// assumed -- a different category screen instance).
final categoryShopProductsProvider = StateNotifierProvider.autoDispose
    .family<SwrNotifier<List<ShopProduct>>, AsyncValue<List<ShopProduct>>, ({String categoryId, String shopId})>((ref, key) {
  final repository = ref.watch(categoriesRepositoryProvider);
  return SwrNotifier<List<ShopProduct>>(
    cache: ref.watch(localCacheProvider),
    cacheKey: 'category_shop_products:${key.shopId}:${key.categoryId}',
    ttl: CacheTtls.shopProducts,
    fetch: () => repository.getShopProductsByCategory(key.shopId, key.categoryId),
    encode: (products) => products.map((p) => p.toJson()).toList(),
    decode: (json) => (json as List<dynamic>).map((e) => ShopProduct.fromJson(e as Map<String, dynamic>)).toList(),
  );
});
