// Widget: Budget Summary Card for Dashboard
// Feature: Italian Categories and Budget Management (004)
// Tasks: T053-T055

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../budgets/presentation/providers/category_budget_provider.dart';
import '../../../budgets/presentation/providers/budget_repository_provider.dart';
import '../../../groups/presentation/providers/group_provider.dart';
import '../../domain/entities/dashboard_stats_entity.dart';

/// Card showing overall budget summary for the selected period
class BudgetSummaryCard extends ConsumerWidget {
  const BudgetSummaryCard({
    super.key,
    this.onTap,
    required this.period,
    required this.offset,
  });

  final VoidCallback? onTap;
  final DashboardPeriod period;
  final int offset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.currency(
      locale: 'it_IT',
      symbol: '\u20ac',
      decimalDigits: 2,
    );

    final groupId = ref.watch(currentGroupIdProvider);

    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchOverallBudgetStats(ref, groupId, period, offset),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Budget ${period.label}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Center(
                    child: CircularProgressIndicator(),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          return Card(
            elevation: 2,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.account_balance_wallet_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Budget Mensile',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Nessun budget impostato',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: onTap,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Imposta budget'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final stats = snapshot.data!;
        final totalBudgeted = (stats['total_budgeted'] as int?) ?? 0;
        final totalSpent = (stats['total_spent'] as int?) ?? 0;
        final categoriesWithBudget = (stats['categories_with_budget'] as int?) ?? 0;
        final categoriesOverBudget = (stats['categories_over_budget'] as int?) ?? 0;
        final percentageUsed = (stats['percentage_used'] as double?) ?? 0.0;

        final remaining = totalBudgeted - totalSpent;
        final isOverBudget = totalSpent > totalBudgeted;

        return Card(
          elevation: 2,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Budget Mensile',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (categoriesOverBudget > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.warning,
                                size: 14,
                                color: Colors.red.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$categoriesOverBudget oltre budget',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Budget amounts
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Budget totale',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currencyFormat.format(totalBudgeted / 100),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            isOverBudget ? 'Oltre budget' : 'Rimanente',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isOverBudget
                                  ? Colors.red.shade700
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currencyFormat.format(remaining.abs() / 100),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isOverBudget
                                  ? Colors.red.shade700
                                  : Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Progress bar
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Speso',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            currencyFormat.format(totalSpent / 100),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (percentageUsed / 100).clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isOverBudget
                                ? Colors.red.shade700
                                : percentageUsed >= 90
                                    ? Colors.orange.shade700
                                    : theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${percentageUsed.toStringAsFixed(0)}% utilizzato',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Categories info
                  Text(
                    '$categoriesWithBudget categorie con budget',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Calculate date range based on period and offset
  (int year, int? month) _calculateDateParams(DashboardPeriod period, int offset) {
    final now = DateTime.now();

    switch (period) {
      case DashboardPeriod.week:
      case DashboardPeriod.month:
        // For week and month, we show the month that contains the period
        final targetDate = DateTime(now.year, now.month + offset, 1);
        return (targetDate.year, targetDate.month);

      case DashboardPeriod.year:
        // For year, we aggregate all 12 months
        final targetYear = now.year + offset;
        return (targetYear, null);
    }
  }

  Future<Map<String, dynamic>?> _fetchOverallBudgetStats(
    WidgetRef ref,
    String groupId,
    DashboardPeriod period,
    int offset,
  ) async {
    final repository = ref.read(budgetRepositoryProvider);
    final (year, month) = _calculateDateParams(period, offset);

    // For annual view, aggregate all 12 months
    if (period == DashboardPeriod.year) {
      try {
        // Fetch stats for all 12 months in parallel
        final futures = List.generate(12, (index) {
          final monthNum = index + 1;
          return repository.getOverallGroupBudgetStats(
            groupId: groupId,
            year: year,
            month: monthNum,
          );
        });

        final results = await Future.wait(futures);

        // Aggregate the results
        int totalBudgeted = 0;
        int totalSpent = 0;
        int categoriesWithBudget = 0;
        int categoriesOverBudget = 0;

        for (final result in results) {
          result.fold(
            (failure) => null,
            (stats) {
              if (stats != null) {
                final monthStats = stats as Map<String, dynamic>;
                totalBudgeted += (monthStats['total_budgeted'] as int?) ?? 0;
                totalSpent += (monthStats['total_spent'] as int?) ?? 0;
                // For categories, we take max to avoid counting same category multiple times
                categoriesWithBudget = (monthStats['categories_with_budget'] as int? ?? 0) > categoriesWithBudget
                    ? (monthStats['categories_with_budget'] as int? ?? 0)
                    : categoriesWithBudget;
                categoriesOverBudget = (monthStats['categories_over_budget'] as int? ?? 0) > categoriesOverBudget
                    ? (monthStats['categories_over_budget'] as int? ?? 0)
                    : categoriesOverBudget;
              }
            },
          );
        }

        // Calculate percentage
        final percentageUsed = totalBudgeted > 0 ? (totalSpent / totalBudgeted) * 100 : 0.0;

        return {
          'total_budgeted': totalBudgeted,
          'total_spent': totalSpent,
          'categories_with_budget': categoriesWithBudget,
          'categories_over_budget': categoriesOverBudget,
          'percentage_used': percentageUsed,
        };
      } catch (e) {
        return null;
      }
    }

    // For monthly/weekly view, use single month
    final result = await repository.getOverallGroupBudgetStats(
      groupId: groupId,
      year: year,
      month: month!,
    );

    return result.fold(
      (failure) => null,
      (stats) => stats as Map<String, dynamic>?,
    );
  }
}
