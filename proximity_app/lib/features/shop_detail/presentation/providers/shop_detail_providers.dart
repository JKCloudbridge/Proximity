import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider lives here in this resolved Riverpod version -- same
// reorganization home_providers.dart's own import comment already documents.
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/cache/cache_ttls.dart';
import '../../../../core/cache/swr_notifier.dart';
import '../../../../core/providers.dart';
import '../../../catalog/data/models/shop_product.dart';
import '../../data/models/shop_detail.dart';
import '../../data/models/shop_sub_category.dart';
import '../../data/shop_detail_repository.dart';

final shopDetailRepositoryProvider = Provider<ShopDetailRepository>((ref) {
  return ShopDetailRepository(dio: ref.watch(dioProvider));
});

/// All four providers below are `.family`-keyed on `shopId` and
/// `.autoDispose` -- a shop detail screen is pushed/popped per shop the
/// buyer taps into from Home, so nothing here should outlive that screen or
/// leak one shop's state (especially the rail selection) into the next
/// shop visited in the same session. Sprint 15 -- SWR-cached (core/cache);
/// `.autoDispose` only tears down the *provider* (its in-memory
/// AsyncValue) when the screen is popped, same as before -- the underlying
/// Drift row survives that and is what makes the next visit to the same
/// shop within its TTL repaint instantly.
final shopDetailProvider = StateNotifierProvider.autoDispose.family<SwrNotifier<ShopDetail?>, AsyncValue<ShopDetail?>, String>((ref, shopId) {
  final repository = ref.watch(shopDetailRepositoryProvider);
  return SwrNotifier<ShopDetail?>(
    cache: ref.watch(localCacheProvider),
    cacheKey: 'shop_detail:$shopId',
    ttl: CacheTtls.shopDetail,
    fetch: () => repository.getShop(shopId),
    encode: (shop) => shop?.toJson(),
    decode: (json) => json == null ? null : ShopDetail.fromJson(json as Map<String, dynamic>),
  );
});

final shopSubCategoriesProvider = StateNotifierProvider.autoDispose.family<SwrNotifier<List<ShopSubCategory>>, AsyncValue<List<ShopSubCategory>>, String>((ref, shopId) {
  final repository = ref.watch(shopDetailRepositoryProvider);
  return SwrNotifier<List<ShopSubCategory>>(
    cache: ref.watch(localCacheProvider),
    cacheKey: 'shop_sub_categories:$shopId',
    ttl: CacheTtls.shopSubCategories,
    fetch: () => repository.getSubCategories(shopId),
    encode: (subCategories) => subCategories.map((s) => s.toJson()).toList(),
    decode: (json) => (json as List<dynamic>).map((e) => ShopSubCategory.fromJson(e as Map<String, dynamic>)).toList(),
  );
});

/// The rail's current selection -- `null` means "All", same convention
/// Home's `selectedCategoryIdProvider` established (Sprint 4).
final selectedSubCategoryIdProvider = StateProvider.autoDispose.family<String?, String>((ref, shopId) => null);

final shopProductsProvider = StateNotifierProvider.autoDispose.family<SwrNotifier<List<ShopProduct>>, AsyncValue<List<ShopProduct>>, String>((ref, shopId) {
  final subCategoryId = ref.watch(selectedSubCategoryIdProvider(shopId));
  final repository = ref.watch(shopDetailRepositoryProvider);
  return SwrNotifier<List<ShopProduct>>(
    cache: ref.watch(localCacheProvider),
    cacheKey: 'shop_products:$shopId:${subCategoryId ?? 'all'}',
    ttl: CacheTtls.shopProducts,
    fetch: () => repository.getProducts(shopId, subCategoryId: subCategoryId),
    encode: (products) => products.map((p) => p.toJson()).toList(),
    decode: (json) => (json as List<dynamic>).map((e) => ShopProduct.fromJson(e as Map<String, dynamic>)).toList(),
  );
});
