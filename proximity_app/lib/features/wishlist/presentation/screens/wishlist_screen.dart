import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency.dart';
import '../../data/models/wishlist_item.dart';
import '../providers/wishlist_providers.dart';

/// Reached from AccountScreen's "My Wishlist" tile -- protected route
/// (app_router.dart's `_protectedPaths`), so this screen never renders for a
/// guest; unlike WishlistHeartButton, it doesn't need its own sign-in prompt.
class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(wishlistProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Wishlist')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(wishlistProvider),
        child: itemsAsync.when(
          data: (items) => items.isEmpty
              ? ListView(children: const [SizedBox(height: 120), _EmptyState()])
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) => _WishlistTile(item: items[index]),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => const Center(child: Text('Could not load your wishlist.')),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.favorite_border, size: 40, color: AppColors.inkSoft),
          const SizedBox(height: 12),
          Text(
            'Nothing saved yet -- tap the heart on any product to add it here.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _WishlistTile extends ConsumerWidget {
  const _WishlistTile({required this.item});

  final WishlistItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = item.product;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.line)),
      child: InkWell(
        // Product may be gone (deleted/deactivated/shop suspended) --
        // isAvailable/product-null both signal that; nothing to navigate to
        // in that case, only "remove" still makes sense (below).
        onTap: item.isAvailable && product != null ? () => context.push('/product/${item.productId}') : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  product?.imageUrl != null
                      ? Opacity(
                          opacity: item.isAvailable ? 1 : 0.4,
                          child: CachedNetworkImage(imageUrl: product!.imageUrl!, fit: BoxFit.cover),
                        )
                      : const ColoredBox(color: AppColors.brandTint, child: Icon(Icons.image_outlined, color: AppColors.brand)),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: IconButton(
                        tooltip: 'Remove from wishlist',
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () async {
                          await ref.read(wishlistRepositoryProvider).remove(item.productId);
                          ref.invalidate(wishlistProvider);
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product?.name ?? 'No longer available',
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (product?.shopName != null)
                    Text(product!.shopName!, style: textTheme.labelSmall?.copyWith(color: AppColors.inkSoft), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  if (!item.isAvailable)
                    Text('Unavailable', style: textTheme.labelSmall?.copyWith(color: AppColors.urgent, fontWeight: FontWeight.w600))
                  else if (product?.minPrice != null)
                    Text(formatPaise(product!.minPrice!), style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
