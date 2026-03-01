import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/budget_calculator.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../groups/presentation/providers/group_provider.dart';
import '../../../expenses/presentation/providers/recurring_expense_provider.dart';

/// Provider for current month's reserved budget
///
/// Feature 013-recurring-expenses - User Story 2 (T034)
///
/// Calculates the total budget reserved by active recurring expenses
/// for the current month. This amount represents future commitments
/// that should be subtracted from available budget.
final currentMonthReservedBudgetProvider = Provider<int>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  final groupId = ref.watch(currentGroupIdProvider);

  // Get current month and year
  final now = DateTime.now();
  final month = now.month;
  final year = now.year;

  // Get all recurring expenses for the user
  final recurringExpensesState = ref.watch(recurringExpenseListProvider);

  // Calculate total reserved budget for current month
  return BudgetCalculator.calculateReservedBudget(
    recurringExpenses: recurringExpensesState.templates,
    month: month,
    year: year,
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
