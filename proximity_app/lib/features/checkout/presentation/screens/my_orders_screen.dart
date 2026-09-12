import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency.dart';
import '../../data/models/order_group_summary.dart';
import '../providers/checkout_providers.dart';

/// Sprint 9 -- the minimal, real entry point §7.5's now-live tracking needed
/// (see GET /v1/order-groups' own header on the backend for the full
/// reasoning): before this screen existed, `/order-groups/:id` was reachable
/// only as a one-time push straight off a just-completed checkout -- nothing
/// could navigate back to an order placed earlier and then backgrounded or
/// closed. This is NOT §11's Sprint 10 "Order history / Order Again"
/// feature -- no reorder, no filtering, no pagination, just the buyer's own
/// order_groups, most recent first, each tappable into the same live
/// tracking screen this sprint already built.
class MyOrdersScreen extends ConsumerWidget {
  const MyOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(myOrderGroupsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Orders')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myOrderGroupsProvider),
        child: groupsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load your orders: $e')),
          data: (groups) => groups.isEmpty
              ? ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: Text("You haven't placed an order yet.")),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: groups.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _OrderGroupTile(group: groups[index]),
                ),
        ),
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
