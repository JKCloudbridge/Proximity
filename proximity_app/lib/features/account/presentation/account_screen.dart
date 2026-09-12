import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/auth_provider.dart';

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
