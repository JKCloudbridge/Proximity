import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/fulfillment_slot.dart';
import '../providers/checkout_providers.dart';

/// §7.4 step 1's slot picker: a day selector over `GET /v1/shops/:id/
/// fulfillment-slots` (§4.6), with **unavailable slots shown greyed and
/// labelled with their reason rather than hidden** -- that section asks for
/// this specifically, and it's the difference between "the shop has no 8 PM
/// slot" and "the shop closes at 6".
///
/// Dates here are the device's own local calendar days, which inherits the
/// same single-country IST assumption lib/slots.ts documents on the server
/// side -- there is still no per-shop timezone anywhere in this schema to do
/// anything better with.
class SlotPickerSheet extends ConsumerStatefulWidget {
  const SlotPickerSheet({
    super.key,
    required this.shopId,
    required this.shopName,
    required this.fulfillmentType,
    required this.onSelected,
  });

  final String shopId;
  final String shopName;
  final String fulfillmentType;
  final ValueChanged<FulfillmentSlot> onSelected;

  @override
  ConsumerState<SlotPickerSheet> createState() => _SlotPickerSheetState();
}

class _SlotPickerSheetState extends ConsumerState<SlotPickerSheet> {
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
  }

  String get _dateString {
    final d = _selectedDay;
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final slotsAsync = ref.watch(
      slotsProvider((shopId: widget.shopId, date: _dateString, type: widget.fulfillmentType)),
    );
    final today = DateTime.now();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.fulfillmentType == 'pickup' ? 'Pickup time' : 'Delivery time',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(widget.shopName, style: textTheme.labelMedium?.copyWith(color: AppColors.inkSoft)),
            const SizedBox(height: 12),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 7,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final day = DateTime(today.year, today.month, today.day).add(Duration(days: index));
                  final selected = day.year == _selectedDay.year && day.month == _selectedDay.month && day.day == _selectedDay.day;
                  return _DayChip(
                    day: day,
                    isToday: index == 0,
                    selected: selected,
                    onTap: () => setState(() => _selectedDay = day),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
              child: slotsAsync.when(
                data: (day) {
                  if (day.unsupported) {
                    return _Message(
                      text: widget.fulfillmentType == 'pickup'
                          ? "This shop doesn't offer pickup."
                          : "This shop doesn't offer delivery.",
                    );
                  }
                  if (day.slots.isEmpty) {
                    return const _Message(text: 'No slots configured for this day.');
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: day.slots.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _SlotRow(
                      slot: day.slots[index],
                      onTap: () {
                        widget.onSelected(day.slots[index]);
                        Navigator.pop(context);
                      },
                    ),
                  );
                },
                loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                error: (error, stackTrace) => const _Message(text: 'Could not load slots. Pull to retry.'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.day, required this.isToday, required this.selected, required this.onTap});

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  final DateTime day;
  final bool isToday;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandTint : Colors.white,
          border: Border.all(color: selected ? AppColors.brand : AppColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isToday ? 'Today' : _weekdays[day.weekday - 1],
              style: TextStyle(fontSize: 11, color: selected ? AppColors.brandDark : AppColors.inkSoft),
            ),
            const SizedBox(height: 2),
            Text(
              '${day.day}',
              style: TextStyle(fontWeight: FontWeight.w700, color: selected ? AppColors.brandDark : AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.slot, required this.onTap});

  final FulfillmentSlot slot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Opacity(
      opacity: slot.available ? 1 : 0.55,
      child: InkWell(
        onTap: slot.available ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
          ),
          child: Row(
            children: [
              Icon(
                slot.available ? Icons.schedule : Icons.block,
                size: 18,
                color: slot.available ? AppColors.brand : AppColors.inkSoft,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(slot.label, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    if (!slot.available && slot.unavailableReason != null)
                      Text(slot.unavailableReason!, style: textTheme.labelSmall?.copyWith(color: AppColors.inkSoft)),
                  ],
                ),
              ),
              if (slot.available) const Icon(Icons.chevron_right, color: AppColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
        ),
      ),
    );
  }
}
