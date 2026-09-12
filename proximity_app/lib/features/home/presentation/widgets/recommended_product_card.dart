import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency.dart';
import '../../data/models/recommended_product.dart';

/// One card in Home's "Recommended for you" 2-row horizontal scroll (§7.1)
/// -- sized by the enclosing horizontal [GridView]'s delegate
/// (_RecommendedSection in home_screen.dart), not a fixed width of its own.
/// Tap only navigates to the PDP -- same "no quick-add on the card"
/// restraint [ProductGridTile] (features/shop_detail) already established
/// for the shop-detail grid, which predates this widget and has no cart
/// button either despite showing a wishlist heart; adding one here would be
/// a new affordance this sprint's scope doesn't ask for.
class RecommendedProductCard extends StatelessWidget {
  const RecommendedProductCard({super.key, required this.product, required this.onTap});

  final RecommendedProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

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
                  product.imageUrl != null
                      ? CachedNetworkImage(imageUrl: product.imageUrl!, fit: BoxFit.cover)
                      : const ColoredBox(color: AppColors.brandTint, child: Icon(Icons.shopping_basket_outlined, color: AppColors.brand)),
                  if (product.isVeg != null) Positioned(top: 6, left: 6, child: _VegDot(isVeg: product.isVeg!)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(product.shopName, style: textTheme.labelSmall?.copyWith(color: AppColors.inkSoft), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(formatPaise(product.minPrice), style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
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
