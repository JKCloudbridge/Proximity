import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/auth_provider.dart';
import '../../data/models/frequently_bought_group.dart';
import '../providers/order_again_providers.dart';
import '../widgets/group_tile.dart';
import '../widgets/previously_bought_tile.dart';

/// Sprint 10 -- the fourth bottom-nav tab (§7.1/§7.6), replacing
/// `PlaceholderScreen(title: 'Order Again')`. §2 of Baker Ally's
/// `03_order_again_tab.md` prose spec: two sections, "Frequently Bought
/// Together" (horizontal scroll of [GroupTile]s) above "Previously Bought"
/// (a 2-column infinite-scroll grid) -- see that route's own header
/// (routes/orderAgain.ts, backend) for why this is a fresh design against
/// that doc's prose, not a port of any existing Baker Ally code (none
/// exists). Own-user data throughout -- this whole screen assumes a
/// signed-in buyer, same as the Cart tab's own sign-in-prompt convention
/// (unlike Cart, though, `/order-again` isn't in `_protectedPaths` either,
/// matching the exact same "gate the tab's content, not the tab itself"
/// reasoning app_router.dart's header already gives for `/cart`).
class OrderAgainScreen extends ConsumerWidget {
  const OrderAgainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Own-user data throughout (routes/orderAgain.ts's whole `/order-again/*`
    // group requires a signed-in buyer) -- same "gate the tab's content, not
    // the tab itself" rule CartScreen already established for `/cart`, the
    // other bottom-nav tab that isn't in `_protectedPaths`.
    final isLoggedIn = ref.watch(authProvider.select((s) => s.isLoggedIn));
    if (!isLoggedIn) return const _SignInPrompt();

    final groupsAsync = ref.watch(frequentlyBoughtGroupsProvider);
    final previouslyBought = ref.watch(previouslyBoughtProvider);

    final noGroupsYet = groupsAsync.maybeWhen(data: (g) => g.isEmpty, orElse: () => false);
    final noPreviousYet = previouslyBought.items.isEmpty && !previouslyBought.loading;

    // §8's own empty-state rule: a brand-new buyer (no orders at all) gets
    // one full-screen empty state, not two independently-empty sections
    // stacked on top of each other.
    if (noGroupsYet && noPreviousYet && previouslyBought.error == null) {
      return _EmptyState(
        onRefresh: () async {
          ref.invalidate(frequentlyBoughtGroupsProvider);
          await ref.read(previouslyBoughtProvider.notifier).refresh();
        },
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(frequentlyBoughtGroupsProvider);
        await ref.read(previouslyBoughtProvider.notifier).refresh();
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels > notification.metrics.maxScrollExtent - 400) {
            ref.read(previouslyBoughtProvider.notifier).loadMore();
          }
          return false;
        },
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Order Again', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              ),
            ),
            SliverToBoxAdapter(
              child: groupsAsync.when(
                data: (groups) => groups.isEmpty ? const SizedBox.shrink() : _FrequentlyBoughtSection(groups: groups),
                loading: () => const SizedBox.shrink(),
                error: (e, _) => const SizedBox.shrink(),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text('Previously Bought', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
            if (previouslyBought.error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text('Could not load your previous orders.', style: TextStyle(color: AppColors.inkSoft))),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.62,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => PreviouslyBoughtTile(product: previouslyBought.items[index]),
                    childCount: previouslyBought.items.length,
                  ),
                ),
              ),
            if (previouslyBought.loading)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _FrequentlyBoughtSection extends StatelessWidget {
  const _FrequentlyBoughtSection({required this.groups});

  final List<FrequentlyBoughtGroup> groups;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text('Frequently Bought Together', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          height: 260,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) => GroupTile(group: groups[index]),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined, size: 48, color: AppColors.inkSoft),
            const SizedBox(height: 16),
            Text('Sign in to see what you order again', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => context.push('/login'), child: const Text('Sign in')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.shopping_cart_outlined, size: 56, color: AppColors.inkSoft),
          const SizedBox(height: 16),
          Text('No order history yet', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            "Place your first order and we'll show your frequently bought items here",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: () => context.go('/'), child: const Text('Browse Catalog')),
        ],
      ),
    );
  }
}
