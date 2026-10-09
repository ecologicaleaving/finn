import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:family_expense_tracker/core/enums/recurrence_frequency.dart';
import 'package:family_expense_tracker/core/enums/reimbursement_status.dart';
import 'package:family_expense_tracker/features/budgets/presentation/providers/budget_reservation_provider.dart';
import 'package:family_expense_tracker/features/expenses/domain/entities/recurring_expense.dart';
import 'package:family_expense_tracker/features/expenses/presentation/providers/recurring_expense_provider.dart';

RecurringExpense _monthlyTemplate({
  required DateTime anchorDate,
  double amount = 50.0,
}) {
  return RecurringExpense(
    id: 'rec-1',
    userId: 'user-1',
    groupId: 'group-1',
    amount: amount,
    categoryId: 'cat-1',
    categoryName: 'Affitto',
    isGroupExpense: true,
    frequency: RecurrenceFrequency.monthly,
    anchorDate: anchorDate,
    isPaused: false,
    budgetReservationEnabled: true,
    defaultReimbursementStatus: ReimbursementStatus.none,
    createdAt: anchorDate,
    updatedAt: anchorDate,
  );
}

// Issue #69: the reservation reads the templates from Drift
// (activeRecurringTemplatesProvider), not from the list screen state.
Future<ProviderContainer> _containerWith(List<RecurringExpense> templates) async {
  final container = ProviderContainer(
    overrides: [
      activeRecurringTemplatesProvider
          .overrideWith((ref) => Stream.value(templates)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(activeRecurringTemplatesProvider.future);
  return container;
}

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('UTC'));
  });

  group('reservedBudgetForMonthProvider (issue #50)', () {
    test('uses the requested month instead of DateTime.now()', () async {
      // Monthly template anchored on 15 Jan 2030, first occurrence not yet
      // generated: counted in January and in the following months.
      final container = await _containerWith(
          [_monthlyTemplate(anchorDate: DateTime(2030, 1, 15))]);

      final beforeAnchor = container
          .read(reservedBudgetForMonthProvider((year: 2029, month: 12)));
      final dueMonth = container
          .read(reservedBudgetForMonthProvider((year: 2030, month: 2)));

      expect(beforeAnchor, 0);
      expect(
        container.read(reservedBudgetForMonthProvider((year: 2030, month: 1))),
        5000,
      );
      expect(dueMonth, 5000); // 50 EUR in cents
      expect(dueMonth, isNot(beforeAnchor));

      // The current month (2026) is not the due month: the "current month"
      // provider must not return the reservation for Feb 2030.
      expect(container.read(currentMonthReservedBudgetProvider), 0);
    });

    test('handles the December -> January year boundary', () async {
      // Anchored on 15 Dec 2030: 15 Dec 2030, then 15 Jan 2031.
      final container = await _containerWith(
          [_monthlyTemplate(anchorDate: DateTime(2030, 12, 15))]);

      expect(
        container.read(reservedBudgetForMonthProvider((year: 2030, month: 12))),
        5000,
      );
      expect(
        container.read(reservedBudgetForMonthProvider((year: 2031, month: 1))),
        5000,
      );
    });

    test('returns 0 when there are no recurring expenses', () async {
      final container = await _containerWith(const []);

      expect(
        container.read(reservedBudgetForMonthProvider((year: 2030, month: 2))),
        0,
      );
    });
  });
}
