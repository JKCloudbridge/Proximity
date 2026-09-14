import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Sprint 13 -- §11's "no untriaged crash-reporting gaps" exit criteria,
/// the mobile half. Checked live against the actually-installed
/// `firebase_crashlytics` 5.3.0 source before writing any of this
/// (`FirebaseCrashlytics.instance.recordError`/`recordFlutterFatalError`/
/// `setCrashlyticsCollectionEnabled` all confirmed against the real package,
/// not assumed) and against Firebase's own current Flutter setup docs for
/// the `FlutterError.onError`/`PlatformDispatcher.instance.onError` wiring
/// shape -- same third-party-API discipline every integration in this
/// project has held to since Sprint 8.
///
/// **Read this before assuming this is "just blocked on credentials," the
/// way every other integration in this project has been:** it isn't, and
/// that's a real difference worth being explicit about, not a footnote.
/// Every prior integration (Razorpay, FCM/APNs) is code-complete and only
/// needs real keys/a real project to start working. Crashlytics is
/// different -- checked directly against Firebase's own current Flutter
/// docs before assuming otherwise: basic crash reporting needs the
/// `com.google.firebase.crashlytics` Gradle plugin on Android, which
/// `flutterfire configure` adds automatically and which this project has
/// never run (needs a live `firebase login` + a real project, same blocker
/// `push_service.dart`'s own header already documents for why FCM went the
/// manual-`FirebaseOptions` route instead). Manual `FirebaseOptions` -- the
/// path that made FCM a real, complete integration without the CLI -- does
/// **not** substitute for the Gradle plugin here; there's no equivalent
/// manual path for what the plugin does (embedding build/mapping info into
/// the APK so Crashlytics can symbolicate a native crash). So: this file's
/// wiring is real and ready, `main.dart` calls it, and once real Firebase
/// config lands this starts sending Dart-side error reports -- but actually
/// receiving a *native* (non-Dart) crash with a readable stack trace still
/// needs `flutterfire configure` (or an equivalent, deliberate, one-time
/// native-build change) to run for real, on top of that. Flagged here
/// exactly this plainly so a future session doesn't treat "real Firebase
/// project exists" as the whole unblock the way it correctly would for FCM.
class CrashReportingService {
  CrashReportingService._();

  /// Called once, inside `main.dart`'s existing `try` block, immediately
  /// after `Firebase.initializeApp` succeeds -- Crashlytics needs Firebase
  /// already initialized, and that block is already the one place in this
  /// app that knows whether a real config actually loaded. Never called on
  /// the failure path (there is nothing to wire error handlers to yet).
  static void wire() {
    FlutterError.onError = (details) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      // Returning true tells the engine this error was handled -- the
      // documented Firebase-recommended shape, confirmed against their
      // current setup guide rather than assumed.
      return true;
    };
  }
}
