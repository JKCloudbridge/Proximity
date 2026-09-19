import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../data/models/frequently_bought_group.dart';
import '../providers/order_again_providers.dart';

/// §5 of Baker Ally's `03_order_again_tab.md` prose spec -- 85% screen
/// height, vertically scrollable, one row per item with a qty stepper
/// (default 1, `-` to 0 excludes that item, out-of-stock items disabled
/// outright). "Add Selected Items to Cart" sends everything with a
/// non-zero qty via the same batch endpoint [GroupTile]'s own "Add All"
/// button uses.
class GroupDetailSheet extends ConsumerStatefulWidget {
  const GroupDetailSheet({super.key, required this.group});

  final FrequentlyBoughtGroup group;

  @override
  ConsumerState<GroupDetailSheet> createState() => _GroupDetailSheetState();
}

class _GroupDetailSheetState extends ConsumerState<GroupDetailSheet> {
  late final Map<String, int> _quantities = {
    for (final item in widget.group.items) item.variantId: item.isAvailable ? 1 : 0,
  };
  bool _adding = false;

  int get _total {
    var sum = 0;
    for (final item in widget.group.items) {
      sum += item.price * (_quantities[item.variantId] ?? 0);
    }
    return sum;
  }

  int get _selectedCount => _quantities.values.where((q) => q > 0).length;

  Future<void> _addSelected() async {
    final selected = widget.group.items.where((i) => (_quantities[i.variantId] ?? 0) > 0).toList();
    if (selected.isEmpty) return;
    setState(() => _adding = true);
    try {
      final result = await ref.read(orderAgainRepositoryProvider).addItemsBatch([
        for (final item in selected) (variantId: item.variantId, quantity: _quantities[item.variantId]!),
      ]);
      ref.invalidate(cartProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      final message = result.failedVariantIds.isEmpty
          ? '${result.added.length} item(s) added to cart'
          : '${result.added.length} item(s) added, ${result.failedVariantIds.length} unavailable';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add items: $e')));
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
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
                  Expanded(
                    child: Text(group.shopName, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: group.items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) => _ItemRow(
                  item: group.items[index],
                  quantity: _quantities[group.items[index].variantId] ?? 0,
                  onChanged: (q) => setState(() => _quantities[group.items[index].variantId] = q),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total', style: textTheme.bodyLarge),
                      Text(formatPaise(_total), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: (_adding || _selectedCount == 0) ? null : _addSelected,
                    child: _adding
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('Add Selected Items to Cart ($_selectedCount)'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.quantity, required this.onChanged});

  final FrequentlyBoughtGroupItem item;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Opacity(
      opacity: item.isAvailable ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 48,
                height: 48,
                child: item.imageUrl != null
                    ? CachedNetworkImage(imageUrl: item.imageUrl!, fit: BoxFit.cover)
                    : const ColoredBox(color: AppColors.brandTint, child: Icon(Icons.shopping_basket_outlined, size: 18, color: AppColors.brand)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.productName, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${item.unitValue}${item.unitLabel}', style: textTheme.labelSmall?.copyWith(color: AppColors.inkSoft)),
                  Text(formatPaise(item.price), style: textTheme.bodySmall),
                ],
              ),
            ),
            if (!item.isAvailable)
              const Text('Out of Stock', style: TextStyle(color: AppColors.urgent, fontSize: 12, fontWeight: FontWeight.w600))
            else
              _Stepper(quantity: quantity, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.quantity, required this.onChanged});

  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Decrease quantity',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_circle_outline, size: 20),
          onPressed: quantity > 0 ? () => onChanged(quantity - 1) : null,
        ),
        SizedBox(width: 20, child: Text('$quantity', textAlign: TextAlign.center)),
        IconButton(
          tooltip: 'Increase quantity',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline, size: 20),
          onPressed: quantity < 99 ? () => onChanged(quantity + 1) : null,
        ),
      ],
    );
  }
}
