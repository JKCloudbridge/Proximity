import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency.dart';
import '../../../catalog/data/models/repeat_product.dart';
import '../../../order_again/presentation/providers/order_again_providers.dart';

/// Sprint 11 -- the Organizer item picker, for both "create a new recurring
/// list" and "edit an existing one's items." SPRINT_PLANNING.md gives no UI
/// spec for Organizer at all (§4.10's own prose is schema-only: "organizer,
/// reminder-mode") -- deliberately built on top of Order Again's own
/// "Previously Bought" feed (Sprint 10, reused directly via
/// previouslyBoughtProvider/RepeatProduct, not re-implemented) rather than a
/// new product-search screen: a recurring list's whole premise is "things I
/// buy regularly," which is exactly what that feed already ranks by. A
/// buyer picking from products they've actually bought before is a better
/// default than a blank search box, and building a second browse surface
/// for this one screen would be real, avoidable scope.
///
/// Returns the selection via `Navigator.pop(context, selection)` -- a plain
/// `Map<String, int>` (variantId -> quantity, zero entries excluded) rather
/// than a typed model, since every caller (the create form, the edit-items
/// action) turns it into the same `{variantId, quantity}` wire shape
/// immediately, same "don't build a type for something that's about to be
/// serialized right back out" judgment call group_detail_sheet.dart's own
/// selection-to-batch-add flow already makes.
Future<Map<String, int>?> showItemPickerSheet(BuildContext context, {Map<String, int> initialSelection = const {}}) {
  return showModalBottomSheet<Map<String, int>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ItemPickerSheet(initialSelection: initialSelection),
  );
}

class _ItemPickerSheet extends ConsumerStatefulWidget {
  const _ItemPickerSheet({required this.initialSelection});

  final Map<String, int> initialSelection;

  @override
  ConsumerState<_ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends ConsumerState<_ItemPickerSheet> {
  late final Map<String, int> _quantities = Map.of(widget.initialSelection);

  int get _selectedCount => _quantities.values.where((q) => q > 0).length;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(previouslyBoughtProvider);
    final textTheme = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(child: Text('Add items', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),
            const Divider(height: 1),
            if (state.items.isEmpty && state.loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (state.items.isEmpty)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "You haven't ordered anything yet -- once you place a few orders, they'll show up here to add to a recurring list.",
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - 200) {
                      ref.read(previouslyBoughtProvider.notifier).loadMore();
                    }
                    return false;
                  },
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: state.items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final product = state.items[index];
                      return _ProductRow(
                        product: product,
                        quantity: _quantities[product.variantId] ?? 0,
                        onChanged: (q) => setState(() {
                          if (q <= 0) {
                            _quantities.remove(product.variantId);
                          } else {
                            _quantities[product.variantId] = q;
                          }
                        }),
                      );
                    },
                  ),
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: FilledButton(
                onPressed: _selectedCount == 0 ? null : () => Navigator.of(context).pop(_quantities),
                child: Text('Done ($_selectedCount selected)'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.quantity, required this.onChanged});

  final RepeatProduct product;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Opacity(
      opacity: product.isAvailable ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 48,
                height: 48,
                child: product.imageUrl != null
                    ? CachedNetworkImage(imageUrl: product.imageUrl!, fit: BoxFit.cover)
                    : const ColoredBox(color: AppColors.brandTint, child: Icon(Icons.shopping_basket_outlined, size: 18, color: AppColors.brand)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${product.unitValue}${product.unitLabel} · ${product.shopName}', style: textTheme.labelSmall?.copyWith(color: AppColors.inkSoft)),
                  Text(formatPaise(product.price), style: textTheme.bodySmall),
                ],
              ),
            ),
            if (!product.isAvailable)
              const Text('Unavailable', style: TextStyle(color: AppColors.urgent, fontSize: 12, fontWeight: FontWeight.w600))
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    onPressed: quantity > 0 ? () => onChanged(quantity - 1) : null,
                  ),
                  SizedBox(width: 20, child: Text('$quantity', textAlign: TextAlign.center)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    onPressed: quantity < 99 ? () => onChanged(quantity + 1) : null,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
