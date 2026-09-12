import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/nearby_shop.dart';
import 'next_slot_badge.dart';

/// SPRINT_PLANNING.md §7.1's "1/row" shops-near-you card. The spec also
/// calls for an "auto-scrolling photo carousel" here -- not built this
/// sprint: that needs `shop_media` (multiple photos per shop), and that
/// table still has no route (Sprint 2/3 both deferred it, no route reads it
/// yet). This card uses the shop's single `coverImageUrl` instead, and the
/// carousel becomes a drop-in upgrade once shop_media gets one -- documented
/// here rather than silently building a single-image card as if it were the
/// finished design.
class ShopCard extends StatelessWidget {
  const ShopCard({super.key, required this.shop, this.onTap});

  final NearbyShop shop;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.line)),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: shop.coverImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: shop.coverImageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => const _CoverPlaceholder(),
                    )
                  : const _CoverPlaceholder(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(shop.name, style: textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Text('${shop.distanceKm.toStringAsFixed(1)} km', style: textTheme.labelMedium?.copyWith(color: AppColors.inkSoft)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(shop.addressLine, style: textTheme.bodySmall?.copyWith(color: AppColors.inkSoft), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
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
          ],
        ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.brandTint,
      child: Center(child: Icon(Icons.storefront_outlined, color: AppColors.brand, size: 32)),
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
