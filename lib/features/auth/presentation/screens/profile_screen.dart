import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../providers/auth_provider.dart';

/// Profile screen with user info, edit options, and account deletion.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    if (user != null && user.displayName != null) {
      _displayNameController.text = user.displayName!;
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _saveDisplayName() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final success = await ref.read(authProvider.notifier).updateDisplayName(
          displayName: _displayNameController.text.trim(),
        );

    setState(() {
      _isSaving = false;
      if (success) _isEditing = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Nome aggiornato' : 'Errore nell\'aggiornamento'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Esci'),
        content: const Text('Sei sicuro di voler uscire?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Esci'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(authProvider.notifier).signOut();
      if (mounted) {
        context.go(AppRoutes.login);
      }
    }
  }

  Future<void> _deleteAccount() async {
    // First dialog: confirm deletion intent
    final wantsToDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina account'),
        content: const Text(
          'Sei sicuro di voler eliminare il tuo account?\n\n'
          'Questa azione non può essere annullata.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Continua'),
          ),
        ],
      ),
    );

    if (wantsToDelete != true || !mounted) return;

    // Second dialog: choose data retention option (FR-021)
    final keepName = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dati delle spese'),
        content: const Text(
          'Le tue spese verranno conservate per il gruppo.\n\n'
          'Vuoi mantenere il tuo nome visibile sulle spese passate '
          'o renderle anonime?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Annulla'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Rendi anonimo'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mantieni nome'),
          ),
        ],
      ),
    );

    if (keepName == null || !mounted) return;

    // Final confirmation
    final finalConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conferma eliminazione'),
        content: Text(
          'Stai per eliminare definitivamente il tuo account.\n\n'
          '${keepName ? 'Il tuo nome rimarrà visibile sulle spese passate.' : 'Le tue spese passate saranno rese anonime.'}\n\n'
          'Vuoi procedere?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Elimina account'),
          ),
        ],
      ),
    );

    if (finalConfirm != true || !mounted) return;

    // Proceed with deletion
    final success = await ref.read(authProvider.notifier).deleteAccount(
          anonymizeExpenses: !keepName,
        );

    if (mounted) {
      if (success) {
        context.go(AppRoutes.login);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account eliminato'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        final errorMessage = ref.read(authProvider).errorMessage;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage ?? 'Errore nell\'eliminazione dell\'account',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profilo'),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
              tooltip: 'Modifica',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Avatar
            Center(
              child: CircleAvatar(
                radius: 50,
                backgroundColor: theme.colorScheme.primary,
                child: Text(
                  (user?.displayName?.isNotEmpty == true)
                      ? user!.displayName![0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // User info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Informazioni',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Display name
                      if (_isEditing) ...[
                        CustomTextField(
                          controller: _displayNameController,
                          label: 'Nome visualizzato',
                          prefixIcon: Icons.person,
                          validator: Validators.validateDisplayName,
                          enabled: !_isSaving,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _isSaving
                                  ? null
                                  : () {
                                      setState(() => _isEditing = false);
                                      _displayNameController.text =
                                          user?.displayName ?? '';
                                    },
                              child: const Text('Annulla'),
                            ),
                            const SizedBox(width: 8),
                            PrimaryButton(
                              onPressed: _saveDisplayName,
                              label: 'Salva',
                              isLoading: _isSaving,
                            ),
                          ],
                        ),
                      ] else ...[
                        ListTile(
                          leading: const Icon(Icons.person),
                          title: const Text('Nome'),
                          subtitle: Text(user?.displayName ?? '-'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        const Divider(),
                        ListTile(
                          leading: const Icon(Icons.email),
                          title: const Text('Email'),
                          subtitle: Text(user?.email ?? '-'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Actions
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Esci'),
                    subtitle: const Text('Disconnettiti da questo dispositivo'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: authState.isLoading ? null : _logout,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      Icons.delete_forever,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      'Elimina account',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    subtitle: const Text('Elimina definitivamente il tuo account'),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.error,
                    ),
                    onTap: authState.isLoading ? null : _deleteAccount,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // App info
            Center(
              child: Text(
                'Family Expense Tracker v1.0.0',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
