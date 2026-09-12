import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/presentation/account_screen.dart';
import '../../features/addresses/presentation/screens/address_form_screen.dart';
import '../../features/addresses/presentation/screens/address_list_screen.dart';
import '../../features/auth/presentation/auth_provider.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/rider/presentation/screens/rider_onboarding_screen.dart';
import '../../shared/widgets/app_shell.dart';
import '../../shared/widgets/placeholder_screen.dart';

/// Guests can browse (same rule as Baker Ally: login is gated at specific
/// actions, not at the door). Sprint 2 adds /account and /rider/onboarding
/// alongside Sprint 1's /addresses -- extend this list as each later sprint
/// adds a route that actually needs a signed-in user (cart/checkout in
/// Sprint 6/7, wishlist/orders in later sprints).
const _protectedPaths = <String>['/addresses', '/account', '/rider'];

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
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (c, s) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/categories', builder: (c, s) => const PlaceholderScreen(title: 'Categories'))]),
          StatefulShellBranch(routes: [GoRoute(path: '/cart', builder: (c, s) => const PlaceholderScreen(title: 'Cart'))]),
          StatefulShellBranch(routes: [GoRoute(path: '/order-again', builder: (c, s) => const PlaceholderScreen(title: 'Order Again'))]),
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
