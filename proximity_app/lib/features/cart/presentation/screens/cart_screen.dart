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
              // Keyed by shop id -- ShopCartSection is a StatefulWidget (its
              // own collapse/expand flag), and this list shrinks whenever a
              // shop's last item is removed ("Remove all from this shop," or
              // the last item in it going to 0). Without an explicit key,
              // Flutter reconciles by position and a shop the buyer manually
              // collapsed could end up handing that collapsed state to a
              // completely different shop that shifts into its old slot.
              for (final entry in byShop.entries)
                ShopCartSection(key: ValueKey(entry.key), shop: entry.value.first.shop, items: entry.value),
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
                // Corrected in Sprint 7: this used to say unavailable items
                // "won't be counted at checkout," which turned out not to be
                // true once rpc_place_order existed -- that function refuses
                // the entire checkout if any line is unavailable
                // (CART_HAS_UNAVAILABLE_ITEMS, migrations/032) rather than
                // quietly dropping the bad lines. Telling the buyer to
                // remove them is the accurate instruction.
                if (hasBlockedItems)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Remove the unavailable items above to check out.',
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
                      // Real as of Sprint 7 -- this was an honest "arrives in
                      // Sprint 7" snackbar through Sprint 6, same "wired now,
                      // built later" treatment the PDP's own Add to cart
                      // button got through Sprint 5.
                      //
                      // Blocked while every line in the cart is unavailable:
                      // rpc_place_order refuses the whole checkout if any
                      // item has gone inactive/out-of-stock
                      // (CART_HAS_UNAVAILABLE_ITEMS, migrations/032), so
                      // sending the buyer to a checkout that cannot succeed
                      // would just be a slower way to show the same problem.
                      onPressed: hasBlockedItems ? null : () => context.push('/checkout'),
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
