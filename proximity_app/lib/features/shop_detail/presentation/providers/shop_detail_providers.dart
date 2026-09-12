import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider lives here in this resolved Riverpod version -- same
// reorganization home_providers.dart's own import comment already documents.
import 'package:flutter_riverpod/legacy.dart';

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
/// shop visited in the same session.
final shopDetailProvider = FutureProvider.autoDispose.family<ShopDetail?, String>((ref, shopId) {
  return ref.watch(shopDetailRepositoryProvider).getShop(shopId);
});

final shopSubCategoriesProvider = FutureProvider.autoDispose.family<List<ShopSubCategory>, String>((ref, shopId) {
  return ref.watch(shopDetailRepositoryProvider).getSubCategories(shopId);
});

/// The rail's current selection -- `null` means "All", same convention
/// Home's `selectedCategoryIdProvider` established (Sprint 4).
final selectedSubCategoryIdProvider = StateProvider.autoDispose.family<String?, String>((ref, shopId) => null);

final shopProductsProvider = FutureProvider.autoDispose.family<List<ShopProduct>, String>((ref, shopId) {
  final subCategoryId = ref.watch(selectedSubCategoryIdProvider(shopId));
  return ref.watch(shopDetailRepositoryProvider).getProducts(shopId, subCategoryId: subCategoryId);
});
