import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateNotifier/StateNotifierProvider moved to this explicit import in
// Riverpod 3.x -- the plain Notifier/NotifierProvider in the main package
// are for riverpod_generator's @riverpod codegen, not hand-writing (their
// own source marks them "@publicInCodegen ... not meant for public
// consumption"). This project isn't using the code-gen workflow (dropped
// riverpod_generator in Sprint 1 over a real version conflict with
// envied_generator -- see Sprint 1.md), so this is the correct, still
// fully-supported surface for a hand-written notifier, not a deprecated
// fallback.
import 'package:flutter_riverpod/legacy.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/providers.dart';
import '../../../core/push/push_service.dart';
import '../../push/presentation/providers/push_providers.dart';
import '../data/auth_repository.dart';

/// GoogleSignIn is a process-wide singleton (GoogleSignIn.instance) --
/// exposed as a provider anyway, rather than referenced as a bare global,
/// so tests can override it and so every consumer goes through Riverpod
/// consistently. `initialize()` is called once in main.dart before this is
/// ever read; see main.dart's comment on why that ordering matters.
final googleSignInProvider = Provider<GoogleSignIn>((ref) => GoogleSignIn.instance);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    supabase: ref.watch(supabaseClientProvider),
    secureStorage: ref.watch(secureStorageProvider),
    dio: ref.watch(dioProvider),
    googleSignIn: ref.watch(googleSignInProvider),
  );
});

/// Root auth state -- same shape and role as Baker Ally's AuthSessionState.
/// `isLoading` covers both "checking for a restored session on cold start"
/// and "sign-in in flight".
class AuthSessionState {
  const AuthSessionState({this.isLoggedIn = false, this.userId, this.role, this.isLoading = true});

  final bool isLoggedIn;
  final String? userId;
  final String? role;
  final bool isLoading;

  AuthSessionState copyWith({bool? isLoggedIn, String? userId, String? role, bool? isLoading}) {
    return AuthSessionState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthSessionState> {
  AuthNotifier(this._repository, this._pushService) : super(const AuthSessionState()) {
    _subscription = _repository.onAuthStateChange.listen((_) => _sync());
    _sync();
  }

  final AuthRepository _repository;
  final PushService _pushService;
  late final StreamSubscription<void> _subscription;
  bool _wasLoggedIn = false;

  Future<void> _sync() async {
    // Sprint 14 fix: this call was the one thing in this function with no
    // try/catch, unlike hydrateProfile() below (deliberately tolerant --
    // "a dropped connection shouldn't force a logout"). flutter_secure_
    // storage has real, documented PlatformExceptions on some Android
    // Keystore configurations -- if that write throws, it used to escape
    // this function uncaught (called from a raw stream listener with
    // nothing catching it), which meant `state` never updated to
    // isLoggedIn: true and `isLoading` stayed stuck at its default `true`
    // forever -- app_router.dart's redirect refuses to act at all while
    // isLoading is true, so a real, successful Supabase sign-in would
    // silently never take the user anywhere. Never caught until this
    // sprint's first real sign-in on a physical device.
    try {
      await _repository.syncSessionToStorage();
    } catch (err) {
      debugPrint('AuthNotifier._sync: syncSessionToStorage failed: $err');
    }
    final session = _repository.currentSession;

    if (session == null) {
      state = const AuthSessionState(isLoading: false);
      _wasLoggedIn = false;
      return;
    }

    state = state.copyWith(isLoggedIn: true, userId: session.user.id, isLoading: true);

    // Sprint 11 -- register this device's push token once a sign-in
    // actually lands (not re-fired on every `_sync()` call, e.g. a token
    // refresh from Supabase itself -- only on the false->true transition).
    // Fire-and-forget: PushService's own contract is "never throw," and
    // auth state resolution must not wait on a notification-permission
    // prompt. Deliberately fired regardless of `role` -- a rider is a
    // `users` row too, and §11's own rider-assignment-push decision needs
    // exactly this same registration path, not a second one.
    if (!_wasLoggedIn) {
      unawaited(_pushService.registerCurrentDevice());
    }
    _wasLoggedIn = true;

    try {
      final profile = await _repository.hydrateProfile();
      state = state.copyWith(role: profile['role'] as String?, isLoading: false);
    } catch (_) {
      // Backend unreachable -- still signed in against Supabase; role stays
      // unresolved until the next successful sync. Same tolerant handling
      // as Baker Ally -- a dropped connection shouldn't force a logout.
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> signUpWithPassword({required String email, required String password, String? fullName, String? phone}) =>
      _repository.signUpWithPassword(email: email, password: password, fullName: fullName, phone: phone);

  Future<void> verifySignupOtp({required String email, required String token}) =>
      _repository.verifySignupOtp(email: email, token: token);

  Future<void> signInWithPassword({required String email, required String password}) =>
      _repository.signInWithPassword(email: email, password: password);

  Future<void> sendPasswordResetOtp(String email) => _repository.sendPasswordResetOtp(email);

  Future<void> verifyPasswordResetOtp({required String email, required String token}) =>
      _repository.verifyPasswordResetOtp(email: email, token: token);

  Future<void> updatePassword(String newPassword) => _repository.updatePassword(newPassword);

  Future<void> signInWithGoogle() => _repository.signInWithGoogle();

  Future<void> signInWithApple() => _repository.signInWithApple();

  Future<void> signOut() async {
    // Before the session itself is torn down -- the DELETE call needs a
    // still-valid bearer token to reach authMiddleware (PushService's own
    // header explains this ordering).
    await _pushService.unregisterCurrentDevice();
    await _repository.signOut();
    state = const AuthSessionState(isLoading: false);
    _wasLoggedIn = false;
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthSessionState>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider), ref.watch(pushServiceProvider));
});
