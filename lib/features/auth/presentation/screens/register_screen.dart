import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../providers/auth_provider.dart';

/// Registration screen for new users.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    await ref.read(authProvider.notifier).signUpWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          displayName: _nameController.text.trim(),
        );

    if (mounted) {
      final authState = ref.read(authProvider);
      if (authState.isAuthenticated) {
        context.go('/');
      }
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
        title: const Text('Crea account'),
      ),
      body: SafeArea(
        child: Center(
          child: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Subtitle
                    Text(
                      'Inserisci i tuoi dati per creare un account',
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

                    // Name field
                    CustomTextField(
                      controller: _nameController,
                      focusNode: _nameFocusNode,
                      label: 'Nome',
                      hint: 'Come vuoi essere chiamato',
                      prefixIcon: Icons.person_outlined,
                      textCapitalization: TextCapitalization.words,
                      enabled: !authState.isLoading,
                      validator: Validators.validateDisplayName,
                      onSubmitted: (_) => _emailFocusNode.requestFocus(),
                    ),
                    const SizedBox(height: 16),

                    // Email field
                    EmailTextField(
                      controller: _emailController,
                      focusNode: _emailFocusNode,
                      enabled: !authState.isLoading,
                      validator: Validators.validateEmail,
                      onSubmitted: (_) => _passwordFocusNode.requestFocus(),
                    ),
                    const SizedBox(height: 16),

                    // Password field
                    PasswordTextField(
                      controller: _passwordController,
                      focusNode: _passwordFocusNode,
                      enabled: !authState.isLoading,
                      validator: Validators.validatePassword,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) =>
                          _confirmPasswordFocusNode.requestFocus(),
                    ),
                    const SizedBox(height: 16),

                    // Confirm password field
                    PasswordTextField(
                      controller: _confirmPasswordController,
                      focusNode: _confirmPasswordFocusNode,
                      label: 'Conferma password',
                      enabled: !authState.isLoading,
                      validator: (value) =>
                          Validators.validatePasswordConfirmation(
                        value,
                        _passwordController.text,
                      ),
                      onSubmitted: (_) => _handleRegister(),
                    ),
                    const SizedBox(height: 32),

                    // Register button
                    PrimaryButton(
                      onPressed: _handleRegister,
                      label: 'Registrati',
                      isLoading: authState.isLoading,
                      loadingLabel: 'Registrazione in corso...',
                    ),
                    const SizedBox(height: 16),

                    // Login link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Hai già un account?',
                          style: theme.textTheme.bodyMedium,
                        ),
                        TextButton(
                          onPressed:
                              authState.isLoading ? null : _navigateToLogin,
                          child: const Text('Accedi'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
