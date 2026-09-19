import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../addresses/presentation/providers/address_providers.dart';
import '../../../home/data/models/category.dart';
import '../../../home/data/models/nearby_shop.dart';
import '../../../home/presentation/providers/home_providers.dart';
import '../../../shop_detail/presentation/widgets/product_grid_tile.dart';
import '../providers/category_shops_providers.dart';
import '../widgets/category_shop_rail.dart';

/// Sprint 15.md's real Categories tab tap-through screen: "tapping a
/// category navigates to a new, focused screen listing nearby shops that
/// carry it," reusing shop_detail's own rail-plus-grid layout ("left rail
/// lists nearby shops carrying that category ... right grid shows the
/// selected shop's products within it"). Reached from `CategoriesScreen`'s
/// grid tiles, pushed via `/categories/:id` (app_router.dart).
class CategoryShopsScreen extends ConsumerWidget {
  const CategoryShopsScreen({super.key, required this.categoryId});

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final categoryName = categoriesAsync.maybeWhen(data: (categories) => _findName(categories, categoryId), orElse: () => 'Category');

    return Scaffold(
      appBar: AppBar(title: Text(categoryName)),
      body: _ShopsPane(categoryId: categoryId),
    );
  }

  // categoriesProvider is already cached (Sprint 15's own scope) and cheap
  // to scan -- a linear find rather than a second network/cache round trip
  // just to resolve a title this screen's own caller already had in hand
  // as a Category (CategoriesScreen), but re-derives here anyway since a
  // deep link could reach `/categories/:id` directly with no `extra` payload.
  String _findName(List<Category> categories, String id) {
    for (final category in categories) {
      if (category.id == id) return category.name;
    }
    return 'Category';
  }
}

/// Same "location unresolved vs. resolved-to-null vs. resolved" three-way
/// split as home_screen.dart's own top-level `HomeScreen.build` --
/// [categoryNearbyShopsProvider] itself already collapses "no location" and
/// "location still loading" into an empty list underneath (see that
/// provider's own header), but the buyer-facing difference between "we
/// don't know where you are" and "we know, and nothing's nearby" is real
/// and worth keeping distinct here too, same reasoning Home's own
/// `_LocationPrompt` vs. `_EmptyShopsState` split already established.
class _ShopsPane extends ConsumerWidget {
  const _ShopsPane({required this.categoryId});

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationAsync = ref.watch(buyerLocationProvider);

    return locationAsync.when(
      data: (location) => location == null ? const _LocationPrompt() : _ShopsBody(categoryId: categoryId),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => const _LocationPrompt(),
    );
  }
}

class _ShopsBody extends ConsumerWidget {
  const _ShopsBody({required this.categoryId});

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shopsAsync = ref.watch(categoryNearbyShopsProvider(categoryId));

    return shopsAsync.when(
      data: (shops) => shops.isEmpty ? const _NoShopsForCategory() : _RailAndGrid(categoryId: categoryId, shops: shops),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('Could not load nearby shops.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft)),
        ),
      ),
    );
  }
}

/// Rail selection defaults to the first shop rather than leaving nothing
/// highlighted -- computed once here (not independently inside the rail and
/// the grid) so both panes always agree on which shop is "selected," per
/// `selectedCategoryShopIdProvider`'s own header.
class _RailAndGrid extends ConsumerWidget {
  const _RailAndGrid({required this.categoryId, required this.shops});

  final String categoryId;
  final List<NearbyShop> shops;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedCategoryShopIdProvider(categoryId));
    final effectiveShopId = selected ?? shops.first.id;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 76,
          child: CategoryShopRail(
            categoryId: categoryId,
            shops: shops,
            selectedShopId: effectiveShopId,
            onSelect: (shopId) => ref.read(selectedCategoryShopIdProvider(categoryId).notifier).state = shopId,
          ),
        ),
        const VerticalDivider(width: 1, color: AppColors.line),
        Expanded(child: _ProductGridPane(categoryId: categoryId, shopId: effectiveShopId)),
      ],
    );
  }
}

class _ProductGridPane extends ConsumerWidget {
  const _ProductGridPane({required this.categoryId, required this.shopId});

  final String categoryId;
  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(categoryShopProductsProvider((categoryId: categoryId, shopId: shopId)));

    return productsAsync.when(
      data: (products) => products.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No products in this category yet.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft)),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.7,
              ),
              itemCount: products.length,
              itemBuilder: (context, index) {
                final product = products[index];
                return ProductGridTile(product: product, onTap: () => context.push('/product/${product.id}'));
              },
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Text('Could not load products.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft)),
      ),
    );
  }
}

class _NoShopsForCategory extends StatelessWidget {
  const _NoShopsForCategory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront_outlined, size: 48, color: AppColors.inkSoft),
            const SizedBox(height: 12),
            Text('No shops near you carry this category yet', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.ink)),
            const SizedBox(height: 4),
            Text(
              "Check back soon, or browse another category.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

/// Same copy/actions as home_screen.dart's own private `_LocationPrompt` --
/// can't import that one (private to its file), so this is a same-shaped
/// twin rather than a shared widget; both re-resolve `buyerLocationProvider`
/// on success, same "either action succeeding replaces this screen with the
/// real content" rule.
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
