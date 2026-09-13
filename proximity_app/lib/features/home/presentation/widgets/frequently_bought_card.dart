import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency.dart';
import '../../../catalog/data/models/repeat_product.dart';

/// Sprint 10 -- one card in Home's conditional "Frequently Bought" section
/// (§7.1). Same restrained "tap only navigates to the PDP" shape
/// [RecommendedProductCard] already established -- the one thing unique
/// here is the "Ordered Nx" line in place of the shop name, since on this
/// section the buyer's own reorder count is the more relevant signal than
/// which shop it came from (they've already bought it there before).
class FrequentlyBoughtCard extends StatelessWidget {
  const FrequentlyBoughtCard({super.key, required this.product, required this.onTap});

  final RepeatProduct product;
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
                      ? Opacity(opacity: product.isAvailable ? 1 : 0.5, child: CachedNetworkImage(imageUrl: product.imageUrl!, fit: BoxFit.cover))
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
                  Text('Ordered ${product.timesOrdered}x before', style: textTheme.labelSmall?.copyWith(color: AppColors.inkSoft)),
                  const SizedBox(height: 4),
                  Text(formatPaise(product.price), style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
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
