import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency.dart';
import '../../data/models/order_group_summary.dart';
import '../providers/checkout_providers.dart';

/// Sprint 10 -- §11's real "Order history," replacing Sprint 9's minimal
/// `MyOrdersScreen` (renamed from that file rather than kept alongside it --
/// GET /v1/order-groups' own header explains the "extend in place, not a
/// second surface" decision). Same entry point §7.5's live tracking needed
/// (account_screen.dart's tile, `/orders`) -- tapping a row still lands on
/// the exact same `OrderConfirmationScreen` + Realtime subscription Sprint 9
/// built; this screen only changes how the buyer finds their way TO a row.
class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  String? _status;

  static const _filters = <({String label, String? value})>[
    (label: 'All', value: null),
    (label: 'Active', value: 'active'),
    (label: 'Completed', value: 'completed'),
    (label: 'Cancelled', value: 'cancelled'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(orderHistoryProvider(_status));

    return Scaffold(
      appBar: AppBar(title: const Text('Order History')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final filter in _filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(filter.label),
                        selected: _status == filter.value,
                        onSelected: (_) => setState(() => _status = filter.value),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(orderHistoryProvider(_status).notifier).refresh(),
              child: _Body(state: state, onLoadMore: () => ref.read(orderHistoryProvider(_status).notifier).loadMore()),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.onLoadMore});

  final OrderHistoryState state;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (state.items.isEmpty && state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.items.isEmpty && state.error != null) {
      return ListView(
        children: [const SizedBox(height: 120), Center(child: Text('Could not load your orders: ${state.error}'))],
      );
    }
    if (state.items.isEmpty) {
      return ListView(
        children: const [
          Padding(padding: EdgeInsets.only(top: 80), child: Center(child: Text("No orders here yet."))),
        ],
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels > notification.metrics.maxScrollExtent - 300) onLoadMore();
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator()));
          }
          return _OrderGroupTile(group: state.items[index]);
        },
      ),
    );
  }
}

class _OrderGroupTile extends StatelessWidget {
  const _OrderGroupTile({required this.group});

  final OrderGroupSummary group;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final shopNames = group.shops.map((s) => s.shopName).join(', ');

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.push('/order-groups/${group.id}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shopNames, style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    '${_dateLabel(group.createdAt)} - ${formatPaise(group.total)}',
                    style: textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                  ),
                  const SizedBox(height: 4),
                  _StatusBadge(status: group.overallStatus),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }

  String _dateLabel(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) { 'active' => 'In progress', 'completed' => 'Completed', 'cancelled' => 'Cancelled', _ => status };
    final color = status == 'cancelled' ? AppColors.urgent : (status == 'active' ? AppColors.accent : AppColors.success);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600)),
    );
  }
}
