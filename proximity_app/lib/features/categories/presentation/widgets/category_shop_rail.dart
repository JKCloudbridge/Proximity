import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../home/data/models/nearby_shop.dart';

/// Sprint 15.md's "left rail lists nearby shops carrying that category" --
/// reuses shop_detail's own established `SubCategoryRail` visual/
/// interaction pattern verbatim (icon-on-select, left-border highlight,
/// re-filters the pane beside it rather than navigating away) with shops in
/// place of sub-categories, per that doc's explicit instruction. Not a
/// literal import of `SubCategoryRail` -- that widget's `_RailEntry` is
/// private and its data type is `ShopSubCategory`, not `NearbyShop` -- but
/// every visual constant below (radii, colors, spacing) is copied from it
/// unchanged, same "no new visual language" rule (§6).
///
/// No "All" entry here, unlike `SubCategoryRail`: that rail's "All" is a
/// real, useful view (this shop's whole catalog); this rail's whole point
/// is picking exactly one shop to see its products in (Sprint 15.md: "the
/// right grid shows the *selected shop's* products"), so [selectedShopId]
/// is always non-null once [shops] is non-empty -- the screen defaults it
/// to the first shop rather than leaving nothing highlighted.
class CategoryShopRail extends StatelessWidget {
  const CategoryShopRail({super.key, required this.categoryId, required this.shops, required this.selectedShopId, required this.onSelect});

  final String categoryId;
  final List<NearbyShop> shops;
  final String? selectedShopId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.cream,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final shop in shops)
            _RailEntry(
              label: shop.name,
              iconUrl: shop.logoUrl,
              selected: selectedShopId == shop.id,
              onTap: () => onSelect(shop.id),
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
                        errorWidget: (context, url, error) => Icon(Icons.storefront_outlined, color: selected ? AppColors.brandDark : AppColors.inkSoft),
                      ),
                    )
                  : Icon(Icons.storefront_outlined, color: selected ? AppColors.brandDark : AppColors.inkSoft),
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
