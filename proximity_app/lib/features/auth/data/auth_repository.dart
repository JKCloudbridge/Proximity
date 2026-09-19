import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/platform/platform_info.dart';
import '../../../core/storage/secure_storage.dart';

/// The only place in the app allowed to touch supabase_flutter directly --
/// auth only, same hard rule as Baker Ally's AuthRepository. Everything else
/// goes through Dio -> proximity_backend.
///
/// Deliberate deviation from Baker Ally's Google flow, worth being explicit
/// about since it's not a blind copy: Baker Ally used
/// `supabase.auth.signInWithOAuth(OAuthProvider.google, redirectTo: ...)`,
/// which hands off to a browser tab. That's fine when Google is the only
/// non-OTP option, but Apple's App Store Review Guideline 4.8 requires Sign
/// in with Apple to be offered wherever another social login is, and a
/// browser hop for Apple specifically would look and feel worse than the
/// native Face ID/Touch ID sheet users actually expect from Apple's own
/// button -- inconsistent quality between the two options on iOS is exactly
/// what 4.8 review tends to flag. So both providers here use their native
/// SDK (google_sign_in v7's authenticate()/authenticationEvents,
/// sign_in_with_apple's getAppleIDCredential()) and hand the resulting ID
/// token to Supabase's signInWithIdToken -- one consistent native-feeling
/// flow on both platforms instead of Google-native-but-Apple-browser.
class AuthRepository {
  AuthRepository({
    required SupabaseClient supabase,
    required SecureStorage secureStorage,
    required Dio dio,
    required GoogleSignIn googleSignIn,
  })  : _supabase = supabase,
        _secureStorage = secureStorage,
        _dio = dio,
        _googleSignIn = googleSignIn;

  final SupabaseClient _supabase;
  final SecureStorage _secureStorage;
  final Dio _dio;
  final GoogleSignIn _googleSignIn;

  Stream<void> get onAuthStateChange => _supabase.auth.onAuthStateChange.map((_) {});

  Session? get currentSession => _supabase.auth.currentSession;

  /// Sprint 14: sign-up is email+password, confirmed by a 6-digit OTP code
  /// (Supabase's "Confirm signup" email/OTP template) -- `signUp` creates
  /// the `auth.users` row but does **not** sign the caller in; the account
  /// stays unconfirmed until [verifySignupOtp] succeeds. Replaces the old
  /// passwordless "email OTP is how you sign in every time" flow (Baker
  /// Ally's own no-Google-consent-screen fallback) now that password
  /// sign-in below covers that no-setup-required role instead.
  /// [fullName]/[phone] are optional profile fields captured on the sign-up
  /// form -- they travel as `signUp`'s `data` map (arbitrary user metadata,
  /// landing in `auth.users.raw_user_meta_data`), the same mechanism
  /// proximity_web's own signup page already uses for `full_name`. Kept
  /// distinct from `signUp`'s own `phone` parameter, which is GoTrue's
  /// phone-based-OTP-auth field -- a different auth mechanism this app
  /// doesn't use, not a place to stash a profile phone number. Read back out
  /// of `user_metadata` by `POST /v1/auth/me` (routes/auth.ts) the one time
  /// it creates the `public.users` row.
  Future<void> signUpWithPassword({required String email, required String password, String? fullName, String? phone}) {
    return _supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      },
    );
  }

  /// Confirms the account [signUpWithPassword] created and, on success,
  /// signs the user in -- same as Supabase's own documented signup-OTP
  /// contract.
  Future<void> verifySignupOtp({required String email, required String token}) {
    return _supabase.auth.verifyOTP(email: email, token: token, type: OtpType.signup);
  }

  /// Sprint 14: returning users sign in with the password they set at
  /// sign-up -- no email round trip needed once an account is confirmed.
  Future<void> signInWithPassword({required String email, required String password}) {
    return _supabase.auth.signInWithPassword(email: email, password: password);
  }

  /// Forgot-password flow, step 1 of 3: triggers Supabase's password-
  /// recovery email (Dashboard's "Reset Password" template -- needs the
  /// same `{{ .Token }}` edit the old Magic Link template needed, see
  /// Sprint 14.md) carrying a 6-digit OTP.
  Future<void> sendPasswordResetOtp(String email) {
    return _supabase.auth.resetPasswordForEmail(email);
  }

  /// Step 2 of 3: verifying a recovery-type OTP signs the caller into a
  /// real session -- Supabase's documented prerequisite for [updatePassword]
  /// below to actually take effect on `auth.users`.
  Future<void> verifyPasswordResetOtp({required String email, required String token}) {
    return _supabase.auth.verifyOTP(email: email, token: token, type: OtpType.recovery);
  }

  /// Step 3 of 3: sets the new password on the session [verifyPasswordResetOtp]
  /// just created. Deliberately leaves the user signed in afterward -- same
  /// "stay signed in until a manual sign-out" contract every other sign-in
  /// path in this app keeps, not a special case that force-logs-out after a
  /// reset.
  Future<void> updatePassword(String newPassword) {
    return _supabase.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// GoogleSignIn.instance.initialize() must have already completed
  /// (called once, in main()) before this is ever invoked -- see
  /// main.dart. Requires GOOGLE_SERVER_CLIENT_ID to be a *Web* OAuth client
  /// id, not Android/iOS -- see .env.example's comment on why.
  Future<void> signInWithGoogle() async {
    final GoogleSignInAccount account = await _googleSignIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('Google sign-in did not return an ID token');
    }
    await _supabase.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken);
  }

  /// Native Face ID/Touch ID sheet on iOS. fullName/email scopes are only
  /// ever returned on the user's *first* authorization for this app
  /// (Apple's own limitation, not this package's) -- if profile
  /// fullName/email need to survive a later re-auth, capture them from this
  /// first call and persist server-side rather than expecting Apple to
  /// resend them.
  ///
  /// Android has no native OS-level Apple auth -- sign_in_with_apple falls
  /// back to a Chrome Custom Tab web flow there, which requires
  /// webAuthenticationOptions (a Services ID + redirect URI from Apple
  /// Developer, both env-configured, neither set up yet -- see
  /// .env.example). Until then this throws on Android specifically, which
  /// is expected: iOS is where Apple Sign-In actually matters for App
  /// Store review (Guideline 4.8), and that path needs no extra config at
  /// all. Passing webAuthenticationOptions on iOS would be wrong (it would
  /// force the web flow instead of the native sheet), hence the platform
  /// branch rather than always passing it.
  Future<void> signInWithApple() async {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      webAuthenticationOptions: PlatformInfo.isIOS
          ? null
          : WebAuthenticationOptions(
              clientId: Env.appleServiceId,
              redirectUri: Uri.parse(Env.appleRedirectUri),
            ),
    );
    final idToken = credential.identityToken;
    if (idToken == null) {
      throw const AuthException('Apple sign-in did not return an identity token');
    }
    await _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      accessToken: credential.authorizationCode,
    );
  }

  /// Mirrors the current session's access token into secure storage so
  /// Dio's interceptor always reads from one consistent place. Call after
  /// every auth state change, including token refresh.
  Future<void> syncSessionToStorage() async {
    final session = _supabase.auth.currentSession;
    if (session != null) {
      await _secureStorage.writeJwt(session.accessToken);
    } else {
      await _secureStorage.clearJwt();
    }
  }

  /// Signup-hook replacement (proximity_backend/.../routes/auth.ts):
  /// idempotently creates the public.users row with the default 'buyer'
  /// role on first call, returns {user, role} either way.
  Future<Map<String, dynamic>> hydrateProfile() async {
    final response = await _dio.post<Map<String, dynamic>>('/v1/auth/me');
    return response.data!['data'] as Map<String, dynamic>;
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
    await _secureStorage.clearJwt();
  }
}
