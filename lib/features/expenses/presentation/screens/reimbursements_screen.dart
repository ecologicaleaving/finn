import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/enums/reimbursement_status.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../providers/reimbursements_provider.dart';

/// Screen for managing reimbursements
///
/// Feature 013-recurring-expenses - User Story 4 (T050-T059)
///
/// Displays all expenses marked as reimbursable or reimbursed with:
/// - Filtering by status (reimbursable vs reimbursed)
/// - Summary totals for pending and completed reimbursements
/// - Quick action to mark reimbursable expenses as reimbursed
/// - Pull-to-refresh functionality
/// - Empty state when no reimbursements exist
class ReimbursementsScreen extends ConsumerStatefulWidget {
  const ReimbursementsScreen({super.key});

  @override
  ConsumerState<ReimbursementsScreen> createState() =>
      _ReimbursementsScreenState();
}

class _ReimbursementsScreenState extends ConsumerState<ReimbursementsScreen> {
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Load reimbursements on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(reimbursementsListProvider.notifier).loadReimbursements();
    });
  }

  Future<void> _handleRefresh() async {
    await ref.read(reimbursementsListProvider.notifier).refresh();
  }

  Future<void> _markAsReimbursed(String expenseId, String merchant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conferma rimborso'),
        content: Text(
          'Vuoi contrassegnare "$merchant" come rimborsato?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Conferma'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await ref
          .read(reimbursementsListProvider.notifier)
          .markAsReimbursed(expenseId);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Spesa contrassegnata come rimborsata')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reimbursementsListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rimborsi'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          // Filter menu (T052)
          PopupMenuButton<ReimbursementFilter>(
            icon: Icon(
              Icons.filter_list,
              color: state.filter != ReimbursementFilter.all
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
            ),
            onSelected: (filter) {
              ref.read(reimbursementsListProvider.notifier).setFilter(filter);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: ReimbursementFilter.all,
                child: Text('Tutti'),
              ),
              const PopupMenuItem(
                value: ReimbursementFilter.reimbursable,
                child: Text('Da rimborsare'),
              ),
              const PopupMenuItem(
                value: ReimbursementFilter.reimbursed,
                child: Text('Rimborsati'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh, // T059
        child: Column(
          children: [
            // Summary section (T053)
            _buildSummary(state, theme),

            // Search bar (T055)
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Cerca per negozio o note...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
              ),
            ),

            // Expenses list
            Expanded(
              child: _buildBody(state),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(ReimbursementsListState state, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Da rimborsare',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '€${(state.totalPendingAmount / 100).toStringAsFixed(2)}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rimborsati',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '€${(state.totalReimbursedAmount / 100).toStringAsFixed(2)}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ReimbursementsListState state) {
    if (state.isLoading) {
      return const Center(child: LoadingIndicator());
    }

    if (state.hasError) {
      return ErrorDisplay(
        message: state.errorMessage ?? 'Errore nel caricamento',
        icon: Icons.error_outline,
        onRetry: () => ref
            .read(reimbursementsListProvider.notifier)
            .loadReimbursements(refresh: true),
      );
    }

    // Empty state (T058)
    if (state.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'Nessun rimborso',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Le spese con stato "Da rimborsare" o "Rimborsato" appariranno qui',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Filter expenses by search query (T055)
    final filteredExpenses = state.filteredExpenses.where((expense) {
      if (_searchQuery.isEmpty) return true;
      final merchant = expense.merchant?.toLowerCase() ?? '';
      final notes = expense.notes?.toLowerCase() ?? '';
      return merchant.contains(_searchQuery) || notes.contains(_searchQuery);
    }).toList();

    if (filteredExpenses.isEmpty) {
      return Center(
        child: Text(
          'Nessun risultato per "$_searchQuery"',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    // List of reimbursements (T052)
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: filteredExpenses.length,
      itemBuilder: (context, index) {
        final expense = filteredExpenses[index];
        final isReimbursable =
            expense.reimbursementStatus == ReimbursementStatus.reimbursable;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isReimbursable
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.tertiaryContainer,
              child: Icon(
                isReimbursable ? Icons.pending_outlined : Icons.check_circle,
                color: isReimbursable
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.tertiary,
              ),
            ),
            title: Text(
              expense.merchant ?? 'Spesa senza negozio',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(DateFormatter.formatFullDate(expense.date)),
                if (expense.notes != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    expense.notes!,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '€${expense.amount.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                // Quick action to mark as reimbursed (T054)
                if (isReimbursable)
                  TextButton(
                    onPressed: () => _markAsReimbursed(
                      expense.id,
                      expense.merchant ?? 'questa spesa',
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 20),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Segna rimborsato',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            onTap: () {
              // Navigate to expense detail
              context.go('/expense/${expense.id}');
            },
          ),
        );
      },
    );
  }
}
