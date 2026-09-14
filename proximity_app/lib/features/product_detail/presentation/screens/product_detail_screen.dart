import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/auth_provider.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../../catalog/data/models/product_variant.dart';
import '../../../wishlist/presentation/widgets/wishlist_heart_button.dart';
import '../../data/models/product_detail.dart';
import '../providers/product_detail_providers.dart';
import '../widgets/variant_selector.dart';

/// SPRINT_PLANNING.md §7.1/§11 Sprint 5/6: the PDP -- images, variant
/// selection, price/stock, and (Sprint 6) a real "Add to cart" wired to
/// rpc_add_to_cart via CartRepository. Sprint 5's exit criteria ended at the
/// full chain "Home -> shop -> product -> variant"; this sprint completes
/// what that sprint left intentionally inert, same "wired now, built later"
/// treatment ShopCard.onTap got in Sprint 4 for shop detail.
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productAsync = ref.watch(productDetailProvider(productId));

    return Scaffold(
      body: productAsync.when(
        data: (product) => product == null ? const _ProductUnavailable() : _ProductBody(productId: productId, product: product),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const _ProductUnavailable(),
      ),
    );
  }
}

class _ProductBody extends ConsumerWidget {
  const _ProductBody({required this.productId, required this.product});

  final String productId;
  final ProductDetail product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final variants = product.variants;

    // Every active variant that's ever reached this screen came through
    // GET /v1/products/:id, which itself never 404s for a product with zero
    // active variants having a *product* still returned -- but a product
    // can genuinely have none (every variant deactivated independently of
    // the product itself, migrations/018's own table). That's the one real
    // empty state this screen has to handle explicitly.
    if (variants.isEmpty) {
      return CustomScrollView(
        slivers: [
          _imagesSliver(context),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Text('This product is currently unavailable.', style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft)),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final selectedId = ref.watch(selectedVariantIdProvider(productId));
    final selectedVariant = _resolveSelected(variants, selectedId);

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            _imagesSliver(context),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (product.isVeg != null) ...[_VegDot(isVeg: product.isVeg!), const SizedBox(width: 8)],
                        Expanded(child: Text(product.name, style: textTheme.headlineSmall)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => context.push('/shop/${product.shopId}'),
                      child: Text('from ${product.shopName}', style: textTheme.bodyMedium?.copyWith(color: AppColors.brandDark, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 16),
                    VariantPriceRow(variant: selectedVariant),
                    const SizedBox(height: 16),
                    if (variants.length > 1) ...[
                      Text('Select unit', style: textTheme.labelLarge),
                      const SizedBox(height: 8),
                      VariantSelector(productId: productId, variants: variants, selectedVariant: selectedVariant),
                      const SizedBox(height: 16),
                    ],
                    if (product.description != null) ...[
                      Text('About this product', style: textTheme.labelLarge),
                      const SizedBox(height: 6),
                      Text(product.description!, style: textTheme.bodyMedium),
                      const SizedBox(height: 16),
                    ],
                    if (product.infoMessage != null)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppColors.brandTint, borderRadius: BorderRadius.circular(10)),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, size: 18, color: AppColors.brandDark),
                            const SizedBox(width: 8),
                            Expanded(child: Text(product.infoMessage!, style: textTheme.bodySmall?.copyWith(color: AppColors.brandDark))),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 4,
          left: 4,
          child: CircleAvatar(backgroundColor: Colors.white, child: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 4,
          right: 4,
          child: CircleAvatar(backgroundColor: Colors.white, child: WishlistHeartButton(productId: product.id)),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: selectedVariant.inStock ? () => _addToCart(context, ref, selectedVariant) : null,
                child: Text(selectedVariant.inStock ? 'Add to cart' : 'Out of stock'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _imagesSliver(BuildContext context) {
    return SliverToBoxAdapter(
      child: AspectRatio(
        aspectRatio: 1,
        child: product.images.isEmpty
            ? const ColoredBox(color: AppColors.brandTint, child: Icon(Icons.shopping_basket_outlined, color: AppColors.brand, size: 56))
            : PageView(children: product.images.map((image) => CachedNetworkImage(imageUrl: image.imageUrl, fit: BoxFit.cover)).toList()),
      ),
    );
  }

  ProductVariant _resolveSelected(List<ProductVariant> variants, String? selectedId) {
    if (selectedId != null) {
      for (final variant in variants) {
        if (variant.id == selectedId) return variant;
      }
    }
    for (final variant in variants) {
      if (variant.inStock) return variant;
    }
    return variants.first;
  }

  // Guest tap never calls the API -- own-user data with no guest-usable
  // backing (routes/cart.ts's whole group is authenticated), same "gated at
  // the specific action, not at the door" rule WishlistHeartButton already
  // follows. No busy-guard on rapid double-taps like the cart screen's
  // stepper needs -- this is an increment (rpc_add_to_cart), so two quick
  // taps correctly landing as +2 is the right outcome, not a race to guard
  // against.
  Future<void> _addToCart(BuildContext context, WidgetRef ref, ProductVariant variant) async {
    final isLoggedIn = ref.read(authProvider).isLoggedIn;
    if (!isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Sign in to add items to your cart'),
          action: SnackBarAction(label: 'Sign in', onPressed: () => context.push('/login')),
        ),
      );
      return;
    }

    try {
      await ref.read(cartRepositoryProvider).addItem(variant.id);
      ref.invalidate(cartProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added to cart'),
          action: SnackBarAction(label: 'View cart', onPressed: () => context.go('/cart')),
        ),
      );
    } on DioException catch (err) {
      final responseData = err.response?.data;
      // Dart quirk, not a style choice: a bare `?[...]` chain can't parse as
      // a ternary's true-branch (`cond ? x?['y'] : z` is a syntax error,
      // confirmed against this project's own Dart SDK) -- the null-aware
      // index needs its own parens even with the ternary's operands already
      // pulled into simple variables.
      final code = responseData is Map ? (responseData['error']?['code']) : null;
      final message = code == 'OUT_OF_STOCK' ? 'This item just went out of stock' : 'Could not add to cart';
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _VegDot extends StatelessWidget {
  const _VegDot({required this.isVeg});

  final bool isVeg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(border: Border.all(color: isVeg ? AppColors.success : AppColors.urgent), borderRadius: BorderRadius.circular(3)),
      child: DecoratedBox(decoration: BoxDecoration(color: isVeg ? AppColors.success : AppColors.urgent, shape: BoxShape.circle)),
    );
  }
}

class _ProductUnavailable extends StatelessWidget {
  const _ProductUnavailable();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shopping_basket_outlined, size: 40, color: AppColors.inkSoft),
            const SizedBox(height: 12),
            Text(
              'This product is no longer available.',
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
