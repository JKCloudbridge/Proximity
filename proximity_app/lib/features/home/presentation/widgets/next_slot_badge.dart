import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// SPRINT_PLANNING.md §7.2's live countdown badge, verbatim to the worked
/// example: current time 9:20, next slot starts 10:00 -> "40 min". Once
/// inside the slot's own window: "Now – closes in Xh Ym".
///
/// Deliberately computes and formats everything itself, tick by tick, off
/// [DateTime.now()] rather than a string the server rendered once --
/// `slotStart`/`slotEnd` are the only two numbers that actually need to
/// cross the network (see NearbyShop's file header). Ticks on a 30-second
/// timer -- a minute-granularity countdown doesn't need anything faster,
/// and this widget is one of several on a scrolling list.
class NextSlotBadge extends StatefulWidget {
  const NextSlotBadge({super.key, required this.slotStart, required this.slotEnd});

  final DateTime slotStart;
  final DateTime slotEnd;

  @override
  State<NextSlotBadge> createState() => _NextSlotBadgeState();
}

class _NextSlotBadgeState extends State<NextSlotBadge> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // The slot this badge was given has fully passed and this sprint's
    // slot computation doesn't look ahead to a later one today (see
    // lib/slots.ts's file header) -- rather than show a stale or negative
    // countdown, the badge just disappears until the list is refetched.
    if (!now.isBefore(widget.slotEnd)) return const SizedBox.shrink();

    final inSlot = !now.isBefore(widget.slotStart);
    final label = inSlot
        ? 'Now – closes in ${_formatRemaining(widget.slotEnd.difference(now))}'
        : _formatRemaining(widget.slotStart.difference(now));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: inSlot ? AppColors.brandTint : AppColors.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: inSlot ? AppColors.brandDark : AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  String _formatRemaining(Duration remaining) {
    final totalMinutes = remaining.inMinutes.clamp(0, 999999);
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '$minutes min';
  }
}
