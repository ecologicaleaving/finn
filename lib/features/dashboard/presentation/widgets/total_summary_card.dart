import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/dashboard_stats_entity.dart';

/// Card showing total expense summary.
class TotalSummaryCard extends StatelessWidget {
  const TotalSummaryCard({
    super.key,
    required this.stats,
    this.isPersonalView = false,
  });

  final DashboardStats stats;
  final bool isPersonalView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.currency(
      locale: 'it_IT',
      symbol: '\u20ac',
      decimalDigits: 2,
    );

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isPersonalView ? Icons.person : Icons.group,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  isPersonalView ? 'Le tue spese' : 'Spese del gruppo',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StatItem(
                    label: 'Spese',
                    value: currencyFormat.format(stats.totalAmount),
                    valueColor: theme.colorScheme.error,
                    isLarge: true,
                  ),
                ),
                if (stats.totalIncome > 0)
                  Expanded(
                    child: _StatItem(
                      label: 'Entrate',
                      value: currencyFormat.format(stats.totalIncome),
                      valueColor: const Color(0xFF2E7D32),
                      isLarge: true,
                    ),
                  ),
                if (stats.totalIncome > 0)
                  Expanded(
                    child: _StatItem(
                      label: 'Saldo',
                      value: currencyFormat.format(stats.netBalance),
                      valueColor: stats.netBalance >= 0
                          ? const Color(0xFF2E7D32)
                          : theme.colorScheme.error,
                      isLarge: true,
                    ),
                  ),
                if (stats.totalIncome == 0) ...[
                  Expanded(
                    child: _StatItem(
                      label: 'N. spese',
                      value: stats.expenseCount.toString(),
                    ),
                  ),
                  Expanded(
                    child: _StatItem(
                      label: 'Media',
                      value: currencyFormat.format(stats.averageExpense),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDateRange(stats.startDate, stats.endDate),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateRange(DateTime start, DateTime end) {
    final dateFormat = DateFormat('d MMM', 'it_IT');
    final yearFormat = DateFormat('yyyy');

    if (start.year == end.year) {
      return '${dateFormat.format(start)} - ${dateFormat.format(end)} ${yearFormat.format(end)}';
    }
    return '${dateFormat.format(start)} ${yearFormat.format(start)} - ${dateFormat.format(end)} ${yearFormat.format(end)}';
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    this.valueColor,
    this.isLarge = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool isLarge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: isLarge
              ? theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                )
              : theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                ),
        ),
      ],
    );
  }
}

/// Compact summary row for smaller spaces.
class CompactSummaryRow extends StatelessWidget {
  const CompactSummaryRow({
    super.key,
    required this.totalAmount,
    required this.expenseCount,
  });

  final double totalAmount;
  final int expenseCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.currency(
      locale: 'it_IT',
      symbol: '\u20ac',
      decimalDigits: 2,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              Icons.euro,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              currencyFormat.format(totalAmount),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Icon(
              Icons.receipt_long,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              '$expenseCount spese',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
