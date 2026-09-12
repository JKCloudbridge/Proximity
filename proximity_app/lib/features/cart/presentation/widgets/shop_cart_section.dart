import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency.dart';
import '../../data/models/cart_item.dart';
import '../providers/cart_providers.dart';
import 'cart_item_tile.dart';

/// SPRINT_PLANNING.md §7.3: one collapsible section per shop in the cart's
/// single scrollable list -- shop logo/name as the header, "Remove all from
/// this shop" as a section-level action. Expanded by default (a buyer who
/// just added items wants to see them immediately, not tap to reveal them);
/// collapsing is purely a display convenience once a cart has several shops
/// in it, not a data-model concern (§1.5's own framing).
class ShopCartSection extends ConsumerStatefulWidget {
  const ShopCartSection({super.key, required this.shop, required this.items});

  final CartItemShop shop;
  final List<CartItem> items;

  @override
  ConsumerState<ShopCartSection> createState() => _ShopCartSectionState();
}

class _ShopCartSectionState extends ConsumerState<ShopCartSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final subtotal = widget.items.fold<int>(0, (sum, item) => sum + item.lineTotalPaise);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.brandTint,
                    child: widget.shop.logoUrl != null
                        ? ClipOval(child: CachedNetworkImage(imageUrl: widget.shop.logoUrl!, width: 32, height: 32, fit: BoxFit.cover))
                        : const Icon(Icons.storefront_outlined, size: 18, color: AppColors.brand),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(widget.shop.name, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Text(formatPaise(subtotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                  IconButton(
                    icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: AppColors.inkSoft),
                    onPressed: () => setState(() => _expanded = !_expanded),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: AppColors.line),
            for (final item in widget.items) ...[CartItemTile(item: item), const Divider(height: 1, indent: 16, color: AppColors.line)],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _confirmRemoveShop(context),
                icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.urgent),
                label: const Text('Remove all from this shop', style: TextStyle(color: AppColors.urgent)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRemoveShop(BuildContext context) async {
    // A section-level bulk removal is a more consequential action than a
    // single item's "x" (which the wishlist screen deliberately skips a
    // confirmation for) -- worth one tap of confirmation before it fires.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove all items?'),
        content: Text('Remove all ${widget.items.length} item(s) from ${widget.shop.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: AppColors.urgent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(cartRepositoryProvider).removeShop(widget.shop.id);
    ref.invalidate(cartProvider);
  }
}
