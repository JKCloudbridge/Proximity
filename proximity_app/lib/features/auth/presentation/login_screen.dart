import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/theme/app_theme.dart';
import 'auth_provider.dart';
import 'email_otp_screen.dart';

/// Email OTP + Google + Apple, all three visible together -- OTP is the
/// no-setup fallback (auth_repository.dart's comment on why), not hidden
/// behind a "more options" link, since Google/Apple credentials won't be
/// live-testable until the accounts referenced in
/// SPRINT_PLANNING.md §3.2 exist.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  bool _sendingOtp = false;
  bool _signingInWithProvider = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    setState(() {
      _sendingOtp = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).sendEmailOtp(email);
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EmailOtpScreen(email: email)),
        );
      }
    } catch (e) {
      setState(() => _error = 'Could not send code: $e');
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _runProviderSignIn(Future<void> Function() signIn) async {
    setState(() {
      _signingInWithProvider = true;
      _error = null;
    });
    try {
      await signIn();
      // authProvider's listener picks up the resulting session change and
      // GoRouter's redirect (app_router.dart) takes it from here -- no
      // manual navigation needed on success.
    } catch (e) {
      setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _signingInWithProvider = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _sendingOtp || _signingInWithProvider;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Proximity', style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: AppColors.brand)),
              const SizedBox(height: 4),
              Text(
                'Your local shops, one app away',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                enabled: !busy,
                decoration: const InputDecoration(labelText: 'Email address', hintText: 'you@example.com'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: busy ? null : _sendOtp,
                child: _sendingOtp
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Send code'),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(child: Divider(color: AppColors.line)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or', style: TextStyle(color: AppColors.inkSoft)),
                  ),
                  const Expanded(child: Divider(color: AppColors.line)),
                ],
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: busy ? null : () => _runProviderSignIn(ref.read(authProvider.notifier).signInWithGoogle),
                icon: const Icon(Icons.g_mobiledata, size: 28),
                label: const Text('Continue with Google'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
              const SizedBox(height: 12),
              SignInWithAppleButton(
                onPressed: busy ? () {} : () => _runProviderSignIn(ref.read(authProvider.notifier).signInWithApple),
                style: SignInWithAppleButtonStyle.black,
                height: 48,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: AppColors.urgent)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
