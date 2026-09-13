import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/realtime/order_status_channel.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/errors/cancel_order_exception.dart';
import '../../../../shared/utils/currency.dart';
import '../../../payments/presentation/attempt_online_payment.dart';
import '../../../payments/presentation/providers/payment_providers.dart';
import '../../data/models/order_group.dart';
import '../providers/checkout_providers.dart';

/// Sprint 12 -- rpc_cancel_order's own buyer-window gate (migrations/047):
/// legal only while this shop's own order is still 'pending' or 'confirmed'
/// -- once a shop moves it to 'preparing' they've started real work and the
/// buyer can no longer self-cancel. Mirrored here purely to decide whether
/// to show the button at all; the RPC is the actual authority (a race where
/// the shop advances status between this check and the tap still gets a
/// clean, typed BUYER_CANCEL_WINDOW_CLOSED error, not a crash).
bool _buyerCanCancel(String status) => status == 'pending' || status == 'confirmed';

final orderGroupProvider = FutureProvider.autoDispose.family<OrderGroup?, String>((ref, id) {
  return ref.watch(checkoutRepositoryProvider).getOrderGroup(id);
});

/// Sprint 8: `group.paymentStatus` now carries real meaning (rpc_confirm_payment,
/// migrations/036) instead of Sprint 7's placeholder inference. One place to
/// turn it into what the buyer sees, rather than re-deriving it per widget.
String _paymentStatusLabel(OrderGroup group) {
  switch (group.paymentStatus) {
    case 'paid':
      return 'Paid';
    case 'collected_at_shop':
      return 'Pay at shop';
    case 'failed':
      return 'Payment failed';
    case 'pending':
    default:
      return group.isPayAtShop ? 'Confirming...' : 'Payment pending';
  }
}

/// SPRINT_PLANNING.md §7.4 step 5: "one card per shop-group, each showing
/// its own fulfillment type, slot, and (if applicable) delivery-fee line --
/// **never a single merged summary line**, per your explicit instruction."
/// That's the whole reason this screen exists as its own thing rather than a
/// receipt dialog: a two-shop checkout has two genuinely different promises
/// in it ("Shop A: pickup 4-6 PM", "Shop B: rider delivery 10 AM-12 PM"),
/// and flattening them into one line is exactly what §4.8's redesign set out
/// to stop.
class OrderConfirmationScreen extends ConsumerWidget {
  const OrderConfirmationScreen({super.key, required this.orderGroupId});

  final String orderGroupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(orderGroupProvider(orderGroupId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order confirmed'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(onPressed: () => context.go('/'), child: const Text('Done')),
        ],
      ),
      body: groupAsync.when(
        data: (group) => group == null
            ? const Center(child: Text('Order not found.'))
            : _Body(orderGroupId: orderGroupId, group: group),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const Center(child: Text('Could not load this order.')),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.orderGroupId, required this.group});

  final String orderGroupId;
  final OrderGroup group;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _retrying = false;

  // Sprint 9 -- §7.5's live tracking. Accumulated client-side per order id
  // as Realtime pings arrive while this screen is open (a fresh session
  // starts empty and fills in as things happen -- an honest "live from now"
  // feed, not a full history backfill, which would need its own REST route
  // this sprint doesn't add). Any ping also invalidates orderGroupProvider
  // so the top-level status chip/payment-status/totals stay correct even
  // for the events that don't get their own timeline line (see
  // order_status_channel.dart and migrations/042's header for why some
  // ladder steps share one orders.status value).
  final Map<String, List<OrderStatusEvent>> _liveEvents = {};

  /// Sprint 8: same idempotent create-order/pay/verify sequence
  /// checkout_screen.dart's own post-placement attempt already runs -- one
  /// shared implementation (attemptOnlinePayment), two call sites. Re-fetches
  /// the group afterward regardless of outcome: `paymentStatus` is the one
  /// honest signal either attempt actually changed anything.
  Future<void> _retryPayment() async {
    setState(() => _retrying = true);
    await attemptOnlinePayment(ref, widget.orderGroupId);
    ref.invalidate(orderGroupProvider(widget.orderGroupId));
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final textTheme = Theme.of(context).textTheme;
    final needsPaymentRetry = group.paymentMode == 'online' && group.paymentStatus == 'pending';

    // One subscription per screen, covering every shop-group's orders --
    // orderStatusEventsProvider is keyed by this joined string (Riverpod
    // .family needs a value-equal key, not a List, see that file's header).
    final orderIdsKey = group.orders.map((o) => o.id).join(',');
    ref.listen(orderStatusEventsProvider(orderIdsKey), (previous, next) {
      next.whenData((event) {
        setState(() => _liveEvents.putIfAbsent(event.orderId, () => []).add(event));
        ref.invalidate(orderGroupProvider(widget.orderGroupId));
      });
    });

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.brandTint, borderRadius: BorderRadius.circular(14)),
          child: Column(
            children: [
              const Icon(Icons.check_circle, color: AppColors.brand, size: 36),
              const SizedBox(height: 8),
              Text(
                group.isPayAtShop ? 'Order placed - pay at the shop' : 'Order placed',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.brandDark),
              ),
              const SizedBox(height: 4),
              Text(
                group.orders.length == 1
                    ? '1 shop'
                    : '${group.orders.length} shops, charged once',
                style: textTheme.labelMedium?.copyWith(color: AppColors.brandDark),
              ),
            ],
          ),
        ),
        if (needsPaymentRetry) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.urgent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.urgent, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "Payment wasn't completed. Your order is saved -- finish paying to confirm it.",
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _retrying ? null : _retryPayment,
                  child: _retrying
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        // One card per `orders` row -- §4.8's "one card per shop-group."
        for (final order in group.orders)
          _OrderCard(order: order, liveEvents: _liveEvents[order.id] ?? const []),
        const SizedBox(height: 8),
        _TotalsCard(group: group),
      ],
    );
  }
}

/// Sprint 9 -- raw order_status_history.status words -> what the buyer
/// reads. Deliberately a superset of _StatusChip's own switch below: some of
/// these (rider_assigned, rider_accepted, picked_up) are never
/// `orders.status` values at all (migrations/039/041/042's own headers
/// explain why) -- they only ever show up here, in the live feed, not in
/// the status chip.
String _liveEventLabel(String status) {
  return switch (status) {
    'rider_assigned' => 'A rider has been assigned',
    'rider_accepted' => 'The rider accepted this delivery',
    'picked_up' => 'Picked up by the rider',
    'out_for_delivery' => 'Out for delivery',
    'delivered' => 'Delivered',
    'preparing' => 'The shop is preparing your order',
    'ready_for_pickup' => 'Ready',
    'completed' => 'Completed',
    'confirmed' => 'Confirmed',
    _ => status,
  };
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order, this.liveEvents = const []});

  final OrderGroupOrder order;

  /// §7.5's live tracking -- events received over Realtime while this
  /// screen has been open, oldest first. Empty on a fresh screen open; not
  /// a full history (see _BodyState's own comment for why that's an honest,
  /// deliberate scope cut, not a bug).
  final List<OrderStatusEvent> liveEvents;

  Future<void> _viewInvoice(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final invoice = await ref.read(paymentRepositoryProvider).getInvoice(order.id);
    if (invoice == null) {
      messenger.showSnackBar(const SnackBar(content: Text("This shop's invoice isn't ready yet -- try again shortly.")));
      return;
    }
    final uri = Uri.parse(invoice.url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not open the invoice.')));
    }
  }

  /// Sprint 12 -- buyer-initiated cancellation. One confirmation dialog
  /// (this is money/a real order, not a wishlist toggle -- same "a bulk
  /// section-level action is more consequential" reasoning the cart
  /// screen's own "Remove all from this shop" confirmation gave in Sprint
  /// 6), then the real call. `orderGroupProvider` is invalidated on success
  /// so the card's own status chip and the confirmation screen's per-shop
  /// section reflect 'cancelled' immediately, same refetch-after-mutation
  /// convention every other write in this app follows.
  Future<void> _cancelOrder(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: Text("This will cancel your order from ${order.shopName}. This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep order')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Cancel order')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(checkoutRepositoryProvider).cancelOrder(order.id);
      ref.invalidate(orderGroupProvider);
      if (context.mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('Order cancelled.')));
      }
    } on CancelOrderException catch (err) {
      if (context.mounted) messenger.showSnackBar(SnackBar(content: Text(err.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_outlined, size: 18, color: AppColors.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(order.shopName, style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
              _StatusChip(status: order.status),
            ],
          ),
          const SizedBox(height: 10),
          _line(
            context,
            icon: order.isPickup ? Icons.storefront : Icons.delivery_dining,
            text: order.isPickup
                ? 'Pickup from the shop'
                : order.isRiderDelivery
                    ? 'Delivered by a Proximity rider'
                    : 'Delivered by the shop',
          ),
          _line(context, icon: Icons.schedule, text: _slotLabel(order)),
          if (!order.isPickup && order.addressLine != null)
            _line(context, icon: Icons.location_on_outlined, text: order.addressLine!),
          // Sprint 9 -- §7.5's "no polling" live feed. Only ever shows
          // events received since this screen opened (see liveEvents' own
          // doc comment) -- silent, not missing, when nothing has happened
          // yet.
          if (liveEvents.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final event in liveEvents)
              _line(context, icon: Icons.bolt, text: _liveEventLabel(event.status)),
          ],
          const Divider(height: 18),
          for (final item in order.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.quantity} x ${item.productName} (${item.variantName})',
                      style: textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(formatPaise(item.lineTotal), style: textTheme.bodySmall),
                ],
              ),
            ),
          const SizedBox(height: 6),
          // Each shop's own money, per §4.8 -- including its delivery-fee
          // line only when it actually has one (§1.3: a shop delivering its
          // own order never does).
          _amountRow(context, 'Subtotal', formatPaise(order.subtotal)),
          if (order.discountValue > 0) _amountRow(context, 'Discount', '-${formatPaise(order.discountValue)}'),
          if (order.deliveryFee > 0) _amountRow(context, 'Delivery fee', formatPaise(order.deliveryFee)),
          _amountRow(context, 'This shop', formatPaise(order.total), bold: true),
          // Sprint 8: an invoice only exists once this shop's own order has
          // actually been confirmed (rpc_generate_invoice refuses a
          // 'pending'/'cancelled' order, migrations/037) -- shown only past
          // that point rather than a button that would just 404 before then.
          if (order.status != 'pending' && order.status != 'cancelled') ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _viewInvoice(context, ref),
                icon: const Icon(Icons.receipt_long_outlined, size: 16),
                label: const Text('View invoice'),
              ),
            ),
          ],
          // Sprint 12 -- §11's Sprint 12 entry: "a real cancellation flow --
          // buyer-initiated (before a shop accepts)." Shown only inside the
          // RPC's own legal window (_buyerCanCancel) -- past that, the
          // button simply isn't there rather than being shown-then-refused,
          // same "gray it out / hide it" discipline this screen already
          // applies to the invoice link above.
          if (_buyerCanCancel(order.status)) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _cancelOrder(context, ref),
                icon: const Icon(Icons.cancel_outlined, size: 16, color: AppColors.urgent),
                label: const Text('Cancel order', style: TextStyle(color: AppColors.urgent)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _slotLabel(OrderGroupOrder order) {
    final start = order.slotStart.toLocal();
    final end = order.slotEnd.toLocal();
    String hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${start.day}/${start.month}, ${hhmm(start)} - ${hhmm(end)}';
  }

  Widget _line(BuildContext context, {required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.inkSoft),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }

  Widget _amountRow(BuildContext context, String label, String value, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, fontSize: 13);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'pending' => 'Awaiting shop',
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

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.group});

  final OrderGroup group;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          _row(context, 'Subtotal', formatPaise(group.subtotal)),
          if (group.discountValue > 0)
            _row(context, 'Discount${group.discountCode != null ? ' (${group.discountCode})' : ''}', '-${formatPaise(group.discountValue)}'),
          _row(context, 'Delivery', group.deliveryFeeTotal == 0 ? 'Free' : formatPaise(group.deliveryFeeTotal)),
          const Divider(height: 18),
          _row(context, _paymentStatusLabel(group), formatPaise(group.total), bold: true),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              group.isPayAtShop
                  ? 'Settle directly with each shop on pickup or delivery.'
                  : 'Charged once for all shops in this order.',
              style: textTheme.labelSmall?.copyWith(color: AppColors.inkSoft),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400, fontSize: bold ? 16 : 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
