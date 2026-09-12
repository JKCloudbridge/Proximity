import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../features/auth/presentation/auth_provider.dart';
import '../../features/cart/presentation/providers/cart_providers.dart';
import '../../features/home/presentation/providers/home_providers.dart';

/// Global bottom-nav shell -- SPRINT_PLANNING.md §6.1/§7.1: four tabs (Home,
/// Categories, Cart, Order Again), no fifth loyalty tab like Baker Ally had,
/// and deliberately no cart icon in the top bar -- cart lives on the bottom
/// tab only, per the very first requirement in this whole project. Cart's
/// badge count wiring waited for Sprint 6 (cart exists now); the tab itself
/// existed since Sprint 1 so the router/shell shape was fully proven before
/// being retrofitted here.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartCount = ref.watch(cartItemCountProvider);
    final destinations = [
      const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
      const NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: 'Categories'),
      NavigationDestination(
        icon: _CartIcon(count: cartCount, filled: false),
        selectedIcon: _CartIcon(count: cartCount, filled: true),
        label: 'Cart',
      ),
      const NavigationDestination(icon: Icon(Icons.replay_outlined), selectedIcon: Icon(Icons.replay), label: 'Order Again'),
    ];

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
        destinations: destinations,
      ),
    );
  }
}

class _CartIcon extends StatelessWidget {
  const _CartIcon({required this.count, required this.filled});

  final int count;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(filled ? Icons.shopping_cart : Icons.shopping_cart_outlined);
    if (count <= 0) return icon;
    return Badge(
      label: Text(count > 99 ? '99+' : '$count'),
      backgroundColor: AppColors.urgent,
      child: icon,
    );
  }
}

/// Address (left/expanded) + search + avatar (right) -- SPRINT_PLANNING.md
/// §7.1, wired for real in Sprint 4 (the placeholder search box Sprint 1
/// shipped here deliberately said "no address label yet, that's Sprint 4" --
/// this is that). The address reads [buyerLocationProvider] (Home's own
/// "which lat/lng is Shops-near-you using" provider, shared here so the top
/// bar and Home's query never disagree about the buyer's location) and taps
/// through to the address list to change it. No cart icon, per the file
/// header. Avatar routes to /login when signed out, matching the real auth
/// state wired up in Sprint 1.
class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedIn = ref.watch(authProvider.select((s) => s.isLoggedIn));
    final locationAsync = ref.watch(buyerLocationProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => context.push('/addresses'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 20, color: AppColors.brand),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        locationAsync.when(
                          data: (location) => location?.label ?? 'Set your location',
                          loading: () => 'Locating…',
                          error: (error, stackTrace) => 'Set your location',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.inkSoft),
                  ],
                ),
              ),
            ),
          ),
          // Search UX/backend isn't in Sprint 4's scope (§11's entry names
          // shops-near-you + category filtering + the slot badge, not
          // search) -- the icon stays in place per §7.1's layout, wired to
          // an honest "not built yet" rather than a dead tap.
          IconButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Search -- coming soon')),
            ),
            icon: const Icon(Icons.search, color: AppColors.ink),
          ),
          IconButton(
            onPressed: () {
              if (!isLoggedIn) {
                context.push('/login');
              } else {
                context.push('/account');
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
