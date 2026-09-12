import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../auth/presentation/auth_provider.dart';
import '../../data/cart_repository.dart';
import '../../data/models/cart_item.dart';

final cartRepositoryProvider = Provider<CartRepository>((ref) {
  return CartRepository(dio: ref.watch(dioProvider));
});

/// Network-only, same "refetch via ref.invalidate after a write" pattern
/// wishlistProvider established -- guests get an empty list rather than a
/// 401, same reasoning: both the bottom-nav badge (AppShell) and CartScreen
/// need to render *something* for a guest without each re-checking auth
/// state first.
final cartProvider = FutureProvider.autoDispose<List<CartItem>>((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isLoggedIn) return const [];
  return ref.watch(cartRepositoryProvider).getCart();
});

/// AppShell's bottom-nav Cart badge (its own header comment, written back in
/// Sprint 1, named this sprint as the one that wires it up). Sum of
/// quantities, not row count -- "3 items, one of them x2" should read as 4,
/// matching how the cart screen itself will show it.
final cartItemCountProvider = Provider.autoDispose<int>((ref) {
  final items = ref.watch(cartProvider).value ?? const [];
  return items.fold<int>(0, (sum, item) => sum + item.quantity);
});
