import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/rider_order.dart';
import '../../data/models/rider_profile.dart';
import '../providers/rider_providers.dart';

/// Sprint 9 -- §8.5's working-rider experience: online/offline toggle,
/// the incoming-assignment surface (a live Realtime ping, see
/// rider_assignment_channel.dart's header for why Realtime rather than
/// push), Accept, and the status ladder. Shown by rider_onboarding_screen.dart
/// once `profile.isVerified` -- that screen's own placeholder text
/// ("Delivery assignments ... land in a later update") is what this
/// replaces.
class RiderHomeScreen extends ConsumerStatefulWidget {
  const RiderHomeScreen({super.key, required this.profile});

  final RiderProfile profile;

  @override
  ConsumerState<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends ConsumerState<RiderHomeScreen> {
  bool _togglingStatus = false;

  Future<void> _toggleOnline(bool goOnline) async {
    setState(() => _togglingStatus = true);
    try {
      await ref.read(riderRepositoryProvider).setStatus(goOnline ? 'available' : 'offline');
      ref.invalidate(myRiderProfileProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update status: $e')));
      }
    } finally {
      if (mounted) setState(() => _togglingStatus = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;

    // Sprint 9 -- the Realtime "you have a new assignment" surface (§8.5).
    // Any ping (new assignment, or a status another party changed) just
    // invalidates the order list; the REST re-fetch is what actually
    // renders, same "Realtime tells you to refetch" split every Realtime
    // consumer in this sprint uses.
    ref.listen(riderAssignmentPingForSelfProvider, (previous, next) {
      next.whenData((_) => ref.invalidate(riderOrdersProvider));
    });

    // A location ping stream runs for the lifetime of this screen only
    // while on_delivery -- started/stopped reactively rather than tied to
    // widget lifecycle directly, so going offline mid-session (impossible
    // per the backend's own on_delivery guard, but harmless to handle
    // defensively) or coming back online doesn't need this screen rebuilt.
    final pinger = ref.watch(riderLocationPingerProvider);
    if (profile.status == 'on_delivery') {
      pinger.start();
    } else {
      pinger.stop();
    }

    final ordersAsync = ref.watch(riderOrdersProvider);

    // No Scaffold/AppBar of its own -- rider_onboarding_screen.dart's
    // Scaffold hosts this as its body once `profile.isVerified`, same
    // "plain content, outer screen owns the chrome" shape `_RiderStatusCard`
    // (the not-yet-verified branch) already uses there.
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(riderOrdersProvider),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusToggleCard(profile: profile, busy: _togglingStatus, onToggle: _toggleOnline),
          const SizedBox(height: 16),
          ordersAsync.when(
            loading: () => const Padding(padding: EdgeInsets.only(top: 32), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(padding: const EdgeInsets.only(top: 32), child: Center(child: Text('Could not load deliveries: $e'))),
            data: (orders) => orders.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: Center(
                      child: Text(
                        profile.status == 'available'
                            ? "You're online. New deliveries will appear here as soon as they're assigned."
                            : 'Go online to start receiving deliveries.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.inkSoft),
                      ),
                    ),
                  )
                : Column(children: [for (final order in orders) _RiderOrderCard(order: order)]),
          ),
        ],
      ),
    );
  }
}

class _StatusToggleCard extends StatelessWidget {
  const _StatusToggleCard({required this.profile, required this.busy, required this.onToggle});

  final RiderProfile profile;
  final bool busy;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final onDelivery = profile.status == 'on_delivery';
    final online = profile.status == 'available' || onDelivery;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.brandTint, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(online ? Icons.radio_button_checked : Icons.radio_button_off, color: AppColors.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              onDelivery ? 'On a delivery' : (online ? "You're online" : "You're offline"),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (busy)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else if (!onDelivery)
            Switch(value: online, onChanged: onToggle),
        ],
      ),
    );
  }
}

class _RiderOrderCard extends ConsumerStatefulWidget {
  const _RiderOrderCard({required this.order});

  final RiderOrder order;

  @override
  ConsumerState<_RiderOrderCard> createState() => _RiderOrderCardState();
}

class _RiderOrderCardState extends ConsumerState<_RiderOrderCard> {
  bool _busy = false;

  Future<void> _accept() => _run(() => ref.read(riderRepositoryProvider).acceptOrder(widget.order.id));

  Future<void> _advance(String status) => _run(() => ref.read(riderRepositoryProvider).updateOrderStatus(widget.order.id, status));

  /// Sprint 12 -- the other half of §8.5's "Accept" (rpc_rider_decline_order,
  /// migrations/048). A confirmation dialog, same bar every other
  /// consequential action in this app uses -- declining immediately frees
  /// this rider and tries to hand the order to someone else server-side.
  Future<void> _decline() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Decline this delivery?'),
        content: const Text("We'll try to find another rider for it right away."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Decline')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => ref.read(riderRepositoryProvider).declineOrder(widget.order.id));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(riderOrdersProvider);
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
      key: ValueKey(order.id),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(order.shopName, style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('${order.shopAddressLine}, ${order.shopCity}', style: textTheme.bodySmall?.copyWith(color: AppColors.inkSoft)),
          const SizedBox(height: 10),
          _actionRow(context),
        ],
      ),
    );
  }

  Widget _actionRow(BuildContext context) {
    final order = widget.order;

    if (_busy) {
      return const Align(alignment: Alignment.centerLeft, child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
    }

    // §8.5's ladder, gated on riderLadderStep (not `status` alone -- see
    // rider_order.dart's own comment on why). Decline (Sprint 12) is only
    // offered here, before Accept -- rpc_rider_decline_order itself refuses
    // it past that point (migrations/048's own header).
    if (order.riderLadderStep == null) {
      return Row(
        children: [
          Expanded(child: FilledButton(onPressed: _accept, child: const Text('Accept'))),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _decline, child: const Text('Decline')),
        ],
      );
    }
    if (order.riderLadderStep == 'rider_accepted') {
      if (order.status != 'ready_for_pickup') {
        return Text('Waiting for the shop to mark this ready', style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5));
      }
      return FilledButton(onPressed: () => _advance('picked_up'), child: const Text('Mark picked up'));
    }
    if (order.riderLadderStep == 'picked_up') {
      return FilledButton(onPressed: () => _advance('out_for_delivery'), child: const Text('Mark out for delivery'));
    }
    if (order.riderLadderStep == 'out_for_delivery') {
      return FilledButton(onPressed: () => _advance('delivered'), child: const Text('Mark delivered'));
    }
    return const SizedBox.shrink();
  }
}
