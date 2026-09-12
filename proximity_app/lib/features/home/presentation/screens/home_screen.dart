import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../addresses/presentation/providers/address_providers.dart';
import '../../data/models/nearby_shop.dart';
import '../../data/models/recommended_product.dart';
import '../providers/home_providers.dart';
import '../widgets/category_chip_row.dart';
import '../widgets/recommended_product_card.dart';
import '../widgets/shop_card.dart';

/// SPRINT_PLANNING.md §7.1/§11: category chip row, "Recommended for you"
/// (Sprint 6), and "Shops near you" (Sprint 4), sorted by distance and
/// filterable by category. Frequently-Bought (§7.1's third named section)
/// is still Sprint 10's job -- order history doesn't exist yet -- so this
/// screen has two real sections, not three placeholders pretending to be
/// finished.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final locationAsync = ref.watch(buyerLocationProvider);
    final shopsAsync = ref.watch(nearbyShopsProvider);
    final recommendedAsync = ref.watch(recommendedProductsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(categoriesProvider);
        ref.invalidate(buyerLocationProvider);
        ref.invalidate(nearbyShopsProvider);
        ref.invalidate(recommendedProductsProvider);
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
          // §7.1's order is chips -> Frequently Bought (Sprint 10, not built)
          // -> Recommended for you -> Shops near you. Renders nothing at all
          // (not even a heading) while loading or empty -- same "don't show
          // a section with nothing under it" rule Frequently-Bought's own
          // ≥3-groups gate will use once it exists.
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
          height: 380,
          child: GridView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.72,
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
