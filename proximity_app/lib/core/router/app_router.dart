import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/presentation/account_screen.dart';
import '../../features/addresses/presentation/screens/address_form_screen.dart';
import '../../features/addresses/presentation/screens/address_list_screen.dart';
import '../../features/auth/presentation/auth_provider.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/cart/presentation/screens/cart_screen.dart';
import '../../features/checkout/presentation/screens/checkout_screen.dart';
import '../../features/checkout/presentation/screens/order_confirmation_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/checkout/presentation/screens/order_history_screen.dart';
import '../../features/order_again/presentation/screens/order_again_screen.dart';
import '../../features/product_detail/presentation/screens/product_detail_screen.dart';
import '../../features/rider/presentation/screens/rider_onboarding_screen.dart';
import '../../features/shop_detail/presentation/screens/shop_detail_screen.dart';
import '../../features/shop_orders/presentation/screens/shop_orders_screen.dart';
import '../../features/wishlist/presentation/screens/wishlist_screen.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/placeholder_screen.dart';

/// Guests can browse (same rule as Baker Ally: login is gated at specific
/// actions, not at the door). Sprint 2 adds /account and /rider/onboarding
/// alongside Sprint 1's /addresses; Sprint 5 adds /wishlist (own-user data,
/// §5.2 -- routes/wishlist.ts requires a signed-in buyer for every call) --
/// /shop/:id and /product/:id are deliberately NOT here, guests browse the
/// full Home -> shop -> product path per §11's exit criteria, same as Home
/// itself. /cart is ALSO deliberately not here despite being own-user data
/// too (§5.2) -- unlike /wishlist (a pushed route), /cart is a bottom-nav
/// tab baked into the StatefulShellRoute below, always one tap away; gating
/// it here would mean redirecting straight out of the shell the moment a
/// guest taps "Cart," a worse UX than CartScreen's own sign-in prompt (same
/// "gated at the specific action, not at the door" rule WishlistHeartButton
/// already follows). Extend this list as each later sprint adds a *pushed*
/// route that needs a signed-in user (checkout in Sprint 7, orders later).
/// Sprint 9 adds `/orders` (My Orders, own-user data) and `/shop-orders`
/// (shop-team data -- a guest or non-team buyer just sees "you're not part
/// of any shop's team yet" from the screen itself once signed in, same as
/// every other shop-scoped surface in this app).
const _protectedPaths = <String>[
  '/addresses',
  '/account',
  '/rider',
  '/wishlist',
  '/checkout',
  '/order-groups',
  '/orders',
  '/shop-orders',
];

final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = ref.watch(authProvider.notifier);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: _GoRouterRefreshStream(authNotifier.stream),
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      if (auth.isLoading) return null;

      final goingToLogin = state.uri.path == '/login';
      final needsAuth = _protectedPaths.any(state.uri.path.startsWith);

      if (!auth.isLoggedIn && needsAuth) return '/login?redirect=${state.uri.path}';
      if (auth.isLoggedIn && goingToLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/addresses', builder: (context, state) => const AddressListScreen()),
      GoRoute(path: '/addresses/new', builder: (context, state) => const AddressFormScreen()),
      GoRoute(path: '/account', builder: (context, state) => const AccountScreen()),
      GoRoute(path: '/rider/onboarding', builder: (context, state) => const RiderOnboardingScreen()),
      GoRoute(path: '/wishlist', builder: (context, state) => const WishlistScreen()),
      // Sprint 7 (§7.4). Both are pushed routes rather than shell tabs, and
      // both are own-user data, so unlike /cart they genuinely do belong in
      // `_protectedPaths` above -- a guest can never reach either one with a
      // cart to check out in the first place.
      GoRoute(path: '/checkout', builder: (context, state) => const CheckoutScreen()),
      GoRoute(
        path: '/order-groups/:id',
        builder: (context, state) => OrderConfirmationScreen(orderGroupId: state.pathParameters['id']!),
      ),
      // Sprint 9 built this as the "reachable later too" entry point
      // live-tracking needed (see routes/shopOrders.ts's own header for the
      // shop side); Sprint 10 upgraded the screen it points to from the
      // minimal MyOrdersScreen into the real OrderHistoryScreen (GET
      // /v1/order-groups' own header explains why in place, not a new route).
      GoRoute(path: '/orders', builder: (context, state) => const OrderHistoryScreen()),
      GoRoute(path: '/shop-orders', builder: (context, state) => const ShopOrdersScreen()),
      GoRoute(path: '/shop/:id', builder: (context, state) => ShopDetailScreen(shopId: state.pathParameters['id']!)),
      GoRoute(path: '/product/:id', builder: (context, state) => ProductDetailScreen(productId: state.pathParameters['id']!)),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (c, s) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/categories', builder: (c, s) => const PlaceholderScreen(title: 'Categories'))]),
          StatefulShellBranch(routes: [GoRoute(path: '/cart', builder: (c, s) => const CartScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/order-again', builder: (c, s) => const OrderAgainScreen())]),
        ],
      ),
    ],
  );
});

/// Bridges the auth StateNotifier's change stream into the ChangeNotifier
/// GoRouter expects, so protected routes re-evaluate immediately on
/// login/logout -- identical to Baker Ally's app_router.dart.
class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
