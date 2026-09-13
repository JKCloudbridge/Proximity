import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_provider.dart';
import '../../shop_orders/presentation/providers/shop_orders_providers.dart';

/// Placeholder for the real profile_overlay_sheet.dart port (§7.6,
/// referenced in Sprint 1.md as still-pending) -- a plain screen rather than
/// the bottom-sheet Baker Ally used, since that port isn't this sprint's
/// job. Exists now specifically to give "Become a rider" (§8.5) a real,
/// navigable entry point instead of bolting it onto the avatar tap
/// directly -- app_shell.dart's avatar now routes here instead of straight
/// to /addresses.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(authProvider.select((s) => s.role));
    // Sprint 9 -- only shown once the buyer is actually on ≥1 shop's team;
    // an empty list (the common case -- most buyers never run a shop) means
    // this tile simply doesn't render, same "don't show a section with
    // nothing under it" rule Home's Recommended-for-you section already
    // established in Sprint 6.
    // riverpod 3.x renamed AsyncValue's old `valueOrNull` to a plain
    // nullable `value` getter -- checked against the actually-installed
    // riverpod 3.4.2 source before using this, not assumed from an older
    // API shape (same discipline auth_provider.dart's header already
    // applied to StateNotifier's own Riverpod-3 relocation).
    final myShops = ref.watch(myShopsProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Addresses'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/addresses'),
          ),
          const Divider(height: 1),
          // Sprint 5 -- wishlists (§4.10/§11). Protected route
          // (app_router.dart's `_protectedPaths`), so this tile is the same
          // "gated at the specific action" entry point Addresses already is
          // here, not a new pattern.
          ListTile(
            leading: const Icon(Icons.favorite_border),
            title: const Text('My Wishlist'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/wishlist'),
          ),
          const Divider(height: 1),
          // Sprint 9 built this as a way back into a live-tracking order
          // (§7.5); Sprint 10 is the real Order History screen this now
          // points to (OrderHistoryScreen, formerly the minimal
          // MyOrdersScreen) -- same route, same entry point, real feature.
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Order History'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/orders'),
          ),
          const Divider(height: 1),
          if (myShops.isNotEmpty) ...[
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Shop Orders'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/shop-orders'),
            ),
            const Divider(height: 1),
          ],
          // Anyone not already a rider/admin can apply -- a shop owner
          // moonlighting as a rider is an edge case the RPC already
          // tolerates (migrations/015 never downgrades an admin, but a
          // shop_owner does flip to 'rider'); not worth hiding this tile
          // over.
          if (role != 'admin')
            ListTile(
              leading: const Icon(Icons.pedal_bike_outlined),
              title: const Text('Become a rider'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/rider/onboarding'),
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Sign out', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await ref.read(authProvider.notifier).signOut();
              if (context.mounted) context.go('/');
            },
          ),
        ],
      ),
    );
  }
}
