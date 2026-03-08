import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../shared/widgets/offline_banner.dart';
import '../providers/expense_provider.dart';
import '../widgets/monthly_expense_category_view.dart';
import 'expense_list_screen.dart';

enum ExpenseFilter { all, personal, group }

/// Screen showing expenses grouped by category for a selected month
class ExpenseTabsScreen extends ConsumerStatefulWidget {
  const ExpenseTabsScreen({
    super.key,
    this.initialTab = 0,
  });

  final int initialTab;

  @override
  ConsumerState<ExpenseTabsScreen> createState() => _ExpenseTabsScreenState();
}

class _ExpenseTabsScreenState extends ConsumerState<ExpenseTabsScreen> {
  ExpenseFilter _selectedFilter = ExpenseFilter.all;

  @override
  void initState() {
    super.initState();
    // Default filter is "all" to show all expenses
    _selectedFilter = ExpenseFilter.all;

    // Apply filter on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyFilter(_selectedFilter);
    });
  }

  void _applyFilter(ExpenseFilter filter) {
    setState(() => _selectedFilter = filter);

    switch (filter) {
      case ExpenseFilter.all:
        ref.read(expenseListProvider.notifier).clearIsGroupExpenseFilter();
        break;
      case ExpenseFilter.personal:
        ref.read(expenseListProvider.notifier).setFilterIsGroupExpense(false);
        break;
      case ExpenseFilter.group:
        ref.read(expenseListProvider.notifier).setFilterIsGroupExpense(true);
        break;
    }
  }

  void _showFilterDialog(BuildContext context) {
    ExpenseFilterBottomSheet.show(context);
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(expenseListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Le mie spese'),
        actions: [
          if (listState.hasFilters)
            IconButton(
              icon: const Icon(Icons.filter_alt_off),
              onPressed: () => ref.read(expenseListProvider.notifier).clearFilters(),
              tooltip: 'Rimuovi filtri',
            ),
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: () => _showFilterDialog(context),
            tooltip: 'Filtra',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _FilterChip(
                  label: 'Tutte',
                  isSelected: _selectedFilter == ExpenseFilter.all,
                  onTap: () => _applyFilter(ExpenseFilter.all),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Personali',
                  isSelected: _selectedFilter == ExpenseFilter.personal,
                  onTap: () => _applyFilter(ExpenseFilter.personal),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Di Gruppo',
                  isSelected: _selectedFilter == ExpenseFilter.group,
                  onTap: () => _applyFilter(ExpenseFilter.group),
                ),
              ],
            ),
          ),

          const OfflineBanner(),

          Expanded(
            child: _buildMonthlyBody(context, listState),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyBody(BuildContext context, ExpenseListState listState) {
    if (listState.isLoading && listState.expenses.isEmpty) {
      return const LoadingIndicator(message: 'Caricamento spese...');
    }

    if (listState.hasError && listState.expenses.isEmpty) {
      return ErrorDisplay(
        message: listState.errorMessage ?? 'Errore durante il caricamento',
        onRetry: () => ref.read(expenseListProvider.notifier).refresh(),
      );
    }

    return MonthlyExpenseCategoryView(
      expenses: listState.expenses,
      hasMoreExpenses: listState.hasMore,
      onLoadOlderMonths: () => ref.read(expenseListProvider.notifier).loadMore(),
      onExpenseTap: (expense) => context.push('/expense/${expense.id}'),
    );
  }
}

/// Filter chip widget
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withOpacity(0.5),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
