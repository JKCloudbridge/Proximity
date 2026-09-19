import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../addresses/presentation/providers/address_providers.dart';
import '../../../catalog/data/models/repeat_product.dart';
import '../../data/models/nearby_shop.dart';
import '../../data/models/recommended_product.dart';
import '../providers/home_providers.dart';
import '../widgets/category_chip_row.dart';
import '../widgets/frequently_bought_card.dart';
import '../widgets/recommended_product_card.dart';
import '../widgets/shop_card.dart';

/// SPRINT_PLANNING.md §7.1/§11: category chip row, conditional "Frequently
/// Bought" (Sprint 10), "Recommended for you" (Sprint 6), and "Shops near
/// you" (Sprint 4), sorted by distance and filterable by category.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final locationAsync = ref.watch(buyerLocationProvider);
    final shopsAsync = ref.watch(nearbyShopsProvider);
    final recommendedAsync = ref.watch(recommendedProductsProvider);
    final frequentlyBoughtAsync = ref.watch(frequentlyBoughtGateProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(categoriesProvider);
        ref.invalidate(buyerLocationProvider);
        ref.invalidate(nearbyShopsProvider);
        ref.invalidate(recommendedProductsProvider);
        ref.invalidate(frequentlyBoughtGateProvider);
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
          // §7.1's order: chips -> Frequently Bought (conditional, Sprint
          // 10) -> Recommended for you -> Shops near you. This section
          // renders nothing at all -- not even a heading -- unless
          // `qualifies` is true (repeatPurchases.ts's own header defines the
          // >=3-qualifying-products gate); a `qualifies: false` response and
          // a still-loading/error response look identical to the buyer, on
          // purpose, same "don't show a section with nothing under it" rule
          // Recommended-for-you's own empty case already established.
          SliverToBoxAdapter(
            child: frequentlyBoughtAsync.when(
              data: (result) => !result.qualifies ? const SizedBox.shrink() : _FrequentlyBoughtSection(products: result.products),
              loading: () => const SizedBox.shrink(),
              error: (error, stackTrace) => const SizedBox.shrink(),
            ),
          ),
          SliverToBoxAdapter(
            child: recommendedAsync.when(
              data: (products) => products.isEmpty ? const SizedBox.shrink() : _RecommendedSection(products: products),
              loading: () => const SizedBox.shrink(),
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

/// §7.1's "Recommended for you, 2-row horizontal scroll" -- a horizontal
/// [GridView] with `crossAxisCount: 2` (rows, since the scroll axis is
/// horizontal here) rather than a single-row `ListView`, matching that
/// wording literally rather than approximating it with one long row.
class _RecommendedSection extends StatelessWidget {
  const _RecommendedSection({required this.products});

  final List<RecommendedProduct> products;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text('Recommended for you', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          height: 480,
          child: GridView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // Sprint 14 fix: childAspectRatio is cross-axis-extent ÷
            // main-axis-extent -- for a *horizontally* scrolling grid the
            // cross axis is height and the main axis is width, so the old
            // `childAspectRatio: 0.72` here actually computed each card's
            // WIDTH as height ÷ 0.72 (~257dp wide against a ~185dp-tall
            // row) -- a card wider than tall, forced to hold a square image
            // plus three text lines, which can never fit. That produced a
            // real overflow, not a cosmetic one -- this section had never
            // actually rendered on a real screen before this sprint.
            // `mainAxisExtent` sets the main-axis (width) extent directly
            // and unambiguously, sidestepping the aspect-ratio direction
            // confusion entirely; 480 total height / 2 rows leaves ~225dp
            // per row for a 150dp-wide card -- ~150dp square image + ~75dp
            // for the text block below it, matching RecommendedProductCard's
            // actual content height with a small margin.
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 150,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return RecommendedProductCard(product: product, onTap: () => context.push('/product/${product.productId}'));
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// §7.1's conditional "Frequently Bought" section -- same 2-row horizontal
/// scroll shape as [_RecommendedSection], different data source and gate.
class _FrequentlyBoughtSection extends StatelessWidget {
  const _FrequentlyBoughtSection({required this.products});

  final List<RepeatProduct> products;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text('Frequently Bought', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          height: 480,
          child: GridView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // Same Sprint 14 fix as _RecommendedSection above -- identical
            // card content shape (square image + 3 text lines), identical
            // bug, identical fix.
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 150,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return FrequentlyBoughtCard(product: product, onTap: () => context.push('/product/${product.productId}'));
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _CenteredLoader extends StatelessWidget {
  const _CenteredLoader();

  @override
  Widget build(BuildContext context) {
    return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
  }
}

/// Feedback fix: this used to be bare text with no visual anchor -- brought
/// in line with `_LocationPrompt`'s own icon-plus-message shape just above
/// it in this same file, rather than being the one empty state in this
/// screen that looks unfinished next to it.
class _EmptyShopsState extends StatelessWidget {
  const _EmptyShopsState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.storefront_outlined, size: 48, color: AppColors.inkSoft),
          const SizedBox(height: 12),
          Text(
            'No shops here yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            "We don't have any approved shops in your area yet -- check back soon.",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
          ),
        ],
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
            onPressed: () async {
              // Sprint 14 fix: this button used to just push and forget --
              // address_list_screen.dart's own "Add address" FAB already
              // gets this right (await the result, invalidate on success),
              // this was the one place that didn't match that established
              // pattern. addressesProvider/buyerLocationProvider are cached
              // FutureProviders, so without this, a newly-saved address
              // never made Home's "no location" prompt go away until an
              // unrelated pull-to-refresh happened to invalidate it too.
              final added = await context.push<bool>('/addresses/new');
              if (added == true) ref.invalidate(addressesProvider);
            },
            child: const Text('Add an address'),
          ),
        ],
      ),
    );
  }
}
