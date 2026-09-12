import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/currency.dart';
import '../../../addresses/data/models/address.dart';
import '../../../addresses/presentation/providers/address_providers.dart';
import '../../../cart/data/models/cart_item.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../providers/checkout_providers.dart';
import '../widgets/shop_fulfillment_card.dart';

/// SPRINT_PLANNING.md §7.4 steps 1-4, §11's Sprint 7 scope. One scrollable
/// screen with numbered sections rather than a four-page wizard -- a
/// deliberate reading of "in sequence," not an oversight: with a multi-shop
/// cart the buyer routinely needs to go back and change one shop's slot
/// after seeing the total, and a wizard turns that into a navigation
/// problem. The sections still gate in order (the pay button stays disabled
/// until every earlier decision is made), which is the part that matters.
///
/// Step 5 (confirmation) is its own screen -- OrderConfirmationScreen.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _discountController = TextEditingController();
  bool _placing = false;
  String? _discountError;
  String? _placeError;

  @override
  void dispose() {
    _discountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cartAsync = ref.watch(cartProvider);
    final configAsync = ref.watch(checkoutConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: cartAsync.when(
        data: (items) {
          if (items.isEmpty) return const _EmptyCartNotice();
          final riderFee = configAsync.value?.platformRiderDeliveryFee ?? 0;
          return _CheckoutBody(
            items: items,
            riderFee: riderFee,
            discountController: _discountController,
            discountError: _discountError,
            placeError: _placeError,
            placing: _placing,
            onApplyDiscount: _applyDiscount,
            onClearDiscount: _clearDiscount,
            onPlace: _placeOrder,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const Center(child: Text('Could not load your cart.')),
      ),
    );
  }

  Future<void> _applyDiscount(int subtotal) async {
    final code = _discountController.text.trim();
    if (code.isEmpty) return;
    setState(() => _discountError = null);

    final preview = await ref.read(checkoutRepositoryProvider).previewDiscount(code: code, subtotal: subtotal);
    if (!mounted) return;
    if (preview == null) {
      setState(() => _discountError = "That code isn't valid for this order");
      return;
    }
    ref.read(checkoutDraftProvider.notifier).applyDiscount(preview.code, preview);
  }

  void _clearDiscount() {
    _discountController.clear();
    setState(() => _discountError = null);
    ref.read(checkoutDraftProvider.notifier).clearDiscount();
  }

  Future<void> _placeOrder() async {
    final draft = ref.read(checkoutDraftProvider);
    setState(() {
      _placing = true;
      _placeError = null;
    });

    try {
      final fulfillment = draft.byShop.entries.map((entry) {
        final d = entry.value;
        return <String, dynamic>{
          'shopId': entry.key,
          'fulfillmentType': d.fulfillmentType,
          'deliveryFulfilledBy': d.isDelivery ? d.deliveryFulfilledBy : null,
          'slotStart': d.slotStart!.toUtc().toIso8601String(),
          'slotEnd': d.slotEnd!.toUtc().toIso8601String(),
        };
      }).toList();

      final group = await ref.read(checkoutRepositoryProvider).placeOrder(
            fulfillment: fulfillment,
            addressId: draft.anyDelivery ? draft.addressId : null,
            paymentMode: draft.paymentMode,
            discountCode: draft.discountCode,
          );

      // rpc_place_order cleared the cart server-side as part of the same
      // transaction -- refetch so the badge/cart screen agree, and drop the
      // draft so a later checkout doesn't inherit stale selections.
      ref.invalidate(cartProvider);
      ref.read(checkoutDraftProvider.notifier).reset();
      if (!mounted) return;
      context.pushReplacement('/order-groups/${group.id}');
    } on DioException catch (err) {
      final data = err.response?.data;
      final message = data is Map ? (data['error']?['message'] as String?) : null;
      if (!mounted) return;
      setState(() => _placeError = message ?? 'Could not place your order. Please try again.');
      // Anything the server rejected on freshness grounds (a slot that just
      // passed, an item that just went out of stock) means the cart or slots
      // this screen is showing are already stale -- refetch rather than let
      // the buyer retry against the same bad data.
      ref.invalidate(cartProvider);
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }
}

class _CheckoutBody extends ConsumerWidget {
  const _CheckoutBody({
    required this.items,
    required this.riderFee,
    required this.discountController,
    required this.discountError,
    required this.placeError,
    required this.placing,
    required this.onApplyDiscount,
    required this.onClearDiscount,
    required this.onPlace,
  });

  final List<CartItem> items;
  final int riderFee;
  final TextEditingController discountController;
  final String? discountError;
  final String? placeError;
  final bool placing;
  final ValueChanged<int> onApplyDiscount;
  final VoidCallback onClearDiscount;
  final VoidCallback onPlace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byShop = <String, List<CartItem>>{};
    for (final item in items) {
      byShop.putIfAbsent(item.shop.id, () => []).add(item);
    }

    // Keep the draft's shop set in step with the cart's on every build --
    // rpc_place_order rejects a fulfillment array that doesn't match the
    // cart exactly (SHOP_GROUP_MISMATCH), so a shop removed from the cart in
    // another tab must not leave a stale group behind. Deferred out of the
    // build phase because it writes provider state.
    final shopIds = byShop.keys.toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(checkoutDraftProvider.notifier).syncShops(shopIds);
    });

    final draft = ref.watch(checkoutDraftProvider);
    final addressesAsync = ref.watch(addressesProvider);

    final subtotal = items.fold<int>(0, (sum, item) => sum + item.lineTotalPaise);
    final discountAmount = draft.discount?.amount ?? 0;
    final freeShipping = draft.discount?.freeShipping ?? false;
    final riderGroups = draft.byShop.values.where((d) => d.deliveryFulfilledBy == 'platform_rider').length;
    final deliveryTotal = freeShipping ? 0 : riderGroups * riderFee;
    final total = subtotal - discountAmount + deliveryTotal;

    final blockedByMinimum = byShop.entries.any((entry) {
      final shopSubtotal = entry.value.fold<int>(0, (sum, i) => sum + i.lineTotalPaise);
      return shopSubtotal < entry.value.first.shop.minOrderValue;
    });
    final canPlace = draft.isReady && !blockedByMinimum && !placing;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            children: [
              const _SectionHeader(number: '1', title: 'How would you like each order?'),
              for (final entry in byShop.entries)
                ShopFulfillmentCard(
                  key: ValueKey(entry.key),
                  shop: entry.value.first.shop,
                  subtotal: entry.value.fold<int>(0, (sum, i) => sum + i.lineTotalPaise),
                  itemCount: entry.value.length,
                  riderFee: riderFee,
                ),
              if (draft.anyDelivery) ...[
                const _SectionHeader(number: '2', title: 'Delivery address'),
                _AddressSection(addressesAsync: addressesAsync, selectedId: draft.addressId),
              ],
              _SectionHeader(number: draft.anyDelivery ? '3' : '2', title: 'Payment'),
              _PaymentSection(draft: draft),
              const SizedBox(height: 8),
              _DiscountSection(
                controller: discountController,
                error: discountError,
                applied: draft.discount,
                onApply: () => onApplyDiscount(subtotal),
                onClear: onClearDiscount,
              ),
              const SizedBox(height: 12),
              _SummaryCard(
                byShop: byShop,
                draft: draft,
                riderFee: riderFee,
                freeShipping: freeShipping,
                subtotal: subtotal,
                discountAmount: discountAmount,
                deliveryTotal: deliveryTotal,
                total: total,
              ),
              if (placeError != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.urgent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Text(placeError!, style: const TextStyle(color: AppColors.urgent, fontWeight: FontWeight.w600)),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.line))),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total', style: TextStyle(color: AppColors.inkSoft, fontSize: 12)),
                      Text(formatPaise(total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: canPlace ? onPlace : null,
                  child: placing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(draft.paymentMode == 'pay_at_shop' ? 'Confirm order' : 'Pay ${formatPaise(total)}'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.number, required this.title});

  final String number;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: AppColors.brand,
            child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// §7.4 step 2: "one delivery address selection applies to every shop-group
/// that chose delivery" -- deliberately not per-shop, per that section.
class _AddressSection extends ConsumerWidget {
  const _AddressSection({required this.addressesAsync, required this.selectedId});

  final AsyncValue<List<Address>> addressesAsync;
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return addressesAsync.when(
      data: (addresses) {
        if (addresses.isEmpty) {
          return _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('No saved addresses yet.'),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => context.push('/addresses/new'),
                  child: const Text('Add an address'),
                ),
              ],
            ),
          );
        }

        // Preselect the default address so a buyer with one saved address
        // never has to tap anything here -- same "first address is always
        // default so checkout has one to preselect" rule routes/addresses.ts
        // set up in Sprint 1.
        if (selectedId == null) {
          final preferred = addresses.firstWhere((a) => a.isDefault, orElse: () => addresses.first);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(checkoutDraftProvider.notifier).setAddress(preferred.id);
          });
        }

        // RadioListTile's own groupValue/onChanged are deprecated in this
        // Flutter version -- checked against the actually-installed SDK
        // source (widgets/radio_group.dart) rather than assumed, per this
        // project's standing rule. The replacement is a RadioGroup<T>
        // ancestor managing selection for every Radio/RadioListTile beneath
        // it; each tile below only needs its own `value` now.
        return _Card(
          child: RadioGroup<String>(
            groupValue: selectedId,
            onChanged: (value) => ref.read(checkoutDraftProvider.notifier).setAddress(value!),
            child: Column(
              children: [
                for (final address in addresses)
                  RadioListTile<String>(
                    value: address.id,
                    title: Text(address.shortLine, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${address.city} ${address.pincode}', style: const TextStyle(fontSize: 12)),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => context.push('/addresses/new'),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add another address'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const _Card(child: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => const _Card(child: Text('Could not load your addresses.')),
    );
  }
}

/// §7.4 step 3. Pay-at-shop is **hidden entirely** when a Proximity rider is
/// involved, with a one-line explanation -- that section is explicit that it
/// should not be "shown-then-rejected."
class _PaymentSection extends ConsumerWidget {
  const _PaymentSection({required this.draft});

  final CheckoutDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(checkoutDraftProvider.notifier);
    // Same RadioGroup<T>-ancestor pattern the address section uses -- see
    // that section's comment for why (RadioListTile's own groupValue/
    // onChanged are deprecated in this Flutter version).
    return _Card(
      child: RadioGroup<String>(
        groupValue: draft.paymentMode,
        onChanged: (value) => notifier.setPaymentMode(value!),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RadioListTile<String>(
              value: 'online',
              title: Text('Pay online'),
              subtitle: Text('Card, UPI or wallet', style: TextStyle(fontSize: 12)),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            if (draft.payAtShopAllowed)
              const RadioListTile<String>(
                value: 'pay_at_shop',
                title: Text('Pay at shop'),
                subtitle: Text('Cash or the shop\'s own UPI, on pickup or delivery', style: TextStyle(fontSize: 12)),
                contentPadding: EdgeInsets.zero,
                dense: true,
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Pay at shop isn\'t available when a Proximity rider is delivering part of this order.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.inkSoft),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DiscountSection extends StatelessWidget {
  const _DiscountSection({
    required this.controller,
    required this.error,
    required this.applied,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController controller;
  final String? error;
  final dynamic applied;
  final VoidCallback onApply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (applied != null) {
      return _Card(
        child: Row(
          children: [
            const Icon(Icons.local_offer, size: 18, color: AppColors.brand),
            const SizedBox(width: 8),
            Expanded(child: Text('${applied.code} applied', style: const TextStyle(fontWeight: FontWeight.w600))),
            TextButton(onPressed: onClear, child: const Text('Remove')),
          ],
        ),
      );
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'Discount code', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: onApply, child: const Text('Apply')),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(error!, style: const TextStyle(color: AppColors.urgent, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

/// §7.4 step 4: "one combined total, itemized per shop-group (subtotal +
/// that group's delivery fee if any)."
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.byShop,
    required this.draft,
    required this.riderFee,
    required this.freeShipping,
    required this.subtotal,
    required this.discountAmount,
    required this.deliveryTotal,
    required this.total,
  });

  final Map<String, List<CartItem>> byShop;
  final CheckoutDraft draft;
  final int riderFee;
  final bool freeShipping;
  final int subtotal;
  final int discountAmount;
  final int deliveryTotal;
  final int total;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order summary', style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final entry in byShop.entries) ...[
            _row(
              context,
              entry.value.first.shop.name,
              formatPaise(entry.value.fold<int>(0, (sum, i) => sum + i.lineTotalPaise)),
              bold: true,
            ),
            if (draft.byShop[entry.key]?.deliveryFulfilledBy == 'platform_rider')
              _row(
                context,
                '   Rider delivery',
                freeShipping ? 'Free' : formatPaise(riderFee),
                muted: true,
              ),
          ],
          const Divider(height: 18),
          _row(context, 'Subtotal', formatPaise(subtotal)),
          if (discountAmount > 0) _row(context, 'Discount', '-${formatPaise(discountAmount)}', highlight: true),
          _row(context, 'Delivery', deliveryTotal == 0 ? 'Free' : formatPaise(deliveryTotal)),
          const Divider(height: 18),
          _row(context, 'Total', formatPaise(total), bold: true),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value, {bool bold = false, bool muted = false, bool highlight = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: highlight ? AppColors.success : (muted ? AppColors.inkSoft : AppColors.ink),
      fontSize: muted ? 12 : 14,
    );
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

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
  }
}

class _EmptyCartNotice extends StatelessWidget {
  const _EmptyCartNotice();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shopping_cart_outlined, size: 40, color: AppColors.inkSoft),
            const SizedBox(height: 12),
            Text(
              'Your cart is empty.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: () => context.go('/'), child: const Text('Browse shops')),
          ],
        ),
      ),
    );
  }
}
