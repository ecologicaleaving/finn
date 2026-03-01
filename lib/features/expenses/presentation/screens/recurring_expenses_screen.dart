import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../providers/recurring_expense_provider.dart';
import '../widgets/recurring_expense_card.dart';

/// Screen for managing all recurring expense templates
///
/// Feature 013-recurring-expenses - User Story 3 (T041, T045, T048-T049)
///
/// Displays list of recurring expenses with:
/// - Active and paused templates
/// - Filtering options
/// - Pause/Resume and Delete actions
/// - Empty state when no templates exist
/// - Pull-to-refresh
class RecurringExpensesScreen extends ConsumerStatefulWidget {
  const RecurringExpensesScreen({super.key});

  @override
  ConsumerState<RecurringExpensesScreen> createState() =>
      _RecurringExpensesScreenState();
}

class _RecurringExpensesScreenState
    extends ConsumerState<RecurringExpensesScreen> {
  // Filter state (T045)
  bool? _filterPaused;
  bool? _filterBudgetReservation;

  @override
  void initState() {
    super.initState();
    // Load recurring expenses on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(recurringExpenseListProvider.notifier).loadRecurringExpenses();
    });
  }

  Future<void> _handleRefresh() async {
    await ref
        .read(recurringExpenseListProvider.notifier)
        .loadRecurringExpenses(refresh: true);
  }

  /// Show delete confirmation dialog (T044)
  Future<void> _showDeleteDialog(
    BuildContext context,
    String templateId,
    String categoryName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina spesa ricorrente'),
        content: Text(
          'Vuoi eliminare la spesa ricorrente "$categoryName"?\n\n'
          'Questa azione non può essere annullata.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final formNotifier = ref.read(recurringExpenseFormProvider.notifier);
      final listNotifier = ref.read(recurringExpenseListProvider.notifier);

      final success = await formNotifier.deleteRecurringExpense(
        context: context,
        id: templateId,
        deleteInstances: false, // Keep existing instances
      );

      if (success) {
        listNotifier.removeTemplateFromList(templateId);
      }
    }
  }

  /// Handle pause/resume action (T043)
  Future<void> _handlePauseResume(String templateId, bool isPaused) async {
    final formNotifier = ref.read(recurringExpenseFormProvider.notifier);
    final listNotifier = ref.read(recurringExpenseListProvider.notifier);

    final template = isPaused
        ? await formNotifier.resumeRecurringExpense(
            context: context,
            id: templateId,
          )
        : await formNotifier.pauseRecurringExpense(
            context: context,
            id: templateId,
          );

    if (template != null) {
      listNotifier.updateTemplateInList(template);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recurringExpenseListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spese ricorrenti'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          // Filter menu (T045)
          PopupMenuButton<String>(
            icon: Icon(
              Icons.filter_list,
              color: (state.hasFilters)
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
            ),
            onSelected: (value) {
              setState(() {
                switch (value) {
                  case 'all':
                    _filterPaused = null;
                    _filterBudgetReservation = null;
                    ref
                        .read(recurringExpenseListProvider.notifier)
                        .clearFilters();
                    break;
                  case 'active':
                    _filterPaused = false;
                    ref
                        .read(recurringExpenseListProvider.notifier)
                        .setFilterPaused(false);
                    break;
                  case 'paused':
                    _filterPaused = true;
                    ref
                        .read(recurringExpenseListProvider.notifier)
                        .setFilterPaused(true);
                    break;
                  case 'budget_reservation':
                    _filterBudgetReservation = true;
                    ref
                        .read(recurringExpenseListProvider.notifier)
                        .setFilterBudgetReservation(true);
                    break;
                }
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'all',
                child: Text('Tutte'),
              ),
              const PopupMenuItem(
                value: 'active',
                child: Text('Solo attive'),
              ),
              const PopupMenuItem(
                value: 'paused',
                child: Text('Solo in pausa'),
              ),
              const PopupMenuItem(
                value: 'budget_reservation',
                child: Text('Con riserva budget'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh, // T049
        child: _buildBody(state),
      ),
    );
  }

  Widget _buildBody(RecurringExpenseListState state) {
    if (state.isLoading) {
      return const Center(child: LoadingIndicator());
    }

    if (state.hasError) {
      return ErrorDisplay(
        message: state.errorMessage ?? 'Errore nel caricamento',
        icon: Icons.error_outline,
        onRetry: () => ref
            .read(recurringExpenseListProvider.notifier)
            .loadRecurringExpenses(refresh: true),
      );
    }

    // Empty state (T048)
    if (state.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.loop,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'Nessuna spesa ricorrente',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Crea una spesa ricorrente per automatizzare le tue spese ripetitive',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.go('/add-expense'),
                icon: const Icon(Icons.add),
                label: const Text('Aggiungi spesa'),
              ),
            ],
          ),
        ),
      );
    }

    // List of recurring expenses
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.templates.length,
      itemBuilder: (context, index) {
        final template = state.templates[index];
        return RecurringExpenseCard(
          template: template,
          onTap: () {
            // Navigate to edit recurring expense screen (T027)
            context.go('/recurring-expense/${template.id}/edit');
          },
          onPauseResume: () => _handlePauseResume(template.id, template.isPaused),
          onDelete: () => _showDeleteDialog(
            context,
            template.id,
            template.categoryName,
          ),
        );
      },
    );
  }
}
