import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency.dart';
import '../../../catalog/data/models/product_variant.dart';
import '../providers/product_detail_providers.dart';

/// §7's PDP spec: "variant selection (price/unit/stock_status per
/// variant)" -- one chip per variant, labeled by its unit ("500 g", "1 kg"),
/// selecting one updates the price/stock line the caller renders alongside
/// this (see ProductDetailScreen). An out-of-stock variant is still shown
/// and still selectable (so its price/MRP remain visible and comparable),
/// just visually muted -- "add to cart" (Sprint 6) is what actually
/// disables on out-of-stock, not the chip itself.
class VariantSelector extends ConsumerWidget {
  const VariantSelector({super.key, required this.productId, required this.variants, required this.selectedVariant});

  final String productId;
  final List<ProductVariant> variants;
  final ProductVariant selectedVariant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: variants.map((variant) {
        final selected = variant.id == selectedVariant.id;
        return ChoiceChip(
          label: Text(_unitLabel(variant), style: TextStyle(color: variant.inStock ? null : AppColors.inkSoft)),
          selected: selected,
          onSelected: (_) => ref.read(selectedVariantIdProvider(productId).notifier).state = variant.id,
          selectedColor: AppColors.brandTint,
          labelStyle: TextStyle(color: selected ? AppColors.brandDark : AppColors.ink, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
          side: BorderSide(color: selected ? AppColors.brand : AppColors.line),
          backgroundColor: Colors.white,
        );
      }).toList(),
    );
  }

  String _unitLabel(ProductVariant variant) {
    final value = variant.unitValue == variant.unitValue.roundToDouble() ? variant.unitValue.toStringAsFixed(0) : variant.unitValue.toString();
    return '$value ${variant.unitLabel}';
  }
}

/// The price/MRP/stock line under the chips -- pulled out of
/// ProductDetailScreen so a single-variant product (no chips to show at
/// all) still renders this consistently.
class VariantPriceRow extends StatelessWidget {
  const VariantPriceRow({super.key, required this.variant});

  final ProductVariant variant;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasDiscount = variant.mrp != null && variant.mrp! > variant.price;

    return Row(
      children: [
        Text(formatPaise(variant.price), style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (hasDiscount) ...[
          const SizedBox(width: 8),
          Text(
            formatPaise(variant.mrp!),
            style: textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft, decoration: TextDecoration.lineThrough),
          ),
        ],
        const Spacer(),
        _StockBadge(status: variant.stockStatus),
      ],
    );
  }
}

class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'out_of_stock' => ('Out of stock', AppColors.urgent),
      'low_stock' => ('Only a few left', AppColors.accent),
      _ => ('In stock', AppColors.success),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
