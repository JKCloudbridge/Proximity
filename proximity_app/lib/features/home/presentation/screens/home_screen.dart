import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../addresses/presentation/providers/address_providers.dart';
import '../../data/models/nearby_shop.dart';
import '../providers/home_providers.dart';
import '../widgets/category_chip_row.dart';
import '../widgets/shop_card.dart';

/// SPRINT_PLANNING.md §7.1/§11 Sprint 4: category chip row + "Shops near
/// you", sorted by distance and filterable by category. Frequently-Bought
/// and Recommended-for-you (the other two Home sections named in §7.1) are
/// Sprint 6/10's job -- their data sources (`product_cross_sell`, order
/// history) don't exist yet, so this screen deliberately has one real
/// section, not three placeholder ones pretending to be finished.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final locationAsync = ref.watch(buyerLocationProvider);
    final shopsAsync = ref.watch(nearbyShopsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(categoriesProvider);
        ref.invalidate(buyerLocationProvider);
        ref.invalidate(nearbyShopsProvider);
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: categoriesAsync.when(
              data: (categories) => Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 12),
                child: CategoryChipRow(categories: categories),
              ),
              loading: () => const SizedBox(height: 40),
              error: (error, stackTrace) => const SizedBox.shrink(),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('Shops near you', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
          ),
          locationAsync.when(
            data: (location) => location == null
                ? const SliverFillRemaining(hasScrollBody: false, child: _LocationPrompt())
                : _shopsSliver(context, shopsAsync),
            loading: () => const SliverToBoxAdapter(child: _CenteredLoader()),
            error: (error, stackTrace) => const SliverFillRemaining(hasScrollBody: false, child: _LocationPrompt()),
          ),
        ],
      ),
    );
  }

  Widget _shopsSliver(BuildContext context, AsyncValue<List<NearbyShop>> shopsAsync) {
    return shopsAsync.when(
      data: (shops) => shops.isEmpty
          ? const SliverFillRemaining(hasScrollBody: false, child: _EmptyShopsState())
          : SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => ShopCard(shop: shops[index], onTap: () => _openShop(context, shops[index])),
                childCount: shops.length,
              ),
            ),
      loading: () => const SliverToBoxAdapter(child: _CenteredLoader()),
      error: (error, stackTrace) => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('Could not load nearby shops.', style: TextStyle(color: AppColors.inkSoft))),
        ),
      ),
    );
  }

  void _openShop(BuildContext context, NearbyShop shop) {
    // Shop detail is now real (Sprint 5) -- this was a "coming in Sprint 5"
    // snackbar through Sprint 4, per that sprint's own write-up.
    context.push('/shop/${shop.id}');
  }
}

class _CenteredLoader extends StatelessWidget {
  const _CenteredLoader();

  @override
  Widget build(BuildContext context) {
    return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
  }
}

class _EmptyShopsState extends StatelessWidget {
  const _EmptyShopsState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Text(
          'No approved shops within their service area yet.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
        ),
      ),
    );
  }
}

/// Shown when [buyerLocationProvider] resolves to `null` -- no saved
/// default address and no granted location permission. Both actions below
/// re-resolve the same provider on return, so the moment either one
/// succeeds this screen replaces itself with the real shop list.
class _LocationPrompt extends ConsumerWidget {
  const _LocationPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_off_outlined, size: 40, color: AppColors.inkSoft),
          const SizedBox(height: 12),
          Text(
            'Turn on location, or add an address, to see shops near you.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              await ref.read(locationServiceProvider).ensurePermission();
              ref.invalidate(buyerLocationProvider);
            },
            child: const Text('Enable location'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.push('/addresses/new'),
            child: const Text('Add an address'),
          ),
        ],
      ),
    );
  }
}
