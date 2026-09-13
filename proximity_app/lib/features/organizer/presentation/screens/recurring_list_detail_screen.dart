import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency.dart';
import '../../data/models/recurring_list.dart';
import '../providers/organizer_providers.dart';
import '../widgets/item_picker_sheet.dart';

class RecurringListDetailScreen extends ConsumerWidget {
  const RecurringListDetailScreen({super.key, required this.listId});

  final String listId;

  Future<void> _togglePause(BuildContext context, WidgetRef ref, RecurringList list) async {
    try {
      await ref.read(organizerRepositoryProvider).updateSchedule(list.id, isActive: !list.isActive);
      ref.invalidate(recurringListDetailProvider(list.id));
      ref.invalidate(recurringListsProvider);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  Future<void> _editItems(BuildContext context, WidgetRef ref, RecurringList list) async {
    final current = {for (final item in list.items ?? const <RecurringListItem>[]) item.variantId: item.quantity};
    final result = await showItemPickerSheet(context, initialSelection: current);
    if (result == null) return;
    try {
      await ref.read(organizerRepositoryProvider).replaceItems(
            list.id,
            [for (final entry in result.entries) (variantId: entry.key, quantity: entry.value)],
          );
      ref.invalidate(recurringListDetailProvider(list.id));
      ref.invalidate(recurringListsProvider);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update items: $e')));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, RecurringList list) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this list?'),
        content: Text('"${list.name}" will stop reminding you. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(organizerRepositoryProvider).deleteList(list.id);
      ref.invalidate(recurringListsProvider);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(recurringListDetailProvider(listId));

    return Scaffold(
      appBar: AppBar(
        title: listAsync.maybeWhen(data: (list) => Text(list.name), orElse: () => const Text('Recurring list')),
        actions: [
          listAsync.maybeWhen(
            data: (list) => IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context, ref, list)),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load this list: $error')),
        data: (list) {
          final cadence = RecurringListCadence.fromWireValue(list.cadence);
          final items = list.items ?? const <RecurringListItem>[];

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(recurringListDetailProvider(listId)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: Text(
                    list.isActive
                        ? 'Next reminder: ${DateFormat('EEE, d MMM, h:mm a').format(list.nextRunAt.toLocal())}'
                        : 'Paused -- resume to pick up where you left off',
                  ),
                  value: list.isActive,
                  onChanged: (_) => _togglePause(context, ref, list),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.repeat),
                  title: Text(cadence.label),
                  subtitle: Text('Reminds at ${list.timeOfDay.substring(0, 5)} IST'),
                ),
                if (list.lastRunAt != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history),
                    title: const Text('Last reminder'),
                    subtitle: Text(DateFormat('EEE, d MMM, h:mm a').format(list.lastRunAt!.toLocal())),
                  ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Items (${items.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextButton(onPressed: () => _editItems(context, ref, list), child: const Text('Edit items')),
                  ],
                ),
                for (final item in items) _ItemTile(item: item),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final RecurringListItem item;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: item.isAvailable ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: item.productImageUrl != null
                    ? CachedNetworkImage(imageUrl: item.productImageUrl!, fit: BoxFit.cover)
                    : const ColoredBox(color: AppColors.brandTint, child: Icon(Icons.shopping_basket_outlined, size: 16, color: AppColors.brand)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.productName ?? 'Unavailable item', maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (item.unitValue != null) Text('${item.unitValue}${item.unitLabel} · Qty ${item.quantity}', style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                ],
              ),
            ),
            if (item.price != null) Text(formatPaise(item.price! * item.quantity)),
            if (!item.isAvailable) const Padding(padding: EdgeInsets.only(left: 8), child: Text('Unavailable', style: TextStyle(color: AppColors.urgent, fontSize: 12))),
          ],
        ),
      ),
    );
  }
}
