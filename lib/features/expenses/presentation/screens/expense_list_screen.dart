import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/expense_entity.dart';

import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../categories/presentation/widgets/category_dropdown.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../groups/presentation/providers/group_provider.dart';
import '../providers/expense_provider.dart';
import '../widgets/expense_list_item.dart';
import '../widgets/delete_confirmation_dialog.dart';

/// Screen showing list of expenses with filtering options.
class ExpenseListScreen extends ConsumerStatefulWidget {
  const ExpenseListScreen({
    super.key,
    this.showGroupExpensesOnly,
  });

  final bool? showGroupExpensesOnly;

  @override
  ConsumerState<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends ConsumerState<ExpenseListScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Load expenses on init
    // Note: Filter is now set by parent ExpenseTabsScreen, so we don't set it here
    // This allows the screen to be reused without forcing a filter
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(expenseListProvider.notifier).loadMore();
    }
  }

  /// Group expenses by month and year
  Map<String, List<ExpenseEntity>> _groupExpensesByMonth(List<ExpenseEntity> expenses) {
    final grouped = <String, List<ExpenseEntity>>{};

    for (final expense in expenses) {
      final date = expense.date;
      final key = DateFormat('yyyy-MM').format(date);
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(expense);
    }

    // Sort keys in descending order (newest first)
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Map.fromEntries(
      sortedKeys.map((key) => MapEntry(key, grouped[key]!)),
    );
  }

  /// Format month key for display
  String _formatMonthHeader(String monthKey) {
    final date = DateTime.parse('$monthKey-01');
    return DateFormat('MMMM yyyy', 'it_IT').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(expenseListProvider);
    final theme = Theme.of(context);

    return _buildBody(theme, listState);
  }

  Widget _buildBody(ThemeData theme, ExpenseListState listState) {
    if (listState.isLoading && listState.expenses.isEmpty) {
      return const LoadingIndicator(message: 'Caricamento spese...');
    }

    if (listState.hasError && listState.expenses.isEmpty) {
      return ErrorDisplay(
        message: listState.errorMessage ?? 'Errore durante il caricamento',
        onRetry: () => ref.read(expenseListProvider.notifier).refresh(),
      );
    }

    if (listState.isEmpty) {
      return EmptyDisplay(
        message: listState.hasFilters
            ? 'Nessuna spesa corrisponde ai filtri selezionati'
            : 'Non hai ancora registrato nessuna spesa',
        icon: Icons.receipt_long_outlined,
      );
    }

    final currentUser = ref.watch(currentUserProvider);
    final isAdmin = ref.watch(isGroupAdminProvider);

    // Group expenses by month
    final groupedExpenses = _groupExpensesByMonth(listState.expenses);

    return RefreshIndicator(
      onRefresh: () => ref.read(expenseListProvider.notifier).refresh(),
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Expenses grouped by month
          ...groupedExpenses.entries.map((entry) {
            final monthKey = entry.key;
            final monthExpenses = entry.value;

            return SliverMainAxisGroup(
              slivers: [
                // Month header
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_month,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatMonthHeader(monthKey),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${monthExpenses.length} ${monthExpenses.length == 1 ? 'spesa' : 'spese'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Expenses for this month
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final expense = monthExpenses[index];
                      final canDelete = expense.canDelete(currentUser?.id ?? '', isAdmin);

                      return Column(
                        children: [
                          Dismissible(
                            key: Key(expense.id),
                            direction: canDelete ? DismissDirection.endToStart : DismissDirection.none,
                            confirmDismiss: (direction) => _showDeleteConfirmDialog(context, expense),
                            onDismissed: (direction) => _handleSwipeDelete(expense),
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              color: theme.colorScheme.error,
                              child: Icon(
                                Icons.delete,
                                color: theme.colorScheme.onError,
                                size: 28,
                              ),
                            ),
                            child: ExpenseListItem(
                              expense: expense,
                              onTap: () => context.push('/expense/${expense.id}'),
                            ),
                          ),
                          if (index < monthExpenses.length - 1)
                            const Divider(height: 1),
                        ],
                      );
                    },
                    childCount: monthExpenses.length,
                  ),
                ),
              ],
            );
          }),

          // Loading indicator for pagination
          if (listState.hasMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),

          // Bottom padding
          const SliverToBoxAdapter(
            child: SizedBox(height: 88),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showDeleteConfirmDialog(BuildContext context, ExpenseEntity expense) {
    return DeleteConfirmationDialog.show(
      context,
      expenseName: expense.merchant ?? expense.formattedAmount,
      isReimbursable: expense.isPendingReimbursement,
    );
  }

  /// Handles the swipe delete with immediate backend deletion
  Future<void> _handleSwipeDelete(ExpenseEntity expense) async {
    // Remove from UI immediately (already done by Dismissible)
    ref.read(expenseListProvider.notifier).removeExpenseFromList(expense.id);

    // Show loading snackbar
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Eliminazione in corso...'),
        duration: Duration(seconds: 1),
      ),
    );

    // Execute immediate backend deletion
    final success = await ref.read(expenseFormProvider.notifier).deleteExpense(
          expenseId: expense.id,
        );

    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();

    if (success) {
      // Refresh dashboard to reflect the deleted expense
      ref.read(dashboardProvider.notifier).refresh();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Spesa eliminata'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      // If delete failed, restore the item to the list
      ref.read(expenseListProvider.notifier).addExpense(expense);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Errore durante l\'eliminazione'),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showFilterDialog(BuildContext context) {
    ExpenseFilterBottomSheet.show(context);
  }
}

class ExpenseFilterBottomSheet extends ConsumerStatefulWidget {
  const ExpenseFilterBottomSheet({super.key});

  @override
  ConsumerState<ExpenseFilterBottomSheet> createState() => _ExpenseFilterBottomSheetState();

  /// Show the filter bottom sheet
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const ExpenseFilterBottomSheet(),
    );
  }
}

class _ExpenseFilterBottomSheetState extends ConsumerState<ExpenseFilterBottomSheet> {
  DateTimeRange? _dateRange;
  String? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    final state = ref.read(expenseListProvider);
    if (state.filterStartDate != null && state.filterEndDate != null) {
      _dateRange = DateTimeRange(
        start: state.filterStartDate!,
        end: state.filterEndDate!,
      );
    }
    _selectedCategoryId = state.filterCategoryId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);
    final groupId = authState.user?.groupId;

    return Padding(
      padding: EdgeInsets.only(
        top: 16,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Filtra spese',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 24),

            // Category filter
            if (groupId != null) ...[
              CategoryDropdownMRU(
                value: _selectedCategoryId,
                onChanged: (categoryId) => setState(() => _selectedCategoryId = categoryId),
                label: 'Categoria',
                hint: 'Tutte le categorie',
              ),
              const SizedBox(height: 16),
            ],

            // Date range filter
            ListTile(
              leading: const Icon(Icons.date_range),
              title: const Text('Periodo'),
              subtitle: _dateRange != null
                  ? Text(
                      '${_formatDate(_dateRange!.start)} - ${_formatDate(_dateRange!.end)}',
                    )
                  : const Text('Tutte le date'),
              trailing: _dateRange != null
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _dateRange = null),
                    )
                  : null,
              onTap: _selectDateRange,
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      ref.read(expenseListProvider.notifier).clearFilters();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Cancella filtri'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _applyFilters,
                    child: const Text('Applica'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
      locale: const Locale('it', 'IT'),
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
    }
  }

  void _applyFilters() {
    // Apply category filter (null to clear)
    ref.read(expenseListProvider.notifier).setFilterCategory(_selectedCategoryId);

    // Apply date range filter
    ref.read(expenseListProvider.notifier).setFilterDateRange(
          _dateRange?.start,
          _dateRange?.end,
        );
    Navigator.of(context).pop();
  }
}
