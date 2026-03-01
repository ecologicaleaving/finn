import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/app_theme.dart';
import '../../../../core/enums/recurrence_frequency.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../expenses/domain/entities/recurring_expense.dart';

/// Widget to display budget reservation breakdown for recurring expenses
///
/// Feature 013-recurring-expenses - User Story 2 (T037)
///
/// Shows:
/// - List of recurring expenses with budget reservation enabled
/// - Amount reserved for each expense
/// - Total reserved budget
/// - Breakdown by frequency (monthly, yearly, etc.)
///
/// Example:
/// ```dart
/// BudgetReservationDisplay(
///   recurringExpenses: expenses,
///   month: 1,
///   year: 2026,
/// )
/// ```
class BudgetReservationDisplay extends StatelessWidget {
  const BudgetReservationDisplay({
    super.key,
    required this.recurringExpenses,
    required this.month,
    required this.year,
  });

  final List<RecurringExpense> recurringExpenses;
  final int month;
  final int year;

  @override
  Widget build(BuildContext context) {
    // Filter to only expenses with budget reservation enabled and not paused
    final reservedExpenses = recurringExpenses
        .where((e) => e.budgetReservationEnabled && !e.isPaused)
        .toList();

    if (reservedExpenses.isEmpty) {
      return const SizedBox.shrink();
    }

    // Calculate total reserved
    final totalReserved = reservedExpenses.fold<int>(
      0,
      (sum, expense) => sum + (expense.amount * 100).round(),
    );

    return Card(
      color: AppColors.cream,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.loop,
                  color: AppColors.terracotta,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Budget Riservato',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const Spacer(),
                Text(
                  CurrencyUtils.formatCentsCompact(totalReserved),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),

            Text(
              'Riservato per ${reservedExpenses.length} spese ricorrenti',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: AppColors.inkLight,
              ),
            ),

            const SizedBox(height: 16),

            const Divider(height: 1, color: AppColors.parchmentDark),

            const SizedBox(height: 12),

            // List of reserved expenses
            ...reservedExpenses.map((expense) {
              final amountCents = (expense.amount * 100).round();
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    // Frequency icon
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.parchment,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        _getFrequencyIcon(expense.frequency),
                        size: 14,
                        color: AppColors.inkLight,
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Expense details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            expense.merchant ?? 'Spesa ricorrente',
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _getFrequencyLabel(expense.frequency),
                            style: GoogleFonts.dmSans(
                              fontSize: 11,
                              color: AppColors.inkLight,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Reserved amount
                    Text(
                      CurrencyUtils.formatCentsCompact(amountCents),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.copper,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  IconData _getFrequencyIcon(RecurrenceFrequency frequency) {
    switch (frequency) {
      case RecurrenceFrequency.daily:
        return Icons.today;
      case RecurrenceFrequency.weekly:
        return Icons.view_week;
      case RecurrenceFrequency.monthly:
        return Icons.calendar_month;
      case RecurrenceFrequency.yearly:
        return Icons.calendar_today;
    }
  }

  String _getFrequencyLabel(RecurrenceFrequency frequency) {
    switch (frequency) {
      case RecurrenceFrequency.daily:
        return 'Giornaliera';
      case RecurrenceFrequency.weekly:
        return 'Settimanale';
      case RecurrenceFrequency.monthly:
        return 'Mensile';
      case RecurrenceFrequency.yearly:
        return 'Annuale';
    }
  }
}
