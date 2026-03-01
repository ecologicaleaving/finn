import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/icon_matching_service.dart';
import '../../domain/entities/expense_entity.dart';

/// Widget showing expense summary grouped by category
class ExpenseCategorySummary extends StatefulWidget {
  const ExpenseCategorySummary({
    super.key,
    required this.expenses,
  });

  final List<ExpenseEntity> expenses;

  @override
  State<ExpenseCategorySummary> createState() => _ExpenseCategorySummaryState();
}

class _ExpenseCategorySummaryState extends State<ExpenseCategorySummary> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.currency(
      locale: 'it_IT',
      symbol: '\u20ac',
      decimalDigits: 2,
    );

    // Group expenses by category
    final categoryTotals = <String, double>{};
    for (final expense in widget.expenses) {
      final category = expense.categoryName ?? 'Altro';
      categoryTotals[category] = (categoryTotals[category] ?? 0.0) + expense.amount;
    }

    // Sort by amount descending
    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final totalAmount = categoryTotals.values.fold<double>(0.0, (sum, amount) => sum + amount);

    if (sortedCategories.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(16),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.pie_chart,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Riepilogo per Categoria',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Totale: ${currencyFormat.format(totalAmount)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            const Divider(height: 1),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: sortedCategories.length,
              separatorBuilder: (context, index) => const Divider(height: 1, indent: 56),
              itemBuilder: (context, index) {
                final entry = sortedCategories[index];
                final categoryName = entry.key;
                final amount = entry.value;
                final percentage = totalAmount > 0 ? (amount / totalAmount) * 100 : 0.0;

                return ListTile(
                  dense: true,
                  leading: Icon(
                    IconMatchingService.getDefaultIconForCategory(categoryName),
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  title: Text(
                    categoryName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    '${percentage.toStringAsFixed(1)}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: Text(
                    currencyFormat.format(amount),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
