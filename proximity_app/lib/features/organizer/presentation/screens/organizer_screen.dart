import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/recurring_list.dart';
import '../providers/organizer_providers.dart';

/// Sprint 11 -- Organizer's own list screen. Reached from the account menu
/// (account_screen.dart, same "no bottom-nav tab of its own" treatment
/// My Wishlist got in Sprint 5 -- §7.1 names four tabs, Organizer isn't one
/// of them). Own-user data, gated by the route itself (app_router.dart's
/// `_protectedPaths`), same shape `/wishlist` already uses -- unlike Cart,
/// this screen has no meaningful "browse while signed out" use case at all.
class OrganizerScreen extends ConsumerWidget {
  const OrganizerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listsAsync = ref.watch(recurringListsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring lists')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/organizer/new'),
        child: const Icon(Icons.add),
      ),
      body: listsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load your lists: $error')),
        data: (lists) {
          if (lists.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "No recurring lists yet. Create one from products you buy regularly, and we'll remind you and pre-fill your cart on schedule.",
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(recurringListsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: lists.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _RecurringListTile(list: lists[index]),
            ),
          );
        },
      ),
    );
  }
}

class _RecurringListTile extends StatelessWidget {
  const _RecurringListTile({required this.list});

  final RecurringList list;

  @override
  Widget build(BuildContext context) {
    final cadence = RecurringListCadence.fromWireValue(list.cadence);
    final nextRunLocal = list.nextRunAt.toLocal();

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: () => context.push('/organizer/${list.id}'),
        title: Text(list.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${cadence.label} · ${list.itemCount ?? 0} item(s)\n'
          '${list.isActive ? "Next: " : "Paused · would be "}${DateFormat('EEE, d MMM, h:mm a').format(nextRunLocal)}',
        ),
        isThreeLine: true,
        trailing: list.isActive
            ? null
            : const Icon(Icons.pause_circle_outline, color: AppColors.inkSoft),
      ),
    );
  }
}
