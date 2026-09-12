import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency.dart';
import '../../../catalog/data/models/shop_product.dart';
import '../../../wishlist/presentation/widgets/wishlist_heart_button.dart';

/// One tile in the shop-detail product grid (§7.1, next to
/// [SubCategoryRail]). Tapping anywhere but the heart opens the PDP
/// (§11 Sprint 5's exit criteria: "Home -> shop -> product -> variant").
class ProductGridTile extends StatelessWidget {
  const ProductGridTile({super.key, required this.product, required this.onTap});

  final ShopProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final minPrice = product.minPricePaise;
    final outOfStock = !product.anyVariantInStock;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.line)),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  product.thumbnailUrl != null
                      ? Opacity(
                          opacity: outOfStock ? 0.5 : 1,
                          child: CachedNetworkImage(imageUrl: product.thumbnailUrl!, fit: BoxFit.cover),
                        )
                      : const ColoredBox(color: AppColors.brandTint, child: Icon(Icons.shopping_basket_outlined, color: AppColors.brand)),
                  if (product.isVeg != null)
                    Positioned(top: 6, left: 6, child: _VegDot(isVeg: product.isVeg!)),
                  Positioned(top: -4, right: -4, child: WishlistHeartButton(productId: product.id, size: 20)),
                  if (outOfStock)
                    const Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: ColoredBox(
                        color: Colors.black54,
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Text('Out of stock', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 11)),
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
                  Text(product.name, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  if (minPrice != null)
                    Text(
                      product.variants.length > 1 ? 'From ${formatPaise(minPrice)}' : formatPaise(minPrice),
                      style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VegDot extends StatelessWidget {
  const _VegDot({required this.isVeg});

  final bool isVeg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: isVeg ? AppColors.success : AppColors.urgent), borderRadius: BorderRadius.circular(3)),
      child: DecoratedBox(decoration: BoxDecoration(color: isVeg ? AppColors.success : AppColors.urgent, shape: BoxShape.circle)),
    );
  }
}
