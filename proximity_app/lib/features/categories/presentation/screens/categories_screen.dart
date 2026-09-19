import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../home/data/models/category.dart';
import '../../../home/presentation/providers/home_providers.dart';

/// Sprint 15.md's real Categories tab -- replaces `PlaceholderScreen(title:
/// 'Categories')`, Sprint 1's original stand-in that every other tab
/// (Home/Cart/Order Again) already graduated out of in its own sprint. "A
/// grid of all 20 seeded categories (icon + name, reusing
/// `categoriesProvider` -- itself now also cached per [the caching]
/// section)." No AppBar-level search/filter -- not named in this sprint's
/// scope, same "honest not-built-yet, not a dead tap" rule the top bar's
/// own search icon already follows (app_shell.dart).
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(categoriesProvider),
      child: categoriesAsync.when(
        data: (categories) => categories.isEmpty ? const _EmptyCategories() : _CategoryGrid(categories: categories),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('Could not load categories.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 16, crossAxisSpacing: 12, childAspectRatio: 0.85),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return _CategoryTile(category: category, onTap: () => context.push('/categories/${category.id}'));
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final Category category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: AppColors.brandTint,
            child: category.imageUrl != null
                ? ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: category.imageUrl!,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => const Icon(Icons.category_outlined, color: AppColors.brand, size: 28),
                    ),
                  )
                : const Icon(Icons.category_outlined, color: AppColors.brand, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            category.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _EmptyCategories extends StatelessWidget {
  const _EmptyCategories();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.category_outlined, size: 48, color: AppColors.inkSoft),
                  const SizedBox(height: 12),
                  Text('No categories yet', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.ink)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
