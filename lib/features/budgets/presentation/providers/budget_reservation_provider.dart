import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/budget_calculator.dart';
import '../../../expenses/domain/entities/recurring_expense.dart';
import '../../../expenses/presentation/providers/recurring_expense_provider.dart';

/// Provider for the reserved budget of a specific month/year.
///
/// Calculates the total budget reserved by active recurring expenses for the
/// given month. Used by screens that let the user navigate between months so
/// that the reservation follows the selected month instead of always using
/// the current one (issue #50).
final reservedBudgetForMonthProvider =
    Provider.family<int, ({int year, int month})>((ref, period) {
  // Templates straight from Drift (issue #69), not from the list screen.
  final templates = ref.watch(activeRecurringTemplatesProvider).valueOrNull ??
      const <RecurringExpense>[];

  return BudgetCalculator.calculateReservedBudget(
    recurringExpenses: templates,
    month: period.month,
    year: period.year,
  );
});

/// Provider for current month's reserved budget
///
/// Feature 013-recurring-expenses - User Story 2 (T034)
///
/// Calculates the total budget reserved by active recurring expenses
/// for the current month. This amount represents future commitments
/// that should be subtracted from available budget.
final currentMonthReservedBudgetProvider = Provider<int>((ref) {
  final now = DateTime.now();
  return ref.watch(
    reservedBudgetForMonthProvider((year: now.year, month: now.month)),
  );
});

/// Provider for budget breakdown including reservations
///
/// Feature 013-recurring-expenses - User Story 2
///
/// Provides detailed budget breakdown for a specific category including:
/// - Total budget
/// - Amount spent
/// - Amount reserved
/// - Amount reimbursed
/// - Available budget
/// - Percentage used
final budgetBreakdownProvider = FutureProvider.family<Map<String, dynamic>, String>(
  (ref, categoryId) async {
    // TODO: Implement budget breakdown for specific category
    // This will require:
    // 1. Get category budget from budget repository
    // 2. Get spent amount from expenses
    // 3. Get reimbursed amount from expenses
    // 4. Get reserved amount from recurring expenses for this category
    // 5. Calculate breakdown using BudgetCalculator.getBudgetBreakdown

    return {
      'totalBudget': 0,
      'spentAmount': 0,
      'reservedBudget': 0,
      'reimbursedIncome': 0,
      'availableBudget': 0,
      'percentageUsed': 0.0,
    };
  },
);
