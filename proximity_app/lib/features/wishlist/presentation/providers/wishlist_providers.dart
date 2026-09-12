import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../auth/presentation/auth_provider.dart';
import '../../data/models/wishlist_item.dart';
import '../../data/wishlist_repository.dart';

final wishlistRepositoryProvider = Provider<WishlistRepository>((ref) {
  return WishlistRepository(dio: ref.watch(dioProvider));
});

/// Network-only, same "refetch via ref.invalidate after a write" pattern
/// addressesProvider established (Sprint 1) -- no local mutation logic here
/// either, so no StateNotifier is warranted. Guests (never logged in) get an
/// empty list rather than a 401 -- WishlistHeartButton and WishlistScreen
/// both need to render *something* for a guest without every call site
/// re-checking auth state first.
final wishlistProvider = FutureProvider.autoDispose<List<WishlistItem>>((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isLoggedIn) return const [];
  return ref.watch(wishlistRepositoryProvider).getWishlist();
});

/// Just the set of saved product ids -- what WishlistHeartButton actually
/// needs to decide filled-vs-outline, derived from the one real fetch above
/// rather than a second network call.
final wishlistProductIdsProvider = Provider.autoDispose<AsyncValue<Set<String>>>((ref) {
  return ref.watch(wishlistProvider).whenData((items) => items.map((i) => i.productId).toSet());
});
