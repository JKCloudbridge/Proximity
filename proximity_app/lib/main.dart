import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);

  // Must complete before anything reads GoogleSignIn.instance (see
  // auth_repository.dart/auth_provider.dart's googleSignInProvider comment)
  // -- google_sign_in v7's own docs are explicit that calling any other
  // method before this future resolves is undefined behavior.
  await GoogleSignIn.instance.initialize(serverClientId: Env.googleServerClientId);

  runApp(const ProviderScope(child: ProximityApp()));
}

class ProximityApp extends ConsumerWidget {
  const ProximityApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Proximity',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
