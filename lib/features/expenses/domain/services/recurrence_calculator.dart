import 'package:timezone/timezone.dart' as tz;

import '../../../../core/enums/recurrence_frequency.dart';
import '../entities/recurring_expense.dart';

/// Domain service for calculating recurring expense due dates and budget reservations.
///
/// Provides pure functions for:
/// - Calculating next occurrence dates from anchor dates
/// - Handling edge cases (month-end, leap years)
/// - Calculating budget reservations for periods
class RecurrenceCalculator {
  /// Calculate the next occurrence date from an anchor date.
  ///
  /// [anchorDate] - Original date when recurring expense was created
  /// [frequency] - Recurrence frequency (daily/weekly/monthly/yearly)
  /// [lastCreated] - Last time an instance was created (null for first occurrence)
  ///
  /// Returns next due date in user's local timezone, or null if calculation fails.
  ///
  /// Edge cases handled:
  /// - Month-end (Jan 31 → Feb 28/29): Uses last day of shorter month
  /// - Leap year (Feb 29 → Feb 28): Uses last day of non-leap year
  /// - Weekly: Always exactly 7 days
  /// - Daily: Always exactly 24 hours
  static DateTime? calculateNextDueDate({
    required DateTime anchorDate,
    required RecurrenceFrequency frequency,
    DateTime? lastCreated,
  }) {
    try {
      // Convert to timezone-aware datetime
      final anchor = tz.TZDateTime.from(anchorDate, tz.local);
      final reference = lastCreated != null
          ? tz.TZDateTime.from(lastCreated, tz.local)
          : anchor;

      tz.TZDateTime nextDate;

      switch (frequency) {
        case RecurrenceFrequency.daily:
          nextDate = reference.add(const Duration(days: 1));
          break;

        case RecurrenceFrequency.weekly:
          nextDate = reference.add(const Duration(days: 7));
          break;

        case RecurrenceFrequency.monthly:
          // Handle month-end edge cases (Jan 31 → Feb 28/29)
          nextDate = _addMonths(reference, 1, anchor.day);
          break;

        case RecurrenceFrequency.yearly:
          // Handle leap year edge case (Feb 29 → Feb 28 in non-leap years)
          nextDate = _addYears(reference, 1, anchor.month, anchor.day);
          break;
      }

      return nextDate;
    } catch (e) {
      // Return null if calculation fails (shouldn't happen in normal cases)
      return null;
    }
  }

  /// Calculate total reserved budget for a recurring expense in a period.
  ///
  /// [template] - Recurring expense template
  /// [month] - Budget period month (1-12)
  /// [year] - Budget period year
  ///
  /// Returns reserved amount in cents (0 if not due in period or paused).
  ///
  /// Budget is reserved only if:
  /// - Template is active (not paused)
  /// - Budget reservation is enabled
  /// - Next due date falls within the period
  static int calculateBudgetReservation({
    required RecurringExpense template,
    required int month,
    required int year,
  }) {
    // Don't reserve if paused or reservation disabled
    if (template.isPaused || !template.budgetReservationEnabled) {
      return 0;
    }

    // Calculate period boundaries
    final periodStart = tz.TZDateTime(tz.local, year, month, 1);
    final periodEnd = tz.TZDateTime(tz.local, year, month + 1, 1)
        .subtract(const Duration(microseconds: 1));

    // Calculate next due date
    final nextDue = calculateNextDueDate(
      anchorDate: template.anchorDate,
      frequency: template.frequency,
      lastCreated: template.lastInstanceCreatedAt,
    );

    if (nextDue == null) return 0;

    // Check if due date falls within the period
    final nextDueTz = tz.TZDateTime.from(nextDue, tz.local);
    if (nextDueTz.isAfter(periodStart) && nextDueTz.isBefore(periodEnd)) {
      // Convert euros to cents
      return (template.amount * 100).round();
    }

    return 0;
  }

  /// Calculate total reserved budget for all recurring expenses in a period.
  ///
  /// [recurringExpenses] - List of recurring expense templates
  /// [month] - Budget period month (1-12)
  /// [year] - Budget period year
  ///
  /// Returns total reserved amount in cents.
  static int calculateTotalReservedBudget({
    required List<RecurringExpense> recurringExpenses,
    required int month,
    required int year,
  }) {
    if (recurringExpenses.isEmpty) return 0;

    return recurringExpenses.fold<int>(0, (sum, template) {
      final reservation = calculateBudgetReservation(
        template: template,
        month: month,
        year: year,
      );
      return sum + reservation;
    });
  }

  // =========================================================================
  // Private helper methods
  // =========================================================================

  /// Add months with day-of-month preservation.
  ///
  /// Handles edge case: if anchor day doesn't exist in target month,
  /// use the last day of that month (Jan 31 → Feb 28/29).
  static tz.TZDateTime _addMonths(
    tz.TZDateTime date,
    int months,
    int anchorDay,
  ) {
    final targetMonth = date.month + months;
    final targetYear = date.year + (targetMonth - 1) ~/ 12;
    final normalizedMonth = ((targetMonth - 1) % 12) + 1;

    // Get last day of target month
    final lastDayOfMonth = _lastDayOfMonth(targetYear, normalizedMonth);
    final day = anchorDay <= lastDayOfMonth ? anchorDay : lastDayOfMonth;

    return tz.TZDateTime(
      tz.local,
      targetYear,
      normalizedMonth,
      day,
      date.hour,
      date.minute,
      date.second,
    );
  }

  /// Add years with month/day preservation.
  ///
  /// Handles leap year edge case: Feb 29 → Feb 28 in non-leap years.
  static tz.TZDateTime _addYears(
    tz.TZDateTime date,
    int years,
    int anchorMonth,
    int anchorDay,
  ) {
    final targetYear = date.year + years;

    // Check if anchor day exists in target year's month
    final lastDayOfMonth = _lastDayOfMonth(targetYear, anchorMonth);
    final day = anchorDay <= lastDayOfMonth ? anchorDay : lastDayOfMonth;

    return tz.TZDateTime(
      tz.local,
      targetYear,
      anchorMonth,
      day,
      date.hour,
      date.minute,
      date.second,
    );
  }

  /// Get the last day of a given month.
  ///
  /// Handles month-end variations and leap years.
  static int _lastDayOfMonth(int year, int month) {
    // First day of next month minus 1 day
    final nextMonth = DateTime(year, month + 1, 1);
    final lastDay = nextMonth.subtract(const Duration(days: 1));
    return lastDay.day;
  }

  /// Check if two dates are on the same day (ignoring time).
  static bool isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  /// Check if a recurring expense is due now (for background task).
  ///
  /// Returns true if nextDueDate is today or earlier.
  static bool isDueNow(DateTime dueDate, DateTime now) {
    final dueDateLocal = tz.TZDateTime.from(dueDate, tz.local);
    final nowLocal = tz.TZDateTime.from(now, tz.local);

    // Due if scheduled for today or earlier
    return dueDateLocal.isBefore(nowLocal) || isSameDay(dueDateLocal, nowLocal);
  }
}
