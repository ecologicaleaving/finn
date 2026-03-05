import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/icon_matching_service.dart';
import '../../domain/entities/expense_entity.dart';

class MonthlyExpenseCategoryView extends StatefulWidget {
  const MonthlyExpenseCategoryView({
    super.key,
    required this.expenses,
    required this.hasMoreExpenses,
    this.onLoadOlderMonths,
    this.onExpenseTap,
    DateTime? initialMonth,
    DateTime Function()? nowBuilder,
  })  : initialMonth = initialMonth,
        nowBuilder = nowBuilder;

  final List<ExpenseEntity> expenses;
  final bool hasMoreExpenses;
  final VoidCallback? onLoadOlderMonths;
  final ValueChanged<ExpenseEntity>? onExpenseTap;
  final DateTime? initialMonth;
  final DateTime Function()? nowBuilder;

  @override
  State<MonthlyExpenseCategoryView> createState() => _MonthlyExpenseCategoryViewState();
}

class _MonthlyExpenseCategoryViewState extends State<MonthlyExpenseCategoryView> {
  late DateTime _selectedMonth;
  late final NumberFormat _currencyFormat;
  late final DateFormat _monthFormat;
  late final DateFormat _expenseDateFormat;

  @override
  void initState() {
    super.initState();
    final now = widget.nowBuilder?.call() ?? DateTime.now();
    _selectedMonth = _toMonthStart(widget.initialMonth ?? now);
    _currencyFormat = NumberFormat.currency(
      locale: 'it_IT',
      symbol: '\u20ac',
      decimalDigits: 2,
    );
    _monthFormat = DateFormat('MMMM yyyy', 'it_IT');
    _expenseDateFormat = DateFormat('d MMM', 'it_IT');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthExpenses = _expensesForMonth(_selectedMonth);
    final grouped = _groupByCategory(monthExpenses);
    final categoryEntries = grouped.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));

    return Column(
      children: [
        _MonthHeader(
          monthLabel: _capitalize(_monthFormat.format(_selectedMonth)),
          onPrevious: _goPreviousMonth,
          onNext: _goNextMonth,
        ),
        const Divider(height: 1),
        Expanded(
          child: monthExpenses.isEmpty
              ? _EmptyMonthState(
                  hasMoreExpenses: widget.hasMoreExpenses,
                  onLoadOlderMonths: widget.onLoadOlderMonths,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  itemCount: categoryEntries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = categoryEntries[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          IconMatchingService.getDefaultIconForCategory(entry.key),
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(entry.key),
                        subtitle: Text('${entry.value.expenses.length} ${entry.value.expenses.length == 1 ? 'spesa' : 'spese'}'),
                        trailing: Text(
                          _currencyFormat.format(entry.value.total),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onTap: () => _openCategoryDetail(context, entry.key, entry.value.expenses),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _goPreviousMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1);
    });
    _maybeLoadOlderMonths();
  }

  void _goNextMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
    });
  }

  void _maybeLoadOlderMonths() {
    if (!widget.hasMoreExpenses || widget.expenses.isEmpty) return;
    final oldestLoadedMonth = widget.expenses
        .map((expense) => _toMonthStart(expense.date))
        .reduce((a, b) => a.isBefore(b) ? a : b);
    if (!_selectedMonth.isAfter(oldestLoadedMonth)) {
      widget.onLoadOlderMonths?.call();
    }
  }

  List<ExpenseEntity> _expensesForMonth(DateTime month) {
    return widget.expenses
        .where((expense) => expense.date.year == month.year && expense.date.month == month.month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Map<String, _CategoryData> _groupByCategory(List<ExpenseEntity> expenses) {
    final grouped = <String, _CategoryData>{};
    for (final expense in expenses) {
      final category = expense.categoryName?.trim().isNotEmpty == true ? expense.categoryName!.trim() : 'Altro';
      final current = grouped[category];
      if (current == null) {
        grouped[category] = _CategoryData(total: expense.amount, expenses: [expense]);
      } else {
        grouped[category] = _CategoryData(
          total: current.total + expense.amount,
          expenses: [...current.expenses, expense],
        );
      }
    }
    return grouped;
  }

  void _openCategoryDetail(BuildContext context, String category, List<ExpenseEntity> expenses) {
    final sorted = [...expenses]..sort((a, b) => b.date.compareTo(a.date));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              children: [
                ListTile(
                  title: Text(
                    category,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(_capitalize(_monthFormat.format(_selectedMonth))),
                  trailing: Text(
                    _currencyFormat.format(sorted.fold<double>(0.0, (sum, e) => sum + e.amount)),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: sorted.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final expense = sorted[index];
                      return ListTile(
                        title: Text(expense.merchant?.trim().isNotEmpty == true ? expense.merchant! : 'Spesa senza nome'),
                        subtitle: Text(_expenseDateFormat.format(expense.date)),
                        trailing: Text(_currencyFormat.format(expense.amount)),
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onExpenseTap?.call(expense);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  DateTime _toMonthStart(DateTime date) => DateTime(date.year, date.month, 1);

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.monthLabel,
    required this.onPrevious,
    required this.onNext,
  });

  final String monthLabel;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Mese precedente',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              monthLabel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Mese successivo',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _EmptyMonthState extends StatelessWidget {
  const _EmptyMonthState({
    required this.hasMoreExpenses,
    this.onLoadOlderMonths,
  });

  final bool hasMoreExpenses;
  final VoidCallback? onLoadOlderMonths;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            const Text(
              'Nessuna spesa questo mese',
              textAlign: TextAlign.center,
            ),
            if (hasMoreExpenses && onLoadOlderMonths != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onLoadOlderMonths,
                icon: const Icon(Icons.download),
                label: const Text('Carica mesi precedenti'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryData {
  const _CategoryData({
    required this.total,
    required this.expenses,
  });

  final double total;
  final List<ExpenseEntity> expenses;
}
