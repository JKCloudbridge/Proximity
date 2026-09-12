import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../home/presentation/widgets/next_slot_badge.dart';
import '../../data/models/shop_detail.dart';
import '../providers/shop_detail_providers.dart';
import '../widgets/product_grid_tile.dart';
import '../widgets/sub_category_rail.dart';

/// SPRINT_PLANNING.md §7.1/§11 Sprint 5: shop header + vertical category
/// rail + product grid. Reached from `ShopCard.onTap` on Home (Sprint 4's
/// card pushed a "coming in Sprint 5" snackbar instead -- see
/// home_screen.dart's `_openShop`, now wired to push here).
class ShopDetailScreen extends ConsumerWidget {
  const ShopDetailScreen({super.key, required this.shopId});

  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shopAsync = ref.watch(shopDetailProvider(shopId));

    return Scaffold(
      body: shopAsync.when(
        data: (shop) => shop == null
            ? const _ShopUnavailable()
            : Column(
                children: [
                  _ShopHeader(shop: shop),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 76, child: _SubCategoryRailPane(shopId: shopId)),
                        const VerticalDivider(width: 1, color: AppColors.line),
                        Expanded(child: _ProductGridPane(shopId: shopId)),
                      ],
                    ),
                  ),
                ],
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const _ShopUnavailable(),
      ),
    );
  }
}

class _ShopHeader extends StatelessWidget {
  const _ShopHeader({required this.shop});

  final ShopDetail shop;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 16 / 7,
          child: shop.coverImageUrl != null
              ? CachedNetworkImage(imageUrl: shop.coverImageUrl!, fit: BoxFit.cover)
              : const ColoredBox(color: AppColors.brandTint, child: Icon(Icons.storefront_outlined, color: AppColors.brand, size: 40)),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 4,
          left: 4,
          child: CircleAvatar(backgroundColor: Colors.white, child: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shop.name, style: textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(shop.addressLine, style: textTheme.bodySmall?.copyWith(color: AppColors.inkSoft), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (shop.supportsPickup) const _Tag(label: 'Pickup'),
                    if (shop.supportsPickup && shop.supportsDelivery) const SizedBox(width: 6),
                    if (shop.supportsDelivery) const _Tag(label: 'Delivery'),
                    const Spacer(),
                    if (shop.nextSlot != null) NextSlotBadge(slotStart: shop.nextSlot!.slotStart, slotEnd: shop.nextSlot!.slotEnd),
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

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.line)),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.inkSoft)),
    );
  }
}

class _SubCategoryRailPane extends ConsumerWidget {
  const _SubCategoryRailPane({required this.shopId});

  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subCategoriesAsync = ref.watch(shopSubCategoriesProvider(shopId));

    return subCategoriesAsync.when(
      // A shop with no sub-categories defined yet still has an "All" entry
      // (SubCategoryRail always renders it) -- the rail never fully
      // disappears, since the product grid still needs a way to show
      // everything.
      data: (subCategories) => SubCategoryRail(shopId: shopId, subCategories: subCategories),
      loading: () => const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      error: (error, stackTrace) => SubCategoryRail(shopId: shopId, subCategories: const []),
    );
  }
}

class _ProductGridPane extends ConsumerWidget {
  const _ProductGridPane({required this.shopId});

  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(shopProductsProvider(shopId));

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

class _ShopUnavailable extends StatelessWidget {
  const _ShopUnavailable();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront_outlined, size: 40, color: AppColors.inkSoft),
            const SizedBox(height: 12),
            Text(
              'This shop is no longer available.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: () => context.pop(), child: const Text('Go back')),
          ],
        ),
      ),
    );
  }
}
