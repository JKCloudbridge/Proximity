import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency.dart';
import '../../../cart/data/models/cart_item.dart';
import '../providers/checkout_providers.dart';
import 'slot_picker_sheet.dart';

/// §7.4 step 1, per shop-group: "choose Pickup or Delivery (only the modes
/// that shop's supports_pickup/supports_delivery allow), then pick a slot."
///
/// The delivery *fulfiller* sub-choice only appears for `delivery_mode =
/// 'both'` shops (§1.3) -- a `self` or `platform` shop has exactly one legal
/// answer, and asking the buyer to pick it would be theatre: rpc_place_order
/// rejects anything else outright (DELIVERY_MODE_MISMATCH, migrations/032).
class ShopFulfillmentCard extends ConsumerWidget {
  const ShopFulfillmentCard({
    super.key,
    required this.shop,
    required this.subtotal,
    required this.itemCount,
    required this.riderFee,
  });

  final CartItemShop shop;
  final int subtotal;
  final int itemCount;
  final int riderFee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final draft = ref.watch(checkoutDraftProvider).byShop[shop.id] ?? const ShopFulfillmentDraft();
    final notifier = ref.read(checkoutDraftProvider.notifier);
    final belowMinimum = subtotal < shop.minOrderValue;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_outlined, size: 18, color: AppColors.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(shop.name, style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Text('$itemCount item${itemCount == 1 ? '' : 's'} - ${formatPaise(subtotal)}',
                  style: textTheme.labelSmall?.copyWith(color: AppColors.inkSoft)),
            ],
          ),
          // rpc_place_order enforces min_order_value at placement
          // (MIN_ORDER_NOT_MET) -- surfaced here so the buyer finds out while
          // they can still fix it, not after tapping Pay.
          if (belowMinimum) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.urgent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(
                'This shop has a ${formatPaise(shop.minOrderValue)} minimum -- add ${formatPaise(shop.minOrderValue - subtotal)} more to check out.',
                style: textTheme.labelSmall?.copyWith(color: AppColors.urgent, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (shop.supportsPickup)
                Expanded(
                  child: _ModeButton(
                    label: 'Pickup',
                    icon: Icons.storefront,
                    selected: draft.fulfillmentType == 'pickup',
                    onTap: () => notifier.setFulfillmentType(shop.id, 'pickup'),
                  ),
                ),
              if (shop.supportsPickup && shop.supportsDelivery) const SizedBox(width: 8),
              if (shop.supportsDelivery)
                Expanded(
                  child: _ModeButton(
                    label: 'Delivery',
                    icon: Icons.delivery_dining,
                    selected: draft.fulfillmentType == 'delivery',
                    onTap: () => notifier.setFulfillmentType(
                      shop.id,
                      'delivery',
                      deliveryFulfilledBy: shop.fixedDeliveryFulfilledBy,
                    ),
                  ),
                ),
            ],
          ),
          if (draft.isDelivery && shop.deliveryFulfillerIsChoosable) ...[
            const SizedBox(height: 10),
            Text('Delivered by', style: textTheme.labelMedium?.copyWith(color: AppColors.inkSoft)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _ModeButton(
                    label: 'The shop',
                    icon: Icons.store_mall_directory_outlined,
                    selected: draft.deliveryFulfilledBy == 'shop',
                    subtitle: 'No delivery fee',
                    onTap: () => notifier.setDeliveryFulfilledBy(shop.id, 'shop'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModeButton(
                    label: 'Proximity rider',
                    icon: Icons.pedal_bike,
                    selected: draft.deliveryFulfilledBy == 'platform_rider',
                    subtitle: formatPaise(riderFee),
                    onTap: () => notifier.setDeliveryFulfilledBy(shop.id, 'platform_rider'),
                  ),
                ),
              ],
            ),
          ],
          // §1.3, stated plainly rather than left for the buyer to infer from
          // a fee that silently appears: a shop that always uses Proximity
          // riders always charges the fee, and one that delivers its own
          // orders never does.
          if (draft.isDelivery && !shop.deliveryFulfillerIsChoosable) ...[
            const SizedBox(height: 8),
            Text(
              shop.fixedDeliveryFulfilledBy == 'platform_rider'
                  ? 'Delivered by a Proximity rider - ${formatPaise(riderFee)} delivery fee'
                  : 'Delivered by the shop - no delivery fee',
              style: textTheme.labelSmall?.copyWith(color: AppColors.inkSoft),
            ),
          ],
          if (draft.fulfillmentType != null) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => _pickSlot(context, ref, draft),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: draft.slotStart == null ? AppColors.line : AppColors.brand),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, size: 18, color: AppColors.brand),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        draft.slotStart == null
                            ? 'Choose a time slot'
                            : '${_dayLabel(draft.slotStart!)}, ${draft.slotLabel ?? ''}',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: draft.slotStart == null ? FontWeight.w400 : FontWeight.w600,
                          color: draft.slotStart == null ? AppColors.inkSoft : AppColors.ink,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.inkSoft),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _dayLabel(DateTime slotStart) {
    final local = slotStart.toLocal();
    final now = DateTime.now();
    if (local.year == now.year && local.month == now.month && local.day == now.day) return 'Today';
    final tomorrow = now.add(const Duration(days: 1));
    if (local.year == tomorrow.year && local.month == tomorrow.month && local.day == tomorrow.day) return 'Tomorrow';
    return '${local.day}/${local.month}';
  }

  void _pickSlot(BuildContext context, WidgetRef ref, ShopFulfillmentDraft draft) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SlotPickerSheet(
        shopId: shop.id,
        shopName: shop.name,
        fulfillmentType: draft.fulfillmentType!,
        onSelected: (slot) => ref.read(checkoutDraftProvider.notifier).setSlot(shop.id, slot),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.label, required this.icon, required this.selected, required this.onTap, this.subtitle});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandTint : Colors.white,
          border: Border.all(color: selected ? AppColors.brand : AppColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: selected ? AppColors.brandDark : AppColors.inkSoft),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.brandDark : AppColors.ink,
              ),
            ),
            if (subtitle != null)
              Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: AppColors.inkSoft)),
          ],
        ),
      ),
    );
  }
}
