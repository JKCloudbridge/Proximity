import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'auth_provider.dart';

/// Sprint 14 forgot-password flow: email -> OTP code + new password, all on
/// one screen (`_codeSent` gates which half is shown, same "one screen,
/// state-gated sections" shape as slot_picker_sheet.dart elsewhere in this
/// app) -- no separate route needed since there's nowhere else to go
/// between the two steps. `verifyPasswordResetOtp` signs the user in on
/// success, so after `updatePassword` there's nothing left to do but pop:
/// authProvider's own onAuthStateChange listener + GoRouter's redirect
/// (app_router.dart) take it from there, same pattern EmailOtpScreen uses.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _codeSent = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).sendPasswordResetOtp(email);
      if (mounted) setState(() => _codeSent = true);
    } catch (e) {
      setState(() => _error = 'Could not send code: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    final password = _passwordController.text;
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    if (password != _confirmController.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final notifier = ref.read(authProvider.notifier);
      await notifier.verifyPasswordResetOtp(email: email, token: code);
      await notifier.updatePassword(password);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Could not reset password: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                enabled: !_submitting && !_codeSent,
                decoration: const InputDecoration(labelText: 'Email address', hintText: 'you@example.com'),
              ),
              if (!_codeSent) ...[
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _submitting ? null : _sendCode,
                  child: _submitting
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Send reset code'),
                ),
              ] else ...[
                const SizedBox(height: 16),
                Text('We sent a code to ${_emailController.text.trim()}'),
                const SizedBox(height: 12),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  enabled: !_submitting,
                  decoration: const InputDecoration(labelText: 'Code'),
                ),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  enabled: !_submitting,
                  decoration: const InputDecoration(labelText: 'New password'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmController,
                  obscureText: true,
                  enabled: !_submitting,
                  decoration: const InputDecoration(labelText: 'Confirm new password'),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _submitting ? null : _resetPassword,
                  child: _submitting
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Reset password'),
                ),
              ],
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
