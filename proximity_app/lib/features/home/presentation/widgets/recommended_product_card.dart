import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency.dart';
import '../../../../shared/widgets/quick_add_control.dart';
import '../../data/models/recommended_product.dart';

/// One card in Home's "Recommended for you" 2-row horizontal scroll (§7.1)
/// -- sized by the enclosing horizontal [GridView]'s delegate
/// (_RecommendedSection in home_screen.dart), not a fixed width of its own.
///
/// Sprint 15 feedback: gained the same bottom-right quick-add control
/// [ProductGridTile] (features/shop_detail) already has -- the restraint
/// this file's header used to describe ("no quick-add on the card") was a
/// Sprint 6 decision, revisited and reversed here at your explicit request,
/// not an oversight. Needed `GET /v1/recommended` to start returning a real
/// `variantId` first (routes/recommendations.ts) -- see that file's own
/// header for why it never had before.
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
                  if (product.variantId != null)
                    Positioned(right: 6, bottom: 6, child: QuickAddControl(variantId: product.variantId!)),
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
