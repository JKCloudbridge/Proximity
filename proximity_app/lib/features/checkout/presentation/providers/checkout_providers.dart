import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateNotifier lives here in this resolved Riverpod version -- same
// reorganization auth_provider.dart's header documents (Sprint 1's bug #3);
// it's the current supported surface, not a deprecated fallback.
import 'package:flutter_riverpod/legacy.dart';

import '../../../../core/providers.dart';
import '../../data/checkout_repository.dart';
import '../../data/models/checkout_config.dart';
import '../../data/models/fulfillment_slot.dart';

final checkoutRepositoryProvider = Provider<CheckoutRepository>((ref) {
  return CheckoutRepository(dio: ref.watch(dioProvider));
});

/// The admin-controlled delivery fee + slot granularity (§4.6/§1.3). Not
/// autoDispose -- it's tiny, identical for every shop, and re-read on every
/// checkout otherwise.
final checkoutConfigProvider = FutureProvider<CheckoutConfig>((ref) {
  return ref.watch(checkoutRepositoryProvider).getConfig();
});

typedef SlotQuery = ({String shopId, String date, String type});

/// `.family`-keyed on the whole query (Dart records compare by value, so
/// each shop/date/type combination caches separately) and `.autoDispose` --
/// a slot list is only interesting while its picker is open, and it goes
/// stale quickly by nature (rpc_place_order re-checks every slot at
/// placement, migrations/032, precisely because a cached "available" can be
/// minutes old).
final slotsProvider = FutureProvider.autoDispose.family<FulfillmentSlotDay, SlotQuery>((ref, query) {
  return ref.watch(checkoutRepositoryProvider).getSlots(shopId: query.shopId, date: query.date, type: query.type);
});

/// One shop-group's choices in the checkout draft (§7.4 step 1).
class ShopFulfillmentDraft {
  const ShopFulfillmentDraft({
    this.fulfillmentType,
    this.deliveryFulfilledBy,
    this.slotStart,
    this.slotEnd,
    this.slotLabel,
  });

  final String? fulfillmentType;
  final String? deliveryFulfilledBy;
  final DateTime? slotStart;
  final DateTime? slotEnd;
  final String? slotLabel;

  bool get isDelivery => fulfillmentType == 'delivery';

  /// Mirrors exactly what rpc_place_order will and won't accept
  /// (migrations/032 step 5): a type, a slot, and -- for delivery only -- a
  /// named fulfiller.
  bool get isComplete {
    if (fulfillmentType == null || slotStart == null || slotEnd == null) return false;
    if (isDelivery && deliveryFulfilledBy == null) return false;
    return true;
  }

  ShopFulfillmentDraft copyWith({
    String? fulfillmentType,
    String? deliveryFulfilledBy,
    DateTime? slotStart,
    DateTime? slotEnd,
    String? slotLabel,
    bool clearSlot = false,
    bool clearFulfilledBy = false,
  }) {
    return ShopFulfillmentDraft(
      fulfillmentType: fulfillmentType ?? this.fulfillmentType,
      deliveryFulfilledBy: clearFulfilledBy ? null : (deliveryFulfilledBy ?? this.deliveryFulfilledBy),
      slotStart: clearSlot ? null : (slotStart ?? this.slotStart),
      slotEnd: clearSlot ? null : (slotEnd ?? this.slotEnd),
      slotLabel: clearSlot ? null : (slotLabel ?? this.slotLabel),
    );
  }
}

/// The whole in-progress checkout (§7.4 steps 1-3). Deliberately a
/// StateNotifier rather than the StateProviders every prior sprint got away
/// with: this is the first screen in the app with real multi-field state
/// that has to stay internally consistent (picking a rider delivery has to
/// be able to force the payment mode off pay-at-shop, §1.4) -- which is
/// exactly the invariant a bag of independent StateProviders would lose.
class CheckoutDraft {
  const CheckoutDraft({
    this.byShop = const {},
    this.addressId,
    this.paymentMode = 'online',
    this.discountCode,
    this.discount,
  });

  final Map<String, ShopFulfillmentDraft> byShop;
  final String? addressId;
  final String paymentMode;
  final String? discountCode;
  final DiscountPreview? discount;

  /// §1.4, restated in §7.4 step 3: pay-at-shop is only on the table when no
  /// Proximity rider is involved anywhere in the checkout. The UI hides the
  /// option entirely when this is false ("rather than shown-then-rejected"),
  /// and rpc_place_order refuses it outright regardless (PAY_AT_SHOP_NOT_ALLOWED).
  bool get payAtShopAllowed => !byShop.values.any((d) => d.deliveryFulfilledBy == 'platform_rider');

  bool get anyDelivery => byShop.values.any((d) => d.isDelivery);

  bool get allShopsComplete => byShop.isNotEmpty && byShop.values.every((d) => d.isComplete);

  /// Everything rpc_place_order needs before it's worth calling at all.
  bool get isReady => allShopsComplete && (!anyDelivery || addressId != null);

  CheckoutDraft copyWith({
    Map<String, ShopFulfillmentDraft>? byShop,
    String? addressId,
    String? paymentMode,
    String? discountCode,
    DiscountPreview? discount,
    bool clearDiscount = false,
  }) {
    return CheckoutDraft(
      byShop: byShop ?? this.byShop,
      addressId: addressId ?? this.addressId,
      paymentMode: paymentMode ?? this.paymentMode,
      discountCode: clearDiscount ? null : (discountCode ?? this.discountCode),
      discount: clearDiscount ? null : (discount ?? this.discount),
    );
  }
}

class CheckoutDraftNotifier extends StateNotifier<CheckoutDraft> {
  CheckoutDraftNotifier() : super(const CheckoutDraft());

  /// Keeps the draft's shop set in step with the cart's. Called whenever the
  /// cart loads or changes -- a shop removed from the cart mid-checkout must
  /// not leave a stale group behind, because rpc_place_order rejects any
  /// fulfillment array that doesn't match the cart exactly
  /// (SHOP_GROUP_MISMATCH, migrations/032 step 2).
  void syncShops(List<String> shopIds) {
    final next = <String, ShopFulfillmentDraft>{};
    var changed = shopIds.length != state.byShop.length;
    for (final id in shopIds) {
      final existing = state.byShop[id];
      if (existing == null) changed = true;
      next[id] = existing ?? const ShopFulfillmentDraft();
    }
    if (changed) state = state.copyWith(byShop: next);
  }

  void setFulfillmentType(String shopId, String type, {String? deliveryFulfilledBy}) {
    final current = state.byShop[shopId] ?? const ShopFulfillmentDraft();
    // Switching type invalidates the slot: a pickup slot and a delivery slot
    // are generated from the same grid but validated against a different
    // question, and silently carrying one over would be a guess.
    final next = ShopFulfillmentDraft(
      fulfillmentType: type,
      deliveryFulfilledBy: type == 'delivery' ? deliveryFulfilledBy : null,
      slotStart: current.fulfillmentType == type ? current.slotStart : null,
      slotEnd: current.fulfillmentType == type ? current.slotEnd : null,
      slotLabel: current.fulfillmentType == type ? current.slotLabel : null,
    );
    _put(shopId, next);
  }

  void setDeliveryFulfilledBy(String shopId, String fulfilledBy) {
    final current = state.byShop[shopId] ?? const ShopFulfillmentDraft();
    _put(shopId, current.copyWith(deliveryFulfilledBy: fulfilledBy));
  }

  void setSlot(String shopId, FulfillmentSlot slot) {
    final current = state.byShop[shopId] ?? const ShopFulfillmentDraft();
    _put(shopId, current.copyWith(slotStart: slot.slotStart, slotEnd: slot.slotEnd, slotLabel: slot.label));
  }

  void _put(String shopId, ShopFulfillmentDraft draft) {
    final next = Map<String, ShopFulfillmentDraft>.from(state.byShop)..[shopId] = draft;
    var paymentMode = state.paymentMode;
    // Consistency, not politeness: if the new choice brought a rider into
    // the checkout, pay-at-shop stops being legal (§1.4) and the draft
    // corrects itself rather than waiting to be rejected at placement.
    final ridersInvolved = next.values.any((d) => d.deliveryFulfilledBy == 'platform_rider');
    if (ridersInvolved && paymentMode == 'pay_at_shop') paymentMode = 'online';
    state = state.copyWith(byShop: next, paymentMode: paymentMode);
  }

  void setAddress(String addressId) => state = state.copyWith(addressId: addressId);

  void setPaymentMode(String mode) {
    if (mode == 'pay_at_shop' && !state.payAtShopAllowed) return;
    state = state.copyWith(paymentMode: mode);
  }

  void applyDiscount(String code, DiscountPreview preview) =>
      state = state.copyWith(discountCode: code, discount: preview);

  void clearDiscount() => state = state.copyWith(clearDiscount: true);

  /// Called after a successful placement -- the cart is empty server-side at
  /// that point (rpc_place_order clears it), so keeping the old selections
  /// around would only mislead the next checkout.
  void reset() => state = const CheckoutDraft();
}

final checkoutDraftProvider = StateNotifierProvider<CheckoutDraftNotifier, CheckoutDraft>((ref) {
  return CheckoutDraftNotifier();
});
