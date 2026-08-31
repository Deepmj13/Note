import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_v4/core/app_spacing.dart';
import 'package:note_v4/providers/auth_notifier.dart';
import 'package:note_v4/theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isSignUp = false;
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String get _primaryLabel => _isSignUp ? 'Create account' : 'Sign in';
  String get _switchLabel =>
      _isSignUp ? 'Already have an account? Sign in' : 'New here? Create account';

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _showMessage('Please enter your email and password.');
      return;
    }
    setState(() => _loading = true);
    try {
      final auth = ref.read(authControllerProvider.notifier);
      if (_isSignUp) {
        await auth.signUpWithEmail(email, password);
      } else {
        await auth.signInWithEmail(email, password);
      }
    } on AuthException catch (e) {
      if (mounted) _showMessage(e.message);
    } catch (_) {
      if (mounted) _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(palette),
                  const SizedBox(height: AppSpacing.xl),
                  _buildForm(palette),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppPalette palette) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: palette.accentContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.edit_note, size: 36, color: palette.accent),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Notes', style: context.screenTitle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Capture your ideas, tasks and thoughts.',
          style: context.secondaryText,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildForm(AppPalette palette) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _emailController,
            enabled: !_loading,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Email',
              icon: Icon(Icons.mail_outline, color: palette.secondaryText),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _passwordController,
            enabled: !_loading,
            obscureText: _obscurePassword,
            onSubmitted: (_) => _submit(),
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Password',
              icon: Icon(Icons.lock_outline, color: palette.secondaryText),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _loading ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: palette.accent,
              foregroundColor: palette.onAccent,
              disabledBackgroundColor: palette.accent.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
            ),
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _primaryLabel,
                    style: context.bodyText.copyWith(
                      fontWeight: FontWeight.w600,
                      color: palette.onAccent,
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: _loading
                ? null
                : () => setState(() => _isSignUp = !_isSignUp),
            child: Text(
              _switchLabel,
              style: context.secondaryText.copyWith(color: palette.accent),
            ),
          ),
        ],
      ),
    );
  }
}
