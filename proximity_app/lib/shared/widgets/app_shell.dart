import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../features/auth/presentation/auth_provider.dart';

/// Global bottom-nav shell -- SPRINT_PLANNING.md §6.1/§7.1: four tabs (Home,
/// Categories, Cart, Order Again), no fifth loyalty tab like Baker Ally had,
/// and deliberately no cart icon in the top bar -- cart lives on the bottom
/// tab only, per the very first requirement in this whole project. Cart's
/// badge count wiring waits for Sprint 6 (cart exists then); the tab itself
/// exists now so the router/shell shape is fully proven in Sprint 1 rather
/// than retrofitted later.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
    NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: 'Categories'),
    NavigationDestination(icon: Icon(Icons.shopping_cart_outlined), selectedIcon: Icon(Icons.shopping_cart), label: 'Cart'),
    NavigationDestination(icon: Icon(Icons.replay_outlined), selectedIcon: Icon(Icons.replay), label: 'Order Again'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Column(
        children: [
          const SafeArea(bottom: false, child: _TopBar()),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex),
        destinations: _destinations,
      ),
    );
  }
}

/// Search (left/expanded) + avatar (right) -- no address label yet (that's
/// Sprint 4, once there's a "shops near you" query that actually uses it)
/// and no cart icon, per the file header. Avatar routes to /login when
/// signed out, matching the real auth state now wired up in Sprint 1.
class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedIn = ref.watch(authProvider.select((s) => s.isLoggedIn));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 18, color: AppColors.inkSoft),
                  const SizedBox(width: 8),
                  Text('Search shops, items...', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: () {
              if (!isLoggedIn) {
                context.push('/login');
              } else {
                context.push('/addresses');
              }
            },
            icon: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.brandTint,
              child: Icon(isLoggedIn ? Icons.person : Icons.person_outline, color: AppColors.brand),
            ),
          ),
        ],
      ),
    );
  }
}
