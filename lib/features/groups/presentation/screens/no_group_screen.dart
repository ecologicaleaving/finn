import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/primary_button.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/group_provider.dart';

/// Screen shown when user has no group.
/// Offers options to create a new group or join an existing one.
class NoGroupScreen extends ConsumerWidget {
  const NoGroupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final authState = ref.watch(authProvider);
    if (authState.hasError && user == null) {
      return Scaffold(
        body: ErrorDisplay(
          message: authState.errorMessage ??
              'Impossibile caricare il profilo. Riprova.',
          onRetry: () => ref.read(authProvider.notifier).retryCurrentUser(),
        ),
      );
    }
    final groupState = ref.watch(groupProvider);

    if (groupState.hasGroup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/main');
      });
      return const Scaffold(
        body: LoadingIndicator(message: 'Caricamento gruppo...'),
      );
    }
    if (groupState.status != GroupStatus.noGroup) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gruppo')),
        body: groupState.hasError
            ? ErrorDisplay(
                message: groupState.errorMessage ??
                    'Impossibile caricare il gruppo. Riprova.',
                onRetry: () => ref.read(groupProvider.notifier).loadCurrentGroup(),
              )
            : const LoadingIndicator(message: 'Caricamento gruppo...'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fin'),
        actions: [
          IconButton(
            tooltip: 'Aggiorna gruppo',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(groupProvider.notifier).loadCurrentGroup(),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authProvider.notifier).signOut();
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Welcome icon
              Icon(
                Icons.family_restroom,
                size: 80,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),

              // Welcome message
              Text(
                'Ciao, ${user?.displayName ?? "Utente"}!',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Non fai ancora parte di un gruppo famiglia.\nCrea un nuovo gruppo o unisciti a uno esistente.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // Create group button
              PrimaryButton(
                onPressed: () => context.go('/create-group'),
                label: 'Crea nuovo gruppo',
                icon: Icons.add,
              ),
              const SizedBox(height: 16),

              // Join group button
              SecondaryButton(
                onPressed: () => context.go('/join-group'),
                label: 'Unisciti con codice',
                icon: Icons.group_add,
              ),
              const SizedBox(height: 48),

              // Info card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Il gruppo famiglia ti permette di condividere le spese con i tuoi familiari.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
