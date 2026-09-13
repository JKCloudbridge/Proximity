import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateNotifier lives here in this resolved Riverpod version -- same
// reorganization auth_provider.dart's/checkout_providers.dart's own headers
// already document; it's the current supported surface, not a deprecated
// fallback.
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/providers.dart';
import '../../../catalog/data/models/repeat_product.dart';
import '../../data/models/frequently_bought_group.dart';
import '../../data/order_again_repository.dart';

final orderAgainRepositoryProvider = Provider<OrderAgainRepository>((ref) {
  return OrderAgainRepository(dio: ref.watch(dioProvider));
});

/// §11's exit criteria doesn't gate this tab on anything -- unlike Home's
/// Frequently-Bought section (routes/home.ts's own >=3 threshold), Order
/// Again's own "Frequently Bought Together" section simply renders nothing
/// (§8's own empty-state rule) when the buyer has no qualifying bundles yet.
/// `.autoDispose`: only interesting while the tab is visible, re-fetched
/// fresh on pull-to-refresh rather than kept warm across tab switches.
final frequentlyBoughtGroupsProvider = FutureProvider.autoDispose<List<FrequentlyBoughtGroup>>((ref) {
  return ref.watch(orderAgainRepositoryProvider).getFrequentlyBought();
});

const _previouslyBoughtPageSize = 20;

/// §6's own rule: infinite scroll, not numbered pages. A StateNotifier,
/// same shape CheckoutDraftNotifier established for "real multi-field state
/// that has to stay internally consistent across calls" -- here that's
/// "don't lose earlier pages, don't double-load while a load is already in
/// flight, know when the list has genuinely ended."
class PreviouslyBoughtState {
  const PreviouslyBoughtState({
    this.items = const [],
    this.loading = false,
    this.hasMore = true,
    this.error,
  });

  final List<RepeatProduct> items;
  final bool loading;
  final bool hasMore;
  final Object? error;

  PreviouslyBoughtState copyWith({List<RepeatProduct>? items, bool? loading, bool? hasMore, Object? error, bool clearError = false}) {
    return PreviouslyBoughtState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class PreviouslyBoughtNotifier extends StateNotifier<PreviouslyBoughtState> {
  PreviouslyBoughtNotifier(this._repository) : super(const PreviouslyBoughtState()) {
    loadMore();
  }

  final OrderAgainRepository _repository;

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final result = await _repository.getPreviouslyBought(limit: _previouslyBoughtPageSize, offset: state.items.length);
      state = state.copyWith(items: [...state.items, ...result.items], loading: false, hasMore: result.hasMore);
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> refresh() async {
    state = const PreviouslyBoughtState();
    await loadMore();
  }
}

final previouslyBoughtProvider = StateNotifierProvider.autoDispose<PreviouslyBoughtNotifier, PreviouslyBoughtState>((ref) {
  return PreviouslyBoughtNotifier(ref.watch(orderAgainRepositoryProvider));
});
