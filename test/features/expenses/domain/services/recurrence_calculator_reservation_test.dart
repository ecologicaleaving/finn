import 'package:family_expense_tracker/core/enums/recurrence_frequency.dart';
import 'package:family_expense_tracker/core/enums/reimbursement_status.dart';
import 'package:family_expense_tracker/features/expenses/domain/entities/recurring_expense.dart';
import 'package:family_expense_tracker/features/expenses/domain/services/recurrence_calculator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// Issue #69 - AC5: budget reservation counts the first occurrence and every
// not-yet-generated occurrence in the month.

RecurringExpense _template({
  required DateTime anchor,
  DateTime? nextDue,
  RecurrenceFrequency frequency = RecurrenceFrequency.monthly,
  bool paused = false,
  bool reservation = true,
  double amount = 50,
}) {
  return RecurringExpense(
    id: 'r1',
    userId: 'u1',
    amount: amount,
    categoryId: 'c1',
    categoryName: 'Casa',
    isGroupExpense: true,
    frequency: frequency,
    anchorDate: anchor,
    isPaused: paused,
    nextDueDate: nextDue,
    budgetReservationEnabled: reservation,
    defaultReimbursementStatus: ReimbursementStatus.none,
    createdAt: anchor,
    updatedAt: anchor,
  );
}

DateTime _d(int y, int m, int d) => tz.TZDateTime(tz.local, y, m, d, 12);

int _reserve(RecurringExpense t, int year, int month) =>
    RecurrenceCalculator.calculateBudgetReservation(
        template: t, month: month, year: year);

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Rome'));
  });

  test('first occurrence (anchor) is counted', () {
    final t = _template(anchor: _d(2030, 1, 15));
    expect(_reserve(t, 2030, 1), 5000);
    expect(_reserve(t, 2030, 2), 5000);
  });

  test('months before the next due date are not reserved', () {
    final t = _template(
      anchor: _d(2030, 1, 15),
      nextDue: _d(2030, 3, 15),
    );
    expect(_reserve(t, 2030, 2), 0);
    expect(_reserve(t, 2030, 3), 5000);
  });

  test('weekly template reserves 4 or 5 times a month', () {
    // Wednesdays: October 2026 has 1, 8, 15, 22, 29 -> 5 occurrences
    final t = _template(
      anchor: _d(2026, 10, 7),
      frequency: RecurrenceFrequency.weekly,
      amount: 10,
    );
    expect(_reserve(t, 2026, 10), 4000); // 7, 14, 21, 28
    final t2 = _template(
      anchor: _d(2026, 10, 1),
      frequency: RecurrenceFrequency.weekly,
      amount: 10,
    );
    expect(_reserve(t2, 2026, 10), 5000); // 1, 8, 15, 22, 29
  });

  test('only occurrences from nextDueDate on count in the current month', () {
    final t = _template(
      anchor: _d(2026, 10, 1),
      nextDue: _d(2026, 10, 15),
      frequency: RecurrenceFrequency.weekly,
      amount: 10,
    );
    expect(_reserve(t, 2026, 10), 3000); // 15, 22, 29
  });

  test('period bounds are inclusive', () {
    final first = _template(anchor: tz.TZDateTime(tz.local, 2030, 5, 1));
    final last = _template(
      anchor: tz.TZDateTime(tz.local, 2030, 5, 31, 23, 59),
    );
    expect(_reserve(first, 2030, 5), 5000);
    expect(_reserve(last, 2030, 5), 5000);
  });

  test('paused, reservation disabled: 0', () {
    expect(_reserve(_template(anchor: _d(2030, 1, 15), paused: true), 2030, 1), 0);
    expect(
      _reserve(_template(anchor: _d(2030, 1, 15), reservation: false), 2030, 1),
      0,
    );
  });
}
