import '../../features/expenses/domain/entities/recurring_expense.dart';
import '../../features/expenses/domain/services/recurrence_calculator.dart';

/// Utility class for budget-related calculations
///
/// Handles budget math including percentage calculations, rounding,
/// and budget status determination
///
/// ## Monthly Budget Reset Behavior (Feature 004)
///
/// **IMPORTANT**: Budgets do NOT reset automatically via code or database triggers.
/// Instead, budget "reset" is achieved implicitly through date-based queries:
///
/// 1. **Budget Storage**: Each budget record stores `month` and `year` fields
///    (e.g., month=1, year=2026 for January 2026)
///
/// 2. **Implicit Reset**: When a new month begins:
///    - Queries filter by current month/year (via RPC functions)
///    - Previous month's spending automatically becomes inaccessible
///    - Budget amounts remain the same, but spent amounts start at 0
///
/// 3. **RPC Implementation**: Budget stats RPC functions use date-based queries:
///    ```sql
///    WHERE EXTRACT(MONTH FROM e.date) = p_month
///      AND EXTRACT(YEAR FROM e.date) = p_year
///    ```
///
/// 4. **Multi-Month Tracking**: Each month's budget is independent:
///    - January 2026 budget: €500 budgeted, €300 spent
///    - February 2026 budget: €500 budgeted, €0 spent (new month)
///    - Historical data remains queryable by specifying past month/year
///
/// 5. **Timezone Handling**: All date comparisons use UTC timezone to ensure
///    consistent month boundaries across different user timezones
///    (see [TimezoneHandler] for details)
///
/// This approach provides several benefits:
/// - No scheduled jobs or maintenance required
/// - Historical budget data preserved automatically
/// - Month boundaries handled correctly across timezones
/// - Query performance optimized via indexed date columns
class BudgetCalculator {
  /// Calculate spent amount from expense amounts (rounded up to whole euros)
  ///
  /// [expenseAmounts] - List of expense amounts (may include cents)
  ///
  /// Returns total spent amount rounded up to nearest whole euro
  static int calculateSpentAmount(List<double> expenseAmounts) {
    if (expenseAmounts.isEmpty) return 0;

    // Sum all expenses and round up to whole euro
    final total = expenseAmounts.fold<double>(
      0.0,
      (sum, amount) => sum + amount,
    );

    return total.ceil();
  }

  /// Calculate total reimbursed income from expenses in a given period
  ///
  /// T027: Feature 012-expense-improvements - User Story 3
  /// Sums up all expenses that have been marked as reimbursed.
  /// This amount should be treated as income in budget calculations.
  ///
  /// [expenses] - List of expenses to analyze
  ///
  /// Returns total reimbursed amount in cents
  static int calculateReimbursedIncome(List<dynamic> expenses) {
    if (expenses.isEmpty) return 0;

    return expenses.fold<int>(0, (sum, expense) {
      // Check if expense has reimbursement status and is reimbursed
      if (expense.reimbursementStatus?.value == 'reimbursed') {
        return (sum + (expense.amount * 100).round()) as int;
      }
      return sum;
    });
  }

  /// Calculate total pending reimbursements
  ///
  /// T028: Feature 012-expense-improvements - User Story 3
  /// Sums up all expenses marked as reimbursable (awaiting reimbursement).
  ///
  /// [expenses] - List of expenses to analyze
  ///
  /// Returns total pending reimbursement amount in cents
  static int calculatePendingReimbursements(List<dynamic> expenses) {
    if (expenses.isEmpty) return 0;

    return expenses.fold<int>(0, (sum, expense) {
      // Check if expense has reimbursement status and is reimbursable
      if (expense.reimbursementStatus?.value == 'reimbursable') {
        return (sum + (expense.amount * 100).round()) as int;
      }
      return sum;
    });
  }

  /// Calculate remaining budget amount with optional reimbursed income
  ///
  /// T029: Enhanced to include reimbursed income as additional available funds
  ///
  /// **Formula**: remainingAmount = budgetAmount - spentAmount + reimbursedIncome
  ///
  /// [budgetAmount] - Budget amount in whole euros
  /// [spentAmount] - Spent amount in whole euros
  /// [reimbursedIncome] - Amount reimbursed in cents (default: 0)
  ///
  /// Returns remaining amount (can be negative if over budget)
  static int calculateRemainingAmount(
    int budgetAmount,
    int spentAmount, {
    int reimbursedIncome = 0,
  }) {
    // Convert reimbursedIncome from cents to euros
    final reimbursedEuros = (reimbursedIncome / 100).round();
    return budgetAmount - spentAmount + reimbursedEuros;
  }

  /// Calculate budget usage percentage with optional reimbursed income
  ///
  /// T030: Enhanced to calculate netSpent (spent - reimbursed) for accurate percentage
  ///
  /// **Formula**: percentageUsed = (netSpent / budgetAmount) * 100
  /// where netSpent = spentAmount - reimbursedIncome
  ///
  /// [budgetAmount] - Budget amount in whole euros
  /// [spentAmount] - Spent amount in whole euros
  /// [reimbursedIncome] - Amount reimbursed in cents (default: 0)
  ///
  /// Returns percentage used (0-100+), or 0 if budget is 0
  static double calculatePercentageUsed(
    int budgetAmount,
    int spentAmount, {
    int reimbursedIncome = 0,
  }) {
    if (budgetAmount <= 0) return 0.0;

    // Convert reimbursedIncome from cents to euros and calculate net spent
    final reimbursedEuros = (reimbursedIncome / 100).round();
    final netSpent = spentAmount - reimbursedEuros;

    final percentage = (netSpent / budgetAmount) * 100;
    return double.parse(percentage.toStringAsFixed(2));
  }

  /// Check if budget is over (spent >= budget)
  ///
  /// [budgetAmount] - Budget amount in whole euros
  /// [spentAmount] - Spent amount in whole euros
  ///
  /// Returns true if spent amount equals or exceeds budget
  static bool isOverBudget(int budgetAmount, int spentAmount) {
    return spentAmount >= budgetAmount;
  }

  /// Check if budget is near limit (>= 80% used)
  ///
  /// [budgetAmount] - Budget amount in whole euros
  /// [spentAmount] - Spent amount in whole euros
  ///
  /// Returns true if 80% or more of budget is used
  static bool isNearLimit(int budgetAmount, int spentAmount) {
    if (budgetAmount <= 0) return false;

    final percentageUsed = calculatePercentageUsed(budgetAmount, spentAmount);
    return percentageUsed >= 80.0;
  }

  /// Get budget status as a string
  ///
  /// [budgetAmount] - Budget amount in whole euros
  /// [spentAmount] - Spent amount in whole euros
  ///
  /// Returns one of: 'healthy', 'warning', 'over_budget'
  static String getBudgetStatus(int budgetAmount, int spentAmount) {
    if (isOverBudget(budgetAmount, spentAmount)) {
      return 'over_budget';
    } else if (isNearLimit(budgetAmount, spentAmount)) {
      return 'warning';
    } else {
      return 'healthy';
    }
  }

  /// Format budget amount for display
  ///
  /// [amount] - Amount in whole euros
  ///
  /// Returns formatted string (e.g., "€1,234")
  static String formatAmount(int amount) {
    final absAmount = amount.abs();
    final isNegative = amount < 0;

    // Format with thousands separator
    final formatted = absAmount.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );

    return '${isNegative ? '-' : ''}€$formatted';
  }

  /// Calculate average daily spending rate
  ///
  /// [spentAmount] - Total spent in whole euros
  /// [daysPassed] - Number of days passed in budget period
  ///
  /// Returns average daily spending (can include cents)
  static double calculateDailyRate(int spentAmount, int daysPassed) {
    if (daysPassed <= 0) return 0.0;
    return spentAmount / daysPassed;
  }

  /// Project remaining budget until end of month
  ///
  /// [budgetAmount] - Budget amount in whole euros
  /// [spentAmount] - Spent amount in whole euros
  /// [daysPassed] - Days passed in current month
  /// [daysInMonth] - Total days in the month
  ///
  /// Returns projected remaining amount at month end (can be negative)
  static int projectMonthEnd(
    int budgetAmount,
    int spentAmount,
    int daysPassed,
    int daysInMonth,
  ) {
    if (daysPassed <= 0 || daysInMonth <= 0) return budgetAmount - spentAmount;

    final dailyRate = calculateDailyRate(spentAmount, daysPassed);
    final daysRemaining = daysInMonth - daysPassed;
    final projectedSpending = spentAmount + (dailyRate * daysRemaining);

    return budgetAmount - projectedSpending.ceil();
  }

  /// Validate budget amount
  ///
  /// [amount] - Budget amount to validate
  ///
  /// Returns error message if invalid, null if valid
  static String? validateBudgetAmount(int? amount) {
    if (amount == null) {
      return 'Budget amount is required';
    }

    if (amount < 0) {
      return 'Budget amount cannot be negative';
    }

    if (amount > 1000000) {
      return 'Budget amount cannot exceed €1,000,000';
    }

    return null; // Valid
  }

  /// Round expense amount up to whole euro
  ///
  /// [amount] - Expense amount (may include cents)
  ///
  /// Returns amount rounded up to nearest whole euro
  static int roundUpToWholeEuro(double amount) {
    return amount.ceil();
  }

  // ========== Budget Reservation Methods (Feature 013) ==========

  /// Calculate total reserved budget for recurring expenses
  ///
  /// T033: Feature 013-recurring-expenses - User Story 2
  ///
  /// Sums up budget reservations for all active recurring expenses
  /// that will occur in the specified month/year period.
  ///
  /// [recurringExpenses] - List of recurring expense templates
  /// [month] - Budget period month (1-12)
  /// [year] - Budget period year
  ///
  /// Returns total reserved amount in cents
  static int calculateReservedBudget({
    required List<RecurringExpense> recurringExpenses,
    required int month,
    required int year,
  }) {
    return recurringExpenses.fold<int>(0, (sum, template) {
      // Skip paused templates or templates without budget reservation
      if (template.isPaused || !template.budgetReservationEnabled) {
        return sum;
      }

      final reservation = RecurrenceCalculator.calculateBudgetReservation(
        template: template,
        month: month,
        year: year,
      );
      return sum + reservation;
    });
  }

  /// Calculate available budget after accounting for reservations
  ///
  /// T033: Feature 013-recurring-expenses - User Story 2
  ///
  /// Formula: available = total - spent - reserved + reimbursed
  ///
  /// [budgetAmount] - Total budget in euros
  /// [spentAmount] - Amount spent in euros
  /// [reservedBudget] - Amount reserved for recurring expenses in cents
  /// [reimbursedIncome] - Amount reimbursed in cents (default: 0)
  ///
  /// Returns available budget in euros (can be negative)
  static int calculateAvailableBudget({
    required int budgetAmount,
    required int spentAmount,
    required int reservedBudget,
    int reimbursedIncome = 0,
  }) {
    // Convert cents to euros
    final reservedEuros = (reservedBudget / 100).round();
    final reimbursedEuros = (reimbursedIncome / 100).round();

    return budgetAmount - spentAmount - reservedEuros + reimbursedEuros;
  }

  /// Get detailed budget breakdown including reservations
  ///
  /// T033: Feature 013-recurring-expenses - User Story 2
  ///
  /// Provides comprehensive budget breakdown for UI display.
  ///
  /// [budgetAmount] - Total budget in euros
  /// [spentAmount] - Amount spent in euros
  /// [reservedBudget] - Amount reserved in cents
  /// [reimbursedIncome] - Amount reimbursed in cents (default: 0)
  ///
  /// Returns map with budget breakdown:
  /// - totalBudget: Total budget in euros
  /// - spentAmount: Amount spent in euros
  /// - reservedBudget: Amount reserved in euros
  /// - reimbursedIncome: Amount reimbursed in euros
  /// - availableBudget: Remaining available in euros
  /// - percentageUsed: Percentage of budget used (spent + reserved - reimbursed)
  static Map<String, dynamic> getBudgetBreakdown({
    required int budgetAmount,
    required int spentAmount,
    required int reservedBudget,
    int reimbursedIncome = 0,
  }) {
    // Convert cents to euros
    final reservedEuros = (reservedBudget / 100).round();
    final reimbursedEuros = (reimbursedIncome / 100).round();

    final available = calculateAvailableBudget(
      budgetAmount: budgetAmount,
      spentAmount: spentAmount,
      reservedBudget: reservedBudget,
      reimbursedIncome: reimbursedIncome,
    );

    // Calculate percentage: (spent + reserved - reimbursed) / total * 100
    final totalCommitted = spentAmount + reservedEuros - reimbursedEuros;
    final percentageUsed = budgetAmount > 0
        ? (totalCommitted / budgetAmount * 100).clamp(0.0, 999.9)
        : 0.0;

    return {
      'totalBudget': budgetAmount,
      'spentAmount': spentAmount,
      'reservedBudget': reservedEuros,
      'reimbursedIncome': reimbursedEuros,
      'availableBudget': available,
      'percentageUsed': double.parse(percentageUsed.toStringAsFixed(2)),
    };
  }
}
