import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency.dart';
import '../../data/models/cart_item.dart';
import '../providers/cart_providers.dart';

/// One line in a [ShopCartSection] -- thumbnail, name/unit, price, a +/-
/// stepper, and a remove action. Network round trip on every tap (no local
/// optimistic state, same "fire and refetch" convention WishlistHeartButton
/// established) -- the stepper disables itself while a request is in
/// flight so a rapid double-tap can't fire two overlapping PATCHes, a cheap
/// widget-local guard rather than full optimistic cart state (deferred to
/// Sprint 13 polish, same as every other "not silky yet" gap this codebase
/// has flagged rather than silently left unmentioned).
class CartItemTile extends ConsumerStatefulWidget {
  const CartItemTile({super.key, required this.item});

  final CartItem item;

  @override
  ConsumerState<CartItemTile> createState() => _CartItemTileState();
}

class _CartItemTileState extends ConsumerState<CartItemTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final textTheme = Theme.of(context).textTheme;
    final blocked = !item.isAvailable || !item.variant.inStock;

    return Opacity(
      opacity: blocked ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => context.push('/product/${item.product.id}'),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: item.product.imageUrl != null
                      ? CachedNetworkImage(imageUrl: item.product.imageUrl!, fit: BoxFit.cover)
                      : const ColoredBox(color: AppColors.brandTint, child: Icon(Icons.shopping_basket_outlined, color: AppColors.brand)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.product.name, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text('${item.variant.unitValue.toStringAsFixed(item.variant.unitValue.truncateToDouble() == item.variant.unitValue ? 0 : 1)} ${item.variant.unitLabel}',
                      style: textTheme.labelSmall?.copyWith(color: AppColors.inkSoft)),
                  const SizedBox(height: 4),
                  if (!item.isAvailable)
                    Text('No longer available', style: textTheme.labelSmall?.copyWith(color: AppColors.urgent, fontWeight: FontWeight.w600))
                  else if (!item.variant.inStock)
                    Text('Out of stock', style: textTheme.labelSmall?.copyWith(color: AppColors.urgent, fontWeight: FontWeight.w600))
                  else
                    Text(formatPaise(item.variant.price), style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            blocked ? _removeOnlyAction() : _stepper(),
          ],
        ),
      ),
    );
  }

  Widget _removeOnlyAction() {
    return IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.urgent), onPressed: _busy ? null : _remove, tooltip: 'Remove');
  }

  Widget _stepper() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepperButton(
          icon: widget.item.quantity <= 1 ? Icons.delete_outline : Icons.remove,
          tooltip: widget.item.quantity <= 1 ? 'Remove' : 'Decrease quantity',
          onTap: () => _changeQuantity(widget.item.quantity - 1),
        ),
        SizedBox(width: 28, child: Center(child: Text('${widget.item.quantity}', style: const TextStyle(fontWeight: FontWeight.w700)))),
        _stepperButton(icon: Icons.add, tooltip: 'Increase quantity', onTap: () => _changeQuantity(widget.item.quantity + 1)),
      ],
    );
  }

  Widget _stepperButton({required IconData icon, required String tooltip, required VoidCallback onTap}) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 18, color: icon == Icons.delete_outline ? AppColors.urgent : AppColors.brand),
        onPressed: _busy ? null : onTap,
        style: IconButton.styleFrom(backgroundColor: AppColors.brandTint, shape: const CircleBorder()),
      ),
    );
  }

  Future<void> _changeQuantity(int newQuantity) async {
    setState(() => _busy = true);
    try {
      if (newQuantity <= 0) {
        await ref.read(cartRepositoryProvider).removeItem(widget.item.id);
      } else {
        await ref.read(cartRepositoryProvider).updateQuantity(widget.item.id, newQuantity);
      }
      ref.invalidate(cartProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await ref.read(cartRepositoryProvider).removeItem(widget.item.id);
      ref.invalidate(cartProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
