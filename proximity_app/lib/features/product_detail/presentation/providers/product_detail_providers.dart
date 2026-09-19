import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider lives here in this resolved Riverpod version -- same
// reorganization home_providers.dart's own import comment already documents.
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/cache/cache_ttls.dart';
import '../../../../core/cache/swr_notifier.dart';
import '../../../../core/providers.dart';
import '../../data/models/product_detail.dart';
import '../../data/product_detail_repository.dart';

final productDetailRepositoryProvider = Provider<ProductDetailRepository>((ref) {
  return ProductDetailRepository(dio: ref.watch(dioProvider));
});

/// `.family`-keyed on `productId` and `.autoDispose` -- same reasoning as
/// shop_detail_providers.dart's own header: a PDP is pushed/popped per
/// product, nothing here should outlive that screen. Sprint 15 -- SWR-cached
/// (core/cache), same "the Drift row, not the provider, is what makes a
/// repeat visit instant" note as shop_detail_providers.dart's own header.
final productDetailProvider = StateNotifierProvider.autoDispose.family<SwrNotifier<ProductDetail?>, AsyncValue<ProductDetail?>, String>((ref, productId) {
  final repository = ref.watch(productDetailRepositoryProvider);
  return SwrNotifier<ProductDetail?>(
    cache: ref.watch(localCacheProvider),
    cacheKey: 'product_detail:$productId',
    ttl: CacheTtls.productDetail,
    fetch: () => repository.getProduct(productId),
    encode: (product) => product?.toJson(),
    decode: (json) => json == null ? null : ProductDetail.fromJson(json as Map<String, dynamic>),
  );
});

/// The PDP's explicitly-tapped variant, per product -- `null` until the
/// buyer taps a chip. `null` is not "no selection" for display purposes;
/// the PDP screen falls back to a sensible default (first in-stock, else
/// the first variant at all) whenever this is `null`, rather than writing
/// that default into state on load -- one less effect to get wrong, since
/// the fallback is cheap to recompute on every build.
final selectedVariantIdProvider = StateProvider.autoDispose.family<String?, String>((ref, productId) => null);
