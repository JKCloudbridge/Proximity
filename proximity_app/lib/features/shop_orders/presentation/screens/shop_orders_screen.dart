import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/errors/cancel_order_exception.dart';
import '../../../../shared/utils/currency.dart';
import '../../data/models/my_shop.dart';
import '../../data/models/shop_order.dart';
import '../providers/shop_orders_providers.dart';

/// Sprint 12 -- rpc_cancel_order's own shop-window gate (migrations/047):
/// legal for a shop up to and including 'ready_for_pickup', refused once
/// 'out_for_delivery' (dispatched) or 'completed'. Mirrored here purely to
/// decide whether to show the button; the RPC is the real authority.
bool _shopCanCancel(String status) =>
    status == 'pending' || status == 'confirmed' || status == 'preparing' || status == 'ready_for_pickup';

/// Sprint 9 -- the shop-side status-advance touchpoint (§5.4's
/// rpc_shop_advance_order_status, brought into this sprint's scope
/// specifically because the rider ladder can't work without it -- see that
/// migration's own header). Lives in proximity_app per §2's system map
/// ("lightweight in-app views for shop-order-notifications
/// (shopkeepers/staff)"), not proximity_web -- deliberately minimal: no
/// filtering, no pagination, no order editing, just the status ladder and
/// the manual rider-assignment retry.
class ShopOrdersScreen extends ConsumerStatefulWidget {
  const ShopOrdersScreen({super.key});

  @override
  ConsumerState<ShopOrdersScreen> createState() => _ShopOrdersScreenState();
}

class _ShopOrdersScreenState extends ConsumerState<ShopOrdersScreen> {
  String? _selectedShopId;

  @override
  Widget build(BuildContext context) {
    final shopsAsync = ref.watch(myShopsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Shop Orders')),
      body: shopsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load your shops: $e')),
        data: (shops) {
          if (shops.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text("You're not part of any shop's team yet.")));
          }
          final selected = _selectedShopId ?? (shops.length == 1 ? shops.first.id : null);
          if (selected == null) {
            return _ShopPicker(shops: shops, onSelected: (id) => setState(() => _selectedShopId = id));
          }
          return _ShopOrdersBody(shopId: selected);
        },
      ),
    );
  }
}

class _ShopPicker extends StatelessWidget {
  const _ShopPicker({required this.shops, required this.onSelected});

  final List<MyShop> shops;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Which shop?', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final shop in shops)
          ListTile(
            title: Text(shop.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onSelected(shop.id),
          ),
      ],
    );
  }
}

class _ShopOrdersBody extends ConsumerWidget {
  const _ShopOrdersBody({required this.shopId});

  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(shopOrdersProvider(shopId));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(shopOrdersProvider(shopId)),
      child: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load orders: $e')),
        data: (orders) => orders.isEmpty
            ? ListView(children: const [Padding(padding: EdgeInsets.only(top: 80), child: Center(child: Text('No orders yet.')))])
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: orders.length,
                itemBuilder: (context, index) => _ShopOrderCard(shopId: shopId, order: orders[index]),
              ),
      ),
    );
  }
}

class _ShopOrderCard extends ConsumerStatefulWidget {
  const _ShopOrderCard({required this.shopId, required this.order});

  final String shopId;
  final ShopOrder order;

  @override
  ConsumerState<_ShopOrderCard> createState() => _ShopOrderCardState();
}

class _ShopOrderCardState extends ConsumerState<_ShopOrderCard> {
  bool _busy = false;

  Future<void> _advance(String status) => _run(() => ref.read(shopOrdersRepositoryProvider).advanceStatus(widget.shopId, widget.order.id, status));

  Future<void> _assignRider() => _run(() => ref.read(shopOrdersRepositoryProvider).assignRider(widget.shopId, widget.order.id));

  /// Sprint 12 -- migrations/048's manual escape hatch: "this rider isn't
  /// responding, find someone else," legal only up to (not including)
  /// 'out_for_delivery' -- see that migration's own header for exactly why.
  Future<void> _reassignRider() =>
      _run(() => ref.read(shopOrdersRepositoryProvider).assignRider(widget.shopId, widget.order.id, force: true));

  /// Sprint 12 -- shop-initiated cancellation (rpc_cancel_order,
  /// migrations/047). One confirmation dialog -- a real order, real
  /// ledger-reversal/rider-release consequences, same "consequential bulk
  /// action deserves a confirmation" bar the buyer-side cancel button uses
  /// (order_confirmation_screen.dart).
  Future<void> _cancelOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: const Text("This can't be undone. Any ledger obligation on this order will be reversed automatically."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep order')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Cancel order')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => ref.read(shopOrdersRepositoryProvider).cancelOrder(widget.shopId, widget.order.id));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(shopOrdersProvider(widget.shopId));
    } on CancelOrderException catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('${order.itemCount} item(s) - ${formatPaise(order.total)}', style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700))),
              _StatusBadge(status: order.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            order.fulfillmentType == 'pickup'
                ? 'Pickup'
                : order.isPlatformRiderDelivery
                    ? 'Delivery - Proximity rider'
                    : 'Delivery - shop',
            style: textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 10),
          if (_busy)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Row(
              children: [
                Expanded(child: _actions()),
                // Sprint 12 -- shown whenever this order is still legally
                // cancellable, alongside whatever the ladder's own primary
                // action is (never replacing it) -- cancelling and advancing
                // are independent choices right up until dispatch.
                if (_shopCanCancel(widget.order.status))
                  IconButton(
                    tooltip: 'Cancel order',
                    onPressed: _cancelOrder,
                    icon: const Icon(Icons.cancel_outlined, color: AppColors.urgent),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _actions() {
    final order = widget.order;

    if (order.status == 'confirmed') {
      return FilledButton(onPressed: () => _advance('preparing'), child: const Text('Mark preparing'));
    }
    if (order.status == 'preparing') {
      return FilledButton(onPressed: () => _advance('ready_for_pickup'), child: const Text('Mark ready'));
    }
    if (order.status == 'ready_for_pickup') {
      if (order.fulfillmentType == 'pickup') {
        return FilledButton(onPressed: () => _advance('completed'), child: const Text('Mark picked up by buyer'));
      }
      if (order.deliveryFulfilledBy == 'shop') {
        return FilledButton(onPressed: () => _advance('out_for_delivery'), child: const Text('Mark out for delivery'));
      }
      // platform_rider -- migrations/039's documented manual-retry fallback.
      if (order.riderId == null) {
        return FilledButton.tonal(onPressed: _assignRider, child: const Text('Assign a rider'));
      }
      // Sprint 12 -- migrations/048's manual "this rider isn't responding"
      // escape hatch, only offered pre-pickup (this branch is
      // 'ready_for_pickup' by construction) -- see forceReassignRider's own
      // header for why it can't help once 'out_for_delivery'.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Text('A rider is on the way to collect this', style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
          ),
          TextButton(onPressed: _reassignRider, child: const Text('Find a different rider')),
        ],
      );
    }
    if (order.status == 'out_for_delivery' && order.deliveryFulfilledBy == 'shop') {
      return FilledButton(onPressed: () => _advance('completed'), child: const Text('Mark delivered'));
    }
    if (order.status == 'out_for_delivery') {
      return Text('The rider is delivering this', style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5));
    }
    return const SizedBox.shrink();
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'pending' => 'Awaiting payment',
      'confirmed' => 'Confirmed',
      'preparing' => 'Preparing',
      'ready_for_pickup' => 'Ready',
      'out_for_delivery' => 'On the way',
      'completed' => 'Completed',
      'cancelled' => 'Cancelled',
      _ => status,
    };
    final color = status == 'cancelled' ? AppColors.urgent : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600)),
    );
  }
}
