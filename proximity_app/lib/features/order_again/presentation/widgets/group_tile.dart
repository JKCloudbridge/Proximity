import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../data/models/frequently_bought_group.dart';
import '../providers/order_again_providers.dart';
import 'group_detail_sheet.dart';

/// §4 of Baker Ally's `03_order_again_tab.md` prose spec (ported against
/// prose, not code -- lib/frequentlyBoughtGroups.ts's own header explains
/// why): a card in the horizontal "Frequently Bought Together" scroll row.
/// Tapping the body opens [GroupDetailSheet]; tapping "Add All to Cart" adds
/// every in-stock item at qty 1 directly, without opening the sheet.
class GroupTile extends ConsumerStatefulWidget {
  const GroupTile({super.key, required this.group});

  final FrequentlyBoughtGroup group;

  @override
  ConsumerState<GroupTile> createState() => _GroupTileState();
}

class _GroupTileState extends ConsumerState<GroupTile> {
  bool _adding = false;

  String get _groupName {
    final names = widget.group.items.map((i) => i.productName).toList();
    final joined = names.take(2).join(' + ');
    return names.length > 2 ? '$joined...' : joined;
  }

  Future<void> _addAllToCart() async {
    final available = widget.group.items.where((i) => i.isAvailable).toList();
    if (available.isEmpty) return;
    setState(() => _adding = true);
    try {
      final result = await ref.read(orderAgainRepositoryProvider).addItemsBatch([
        for (final item in available) (variantId: item.variantId, quantity: 1),
      ]);
      ref.invalidate(cartProvider);
      if (!mounted) return;
      final message = result.failedVariantIds.isEmpty
          ? '${result.added.length} item(s) added to cart'
          : '${result.added.length} item(s) added, ${result.failedVariantIds.length} unavailable';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add items: $e')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: 220,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.line)),
        child: InkWell(
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => GroupDetailSheet(group: group),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ImagesRow(items: group.items),
                const SizedBox(height: 10),
                Text(_groupName, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${group.items.length} items - ${formatPaise(group.totalPrice)}',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                ),
                if (group.anyUnavailable) ...[
                  const SizedBox(height: 4),
                  Text('Some items unavailable', style: textTheme.labelSmall?.copyWith(color: AppColors.accent)),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _adding ? null : _addAllToCart,
                    child: _adding
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Add All to Cart'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// §4's "always show exactly 2 product images side by side with a + between
/// them," an overflow-count overlay on the second image when there are more
/// than 2 items.
class _ImagesRow extends StatelessWidget {
  const _ImagesRow({required this.items});

  final List<FrequentlyBoughtGroupItem> items;

  @override
  Widget build(BuildContext context) {
    final overflow = items.length - 2;
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          _Thumb(url: items.isNotEmpty ? items[0].imageUrl : null),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.add, size: 16, color: AppColors.inkSoft)),
          _Thumb(url: items.length > 1 ? items[1].imageUrl : null, overflowCount: overflow > 0 ? overflow : null),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({this.url, this.overflowCount});

  final String? url;
  final int? overflowCount;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              url != null
                  ? CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover)
                  : const ColoredBox(color: AppColors.brandTint, child: Icon(Icons.shopping_basket_outlined, color: AppColors.brand)),
              if (overflowCount != null)
                ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: Text('+$overflowCount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
