import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/crash/crash_reporting_service.dart';
import 'core/push/push_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/push/presentation/providers/push_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);

  // Must complete before anything reads GoogleSignIn.instance (see
  // auth_repository.dart/auth_provider.dart's googleSignInProvider comment)
  // -- google_sign_in v7's own docs are explicit that calling any other
  // method before this future resolves is undefined behavior.
  await GoogleSignIn.instance.initialize(serverClientId: Env.googleServerClientId);

  // Sprint 11 -- Firebase push. Wrapped defensively, same reason every
  // FIREBASE_* field in .env.example's header gives: no real Firebase
  // project exists for this app yet (checked directly, not assumed), so
  // `Firebase.initializeApp` is expected to throw on every field being an
  // empty string -- logged, never fatal. A missing/invalid Firebase config
  // must not be able to crash app startup; once real config lands, this
  // starts succeeding with no code change here at all.
  try {
    await Firebase.initializeApp(options: PushService.optionsForCurrentPlatform());
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    // Sprint 13 -- wired only once Firebase has actually initialized (it
    // needs that to exist first); see crash_reporting_service.dart's own
    // header for the real, disclosed gap this alone does NOT close (the
    // native Gradle plugin `flutterfire configure` normally adds).
    CrashReportingService.wire();
  } catch (err) {
    debugPrint('Firebase init skipped: $err');
  }

  runApp(const ProviderScope(child: ProximityApp()));
}

class ProximityApp extends ConsumerWidget {
  const ProximityApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // First read of pushServiceProvider in the app's lifetime -- this is
    // what actually triggers PushService.wireNotificationTapHandling() (see
    // that provider's own header). Deliberately NOT awaited/used beyond
    // this -- AuthNotifier reads the same provider instance later for the
    // sign-in/sign-out hooks (push_providers.dart's whole point is one
    // shared instance).
    ref.watch(pushServiceProvider);

    return MaterialApp.router(
      title: 'Proximity',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
