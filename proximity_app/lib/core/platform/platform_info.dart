import 'package:flutter/foundation.dart';

/// The one place in this app allowed to branch on platform --
/// SPRINT_PLANNING.md §1.1: "never branch on Platform.isAndroid/isIOS
/// scattered through feature code... centralize the handful of places that
/// genuinely need it." Uses `defaultTargetPlatform` from
/// flutter/foundation rather than `dart:io`'s `Platform` class
/// specifically because `dart:io` doesn't compile on web at all -- this
/// project doesn't target web today, but there's no reason to plant a
/// web-incompatible import as the one central platform check when the
/// zero-cost alternative exists.
///
/// First real consumer: auth_repository.dart's Apple sign-in, which needs
/// `webAuthenticationOptions` on Android (no native Apple auth there --
/// it's a Chrome Custom Tab web flow) and must NOT pass it on iOS (native
/// Face ID/Touch ID sheet; passing web options there would be wrong).
class PlatformInfo {
  PlatformInfo._();

  static bool get isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  static bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;
}
