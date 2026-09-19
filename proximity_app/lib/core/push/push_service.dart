import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../platform/platform_info.dart';
import '../router/app_router.dart';
import '../../features/push/data/push_repository.dart';
import '../../features/push/presentation/providers/push_providers.dart';

/// Sprint 11 -- real FCM/APNs push, both platforms through one
/// `FirebaseOptions`-based manual init (this file's own pubspec.yaml
/// comment has the full "why manual, not the FlutterFire CLI" reasoning).
/// Checked live against the actually-installed firebase_core 4.14.0/
/// firebase_messaging 16.6.0 source before writing any of this, per this
/// project's standing third-party-API rule -- `Firebase.initializeApp`'s
/// `options` parameter, `FirebaseMessaging.instance.requestPermission()`/
/// `.getToken()`/`.onTokenRefresh`, the static `onMessage`/
/// `onMessageOpenedApp` getters, and `onBackgroundMessage`'s top-level-
/// function requirement were all confirmed against the real package
/// source, not assumed from training data (the exact kind of version-drift
/// risk SPRINT_PLANNING.md's standing rules flag explicitly for any new
/// third-party API this project touches).
///
/// **Deliberately kept out of `PlatformInfo`'s own file** -- that class
/// (§1.1's one centralized platform-branch point) is for *behavioral*
/// branches (which sign-in flow to use); picking which Firebase `appId` to
/// load is config selection, not behavior, and lives here, next to the rest
/// of this feature's own Firebase-specific code -- `PlatformInfo.isIOS` is
/// still the thing doing the actual platform check, not a second ad hoc one.
class PushService {
  PushService(this._ref);

  final Ref _ref;

  /// Builds this platform's `FirebaseOptions` from `.env` (Env, envied) --
  /// every field is empty today (no real Firebase project exists, checked
  /// directly per Sprint 11.md), so `Firebase.initializeApp` is expected to
  /// throw until real values land. That's handled by the caller (main.dart),
  /// never here.
  static FirebaseOptions optionsForCurrentPlatform() {
    return FirebaseOptions(
      apiKey: Env.firebaseApiKey,
      appId: PlatformInfo.isIOS ? Env.firebaseAppIdIos : Env.firebaseAppIdAndroid,
      messagingSenderId: Env.firebaseMessagingSenderId,
      projectId: Env.firebaseProjectId,
    );
  }

  bool _tapHandlingWired = false;
  bool _tokenRefreshWired = false;

  /// Requests notification permission and, if granted, registers this
  /// device's current FCM token with the backend (`POST /v1/push/token`).
  /// Called from AuthNotifier once a sign-in actually completes (push_
  /// service.dart has no opinion on auth state itself) -- a token is only
  /// useful once there's a signed-in user id to attach it to server-side
  /// (`users.fcm_token`, migrations/001).
  ///
  /// Best-effort end to end, same contract every push-related call in this
  /// project keeps (lib/push/index.ts's own header, backend side, states
  /// the identical rule): never throws into the caller. A denied
  /// permission, a missing Firebase config, or a network failure all just
  /// mean "this device won't get pushes yet," not a sign-in failure.
  Future<void> registerCurrentDevice() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      final granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!granted) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _repository.registerToken(token);

      if (!_tokenRefreshWired) {
        _tokenRefreshWired = true;
        // Firebase can rotate a device's token at any time (this file's
        // own header on why users.fcm_token is last-write-wins) -- this
        // listener is set up once per app run, not re-subscribed on every
        // sign-in, since a refresh can legitimately fire while already
        // signed in.
        FirebaseMessaging.instance.onTokenRefresh.listen((refreshed) {
          _repository.registerToken(refreshed).catchError((_) {});
        });
      }
    } catch (err) {
      debugPrint('PushService.registerCurrentDevice skipped: $err');
    }
  }

  /// Called from AuthNotifier.signOut(), before the Supabase session itself
  /// is torn down (the DELETE call needs a valid bearer token to reach
  /// authMiddleware) -- a device signed out of this account shouldn't keep
  /// receiving its pushes.
  Future<void> unregisterCurrentDevice() async {
    try {
      await _repository.unregisterToken();
    } catch (err) {
      debugPrint('PushService.unregisterCurrentDevice skipped: $err');
    }
  }

  /// Wires a tapped notification (app was backgrounded/foregrounded, or
  /// cold-started from a terminated state) to a real in-app navigation --
  /// §11's own exit criteria ("deep-links into a pre-filled cart"). Reads
  /// `message.data['route']` (set server-side by routes/internal.ts and
  /// lib/riderAssignment.ts -- `/cart` for a recurring-list reminder, `/rider`
  /// for a rider-assignment ping) and pushes it through the app's own
  /// GoRouter -- no native URL-scheme/intent-filter registration needed at
  /// all for this (checked: this app has no custom scheme registered in
  /// AndroidManifest.xml/Info.plist today, and doesn't need one -- a
  /// notification tap reaches Dart code directly via this API, it was
  /// never actually a deep-link-by-URI problem).
  ///
  /// Called once per app run (`_tapHandlingWired` guards against a second
  /// call re-subscribing `onMessageOpenedApp` if something ever reads
  /// pushServiceProvider more than once) -- see push_providers.dart for
  /// where that single call happens.
  ///
  /// Sprint 13 fix: called from `pushServiceProvider`'s own constructor
  /// (push_providers.dart), which `authProvider` watches -- so an unguarded
  /// throw here (e.g. `FirebaseMessaging.instance` itself throws
  /// `[core/no-app]` when `Firebase.initializeApp()` never succeeded, same
  /// "no real Firebase config yet" case every other method in this file
  /// already tolerates) poisons `authProvider`'s provider state and crashes
  /// the entire auth-dependent UI at startup, not just this feature. Never
  /// caught until this sprint's first real run against a device with blank
  /// Firebase credentials.
  void wireNotificationTapHandling() {
    if (_tapHandlingWired) return;
    _tapHandlingWired = true;

    try {
      FirebaseMessaging.instance.getInitialMessage().then(_handleTap);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    } catch (err) {
      debugPrint('PushService.wireNotificationTapHandling skipped: $err');
    }
  }

  void _handleTap(RemoteMessage? message) {
    final route = message?.data['route'];
    if (route is String && route.isNotEmpty) {
      _ref.read(routerProvider).go(route);
    }
  }

  PushRepository get _repository => _ref.read(pushRepositoryProvider);
}

/// Top-level, `@pragma('vm:entry-point')`-annotated per FlutterFire's own
/// documented requirement (release-mode tree-shaking would otherwise strip
/// it, since nothing in the main isolate appears to call it directly --
/// `FirebaseMessaging.onBackgroundMessage` registers it with the platform
/// side instead). Runs in a separate background isolate with no access to
/// the main isolate's state (no Riverpod `Ref`, no existing `Firebase`
/// instance) -- re-initializing Firebase here is required, not redundant.
///
/// Deliberately does nothing beyond that re-init: every push this project
/// sends carries a `notification` payload (lib/push/fcm.ts), which the OS
/// itself renders in the system tray while backgrounded/terminated with no
/// app code involved at all -- this handler exists only to satisfy
/// firebase_messaging's own registration requirement for data processing,
/// not because this project has background data-processing work to do on
/// an otherwise-killed app. If a future sprint needs that (e.g. silently
/// updating local state before the user even opens the app), it's this
/// function's job to grow, not a new one.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(options: PushService.optionsForCurrentPlatform());
  } catch (_) {
    // Same "no real Firebase config yet" tolerance as every other call site
    // in this file -- a background isolate crashing on init would be worse
    // than silently doing nothing.
  }
}
