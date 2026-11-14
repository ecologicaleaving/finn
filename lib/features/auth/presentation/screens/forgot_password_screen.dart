import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../providers/auth_provider.dart';

/// Forgot password screen for password reset.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _emailFocusNode = FocusNode();
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    _emailFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref.read(authProvider.notifier).resetPassword(
          email: _emailController.text.trim(),
        );

    if (mounted && success) {
      setState(() {
        _emailSent = true;
      });
    }
  }

  void _navigateToLogin() {
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _navigateToLogin,
        ),
        title: const Text('Recupera password'),
      ),
      body: SafeArea(
        child: Center(
          child: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _emailSent
                  ? _buildSuccessContent(theme)
                  : _buildFormContent(authState, theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormContent(AuthState authState, ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Icon
          Icon(
            Icons.lock_reset,
            size: 80,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),

          // Instructions
          Text(
            'Recupero password',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Inserisci la tua email e ti invieremo un link per reimpostare la password.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Error message
          if (authState.hasError && authState.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: InlineError(message: authState.errorMessage!),
            ),

          // Email field
          EmailTextField(
            controller: _emailController,
            focusNode: _emailFocusNode,
            enabled: !authState.isLoading,
            validator: Validators.validateEmail,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _handleResetPassword(),
          ),
          const SizedBox(height: 24),

          // Submit button
          PrimaryButton(
            onPressed: _handleResetPassword,
            label: 'Invia link di recupero',
            isLoading: authState.isLoading,
            loadingLabel: 'Invio in corso...',
          ),
          const SizedBox(height: 16),

          // Back to login
          TextButton(
            onPressed: authState.isLoading ? null : _navigateToLogin,
            child: const Text('Torna al login'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessContent(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Success icon
        Icon(
          Icons.mark_email_read,
          size: 80,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 24),

        // Success message
        Text(
          'Email inviata!',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Controlla la tua casella di posta (anche lo spam) per il link di recupero password.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _emailController.text,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // Back to login button
        PrimaryButton(
          onPressed: _navigateToLogin,
          label: 'Torna al login',
        ),
        const SizedBox(height: 16),

        // Resend link
        TextButton(
          onPressed: () {
            setState(() {
              _emailSent = false;
            });
          },
          child: const Text('Non hai ricevuto l\'email? Riprova'),
        ),
      ],
    );
  }
}
