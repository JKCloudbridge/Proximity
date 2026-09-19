import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/theme/app_theme.dart';
import 'auth_provider.dart';
import 'forgot_password_screen.dart';
import 'sign_up_screen.dart';

/// Sprint 14: password sign-in + Google + Apple, all visible together --
/// same "no hidden fallback" reasoning this screen has carried since
/// Sprint 1, just with password replacing the old passwordless-OTP-every-
/// time flow as the no-setup-required option (OTP now only gates sign-up
/// and password reset, see sign_up_screen.dart/forgot_password_screen.dart).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _signingIn = false;
  bool _signingInWithProvider = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Enter your password');
      return;
    }
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).signInWithPassword(email: email, password: password);
      // authProvider's listener picks up the resulting session change and
      // GoRouter's redirect (app_router.dart) takes it from here.
    } catch (e) {
      setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _runProviderSignIn(Future<void> Function() signIn) async {
    setState(() {
      _signingInWithProvider = true;
      _error = null;
    });
    try {
      await signIn();
    } catch (e) {
      setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _signingInWithProvider = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _signingIn || _signingInWithProvider;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
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
              TextField(
                controller: _passwordController,
                obscureText: true,
                enabled: !busy,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                          ),
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: busy ? null : _signIn,
                child: _signingIn
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Sign in'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: busy
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignUpScreen())),
                child: const Text("New here? Create an account"),
              ),
              const SizedBox(height: 16),
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
