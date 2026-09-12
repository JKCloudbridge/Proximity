import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/shop_sub_category.dart';
import '../providers/shop_detail_providers.dart';

/// SPRINT_PLANNING.md §7.1's "vertical category rail w/ icon-on-select,
/// scoped to that shop's own shop_sub_categories" -- the classic
/// left-sidebar-of-icons layout, one column, selection highlighted rather
/// than navigating away (tapping an entry re-filters the product grid next
/// to it, it doesn't push a new screen). "All" is a real first entry here
/// (unlike Home's chip row, §7.1 names no equivalent "clear" gesture for a
/// vertical rail, and a rail with nothing highlighted by default would read
/// as broken, not as "no filter").
class SubCategoryRail extends ConsumerWidget {
  const SubCategoryRail({super.key, required this.shopId, required this.subCategories});

  final String shopId;
  final List<ShopSubCategory> subCategories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedSubCategoryIdProvider(shopId));

    return ColoredBox(
      color: AppColors.cream,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _RailEntry(
            label: 'All',
            iconUrl: null,
            selected: selectedId == null,
            onTap: () => ref.read(selectedSubCategoryIdProvider(shopId).notifier).state = null,
          ),
          for (final sub in subCategories)
            _RailEntry(
              label: sub.name,
              iconUrl: sub.iconUrl,
              selected: selectedId == sub.id,
              onTap: () => ref.read(selectedSubCategoryIdProvider(shopId).notifier).state = sub.id,
            ),
        ],
      ),
    );
  }
}

class _RailEntry extends StatelessWidget {
  const _RailEntry({required this.label, required this.iconUrl, required this.selected, required this.onTap});

  final String label;
  final String? iconUrl;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          border: Border(left: BorderSide(color: selected ? AppColors.brand : Colors.transparent, width: 3)),
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: selected ? AppColors.brandTint : AppColors.line,
              child: iconUrl != null
                  ? ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: iconUrl!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Icon(Icons.category_outlined, color: selected ? AppColors.brandDark : AppColors.inkSoft),
                      ),
                    )
                  : Icon(Icons.apps, color: selected ? AppColors.brandDark : AppColors.inkSoft),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected ? AppColors.brandDark : AppColors.inkSoft,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
