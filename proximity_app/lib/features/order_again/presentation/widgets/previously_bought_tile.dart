import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../../catalog/data/models/repeat_product.dart';

/// §7 of Baker Ally's `03_order_again_tab.md` prose spec -- same dimensions
/// as the catalog/shop-detail product tile, plus the one thing unique to
/// this tab: a "Last bought" recency label. **One deliberate, documented
/// deviation from that spec:** an out-of-stock item there gets a "Notify
/// Me" button (back-in-stock email alerts) -- that feature doesn't exist in
/// THIS project at all (no `stock_notify_requests` table/route anywhere),
/// and per that same spec doc it wasn't even built in Baker Ally itself
/// ("blocked on choosing an email provider," its own §7 says so). Showing a
/// plain disabled "Out of Stock" state here instead is an honest match to
/// this project's actual scope, not a regression from the spec -- adding a
/// real notify-me flow is a `SPRINT_PLANNING.md` §10 backlog item for
/// whichever future sprint picks it up, not invented here.
class PreviouslyBoughtTile extends ConsumerStatefulWidget {
  const PreviouslyBoughtTile({super.key, required this.product});

  final RepeatProduct product;

  @override
  ConsumerState<PreviouslyBoughtTile> createState() => _PreviouslyBoughtTileState();
}

class _PreviouslyBoughtTileState extends ConsumerState<PreviouslyBoughtTile> {
  bool _adding = false;

  Future<void> _addToCart() async {
    setState(() => _adding = true);
    try {
      await ref.read(cartRepositoryProvider).addItem(widget.product.variantId);
      ref.invalidate(cartProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to cart')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add: $e')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  String _lastBoughtLabel() {
    final d = widget.product.lastOrderedAt.toLocal();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return 'Last bought: ${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.line)),
      child: InkWell(
        onTap: () => context.push('/product/${product.productId}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  product.imageUrl != null
                      ? Opacity(
                          opacity: product.isAvailable ? 1 : 0.5,
                          child: CachedNetworkImage(imageUrl: product.imageUrl!, fit: BoxFit.cover),
                        )
                      : const ColoredBox(color: AppColors.brandTint, child: Icon(Icons.shopping_basket_outlined, color: AppColors.brand)),
                  if (!product.isAvailable)
                    const Positioned(
                      top: 6,
                      left: 6,
                      child: _Badge(text: 'Out of Stock', color: AppColors.urgent),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text('${product.unitValue}${product.unitLabel}', style: textTheme.labelSmall?.copyWith(color: AppColors.inkSoft)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (product.mrp != null && product.mrp! > product.price)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            formatPaise(product.mrp!),
                            style: textTheme.bodySmall?.copyWith(color: AppColors.inkSoft, decoration: TextDecoration.lineThrough),
                          ),
                        ),
                      Text(formatPaise(product.price), style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(_lastBoughtLabel(), style: textTheme.labelSmall?.copyWith(color: AppColors.inkSoft)),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: product.isAvailable
                        ? OutlinedButton(
                            onPressed: _adding ? null : _addToCart,
                            child: _adding
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('+ Add to Cart', style: TextStyle(fontSize: 12.5)),
                          )
                        : const OutlinedButton(onPressed: null, child: Text('Out of Stock', style: TextStyle(fontSize: 12.5))),
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

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}
