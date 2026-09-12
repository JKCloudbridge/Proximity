import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency.dart';
import '../../../auth/presentation/auth_provider.dart';
import '../../data/models/cart_item.dart';
import '../providers/cart_providers.dart';
import '../widgets/shop_cart_section.dart';

/// SPRINT_PLANNING.md §7.3/§11 Sprint 6: the cart tab -- a single scrollable
/// list, grouped into collapsible per-shop sections (§1.5's multi-shop
/// redesign: cart_items itself has no shop lock, the grouping is entirely a
/// presentation concern this screen owns). Unlike /wishlist, `/cart` is a
/// bottom-nav tab baked into the shell (app_router.dart's StatefulShellRoute)
/// and always reachable -- it isn't in `_protectedPaths`, so a guest lands
/// here rather than being redirected to /login. Auth is gated at the
/// specific action instead (same rule WishlistHeartButton already
/// established): this screen shows a sign-in prompt for a guest rather than
/// ever calling the API (routes/cart.ts's whole group requires a signed-in
/// buyer anyway).
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedIn = ref.watch(authProvider.select((s) => s.isLoggedIn));
    if (!isLoggedIn) return const _SignInPrompt();

    final cartAsync = ref.watch(cartProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(cartProvider),
      child: cartAsync.when(
        data: (items) => items.isEmpty ? const _EmptyCart() : _CartBody(items: items),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text('Could not load your cart.', style: TextStyle(color: AppColors.inkSoft))),
          ],
        ),
      ),
    );
  }
}

class _CartBody extends StatelessWidget {
  const _CartBody({required this.items});

  final List<CartItem> items;

  @override
  Widget build(BuildContext context) {
    // Grouped by shop, preserving the order shops first appear in (a plain
    // insertion-ordered Map, not a re-sort) -- §1.5's own words: "3 items
    // from Shop A, 2 items from Shop B as separate collapsible sections,"
    // client-side presentation, not a data-model constraint.
    final byShop = <String, List<CartItem>>{};
    for (final item in items) {
      byShop.putIfAbsent(item.shop.id, () => []).add(item);
    }
    final grandTotal = items.fold<int>(0, (sum, item) => sum + item.lineTotalPaise);
    final hasBlockedItems = items.any((item) => !item.isAvailable || !item.variant.inStock);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            children: [
              for (final entry in byShop.entries) ShopCartSection(shop: entry.value.first.shop, items: entry.value),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.line))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasBlockedItems)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Some items are unavailable or out of stock and won\'t be counted at checkout.',
                      style: TextStyle(color: AppColors.urgent, fontSize: 12),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total', style: TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                          Text(formatPaise(grandTotal), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                        ],
                      ),
                    ),
                    FilledButton(
                      // Checkout (§7.4) is Sprint 7's job -- same "wired now,
                      // built later" treatment the PDP's own Add to cart
                      // button got through Sprint 5.
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Checkout arrives in Sprint 7')),
                      ),
                      child: const Text('Proceed to checkout'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 100),
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shopping_cart_outlined, size: 40, color: AppColors.inkSoft),
              const SizedBox(height: 12),
              Text(
                'Your cart is empty -- browse shops near you and add something.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: () => context.go('/'), child: const Text('Browse shops')),
            ],
          ),
        ),
      ],
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 100),
        Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shopping_cart_outlined, size: 40, color: AppColors.inkSoft),
              const SizedBox(height: 12),
              Text(
                'Sign in to see items you\'ve added to your cart.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => context.push('/login'), child: const Text('Sign in')),
            ],
          ),
        ),
      ],
    );
  }
}
