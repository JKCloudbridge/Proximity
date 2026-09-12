import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/category.dart';
import '../providers/home_providers.dart';

/// SPRINT_PLANNING.md §7.1's category chip row. Tapping a chip that's
/// already selected deselects it back to "All" -- the only way to clear a
/// filter, since there's no separate "All" chip cluttering the row (its
/// absence of a selection already means that).
class CategoryChipRow extends ConsumerWidget {
  const CategoryChipRow({super.key, required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedCategoryIdProvider);

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = category.id == selectedId;
          return ChoiceChip(
            label: Text(category.name),
            selected: selected,
            onSelected: (_) {
              ref.read(selectedCategoryIdProvider.notifier).state = selected ? null : category.id;
            },
            selectedColor: AppColors.brandTint,
            labelStyle: TextStyle(color: selected ? AppColors.brandDark : AppColors.ink, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
            side: BorderSide(color: selected ? AppColors.brand : AppColors.line),
            backgroundColor: Colors.white,
          );
        },
      ),
    );
  }
}
