import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../data/models/my_shop.dart';
import '../../data/models/shop_order.dart';
import '../../data/shop_orders_repository.dart';

final shopOrdersRepositoryProvider = Provider<ShopOrdersRepository>((ref) {
  return ShopOrdersRepository(dio: ref.watch(dioProvider));
});

/// Backs account_screen.dart's "Shop Orders" tile visibility and
/// ShopOrdersScreen's own shop picker. Not `.autoDispose` -- shop
/// membership essentially never changes mid-session, and re-checking it on
/// every AccountScreen visit is wasted the way it wasn't for
/// myRiderProfileProvider (which genuinely can change, e.g. right after
/// submitting an application).
final myShopsProvider = FutureProvider<List<MyShop>>((ref) {
  return ref.watch(shopOrdersRepositoryProvider).getMyShops();
});

final shopOrdersProvider = FutureProvider.autoDispose.family<List<ShopOrder>, String>((ref, shopId) {
  return ref.watch(shopOrdersRepositoryProvider).getOrders(shopId);
});
