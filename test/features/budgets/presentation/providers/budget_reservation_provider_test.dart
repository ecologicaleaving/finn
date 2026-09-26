import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:family_expense_tracker/core/enums/recurrence_frequency.dart';
import 'package:family_expense_tracker/core/enums/reimbursement_status.dart';
import 'package:family_expense_tracker/features/budgets/presentation/providers/budget_reservation_provider.dart';
import 'package:family_expense_tracker/features/expenses/domain/entities/recurring_expense.dart';
import 'package:family_expense_tracker/features/expenses/domain/repositories/recurring_expense_repository.dart';
import 'package:family_expense_tracker/features/expenses/presentation/providers/recurring_expense_provider.dart';

class _FakeRecurringExpenseRepository implements RecurringExpenseRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRecurringExpenseListNotifier extends RecurringExpenseListNotifier {
  _FakeRecurringExpenseListNotifier(List<RecurringExpense> templates)
      : super(_FakeRecurringExpenseRepository()) {
    state = RecurringExpenseListState(
      status: RecurringExpenseListStatus.loaded,
      templates: templates,
    );
  }
}

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

ProviderContainer _containerWith(List<RecurringExpense> templates) {
  final container = ProviderContainer(
    overrides: [
      recurringExpenseListProvider.overrideWith(
        (ref) => _FakeRecurringExpenseListNotifier(templates),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('UTC'));
  });

  group('reservedBudgetForMonthProvider (issue #50)', () {
    test('uses the requested month instead of DateTime.now()', () {
      // Monthly template anchored on 15 Jan 2030: next due date 15 Feb 2030.
      final container =
          _containerWith([_monthlyTemplate(anchorDate: DateTime(2030, 1, 15))]);

      final beforeDue = container
          .read(reservedBudgetForMonthProvider((year: 2030, month: 1)));
      final dueMonth = container
          .read(reservedBudgetForMonthProvider((year: 2030, month: 2)));

      expect(beforeDue, 0);
      expect(dueMonth, 5000); // 50 EUR in cents
      expect(dueMonth, isNot(beforeDue));

      // The current month (2026) is not the due month: the "current month"
      // provider must not return the reservation for Feb 2030.
      expect(container.read(currentMonthReservedBudgetProvider), 0);
    });

    test('handles the December -> January year boundary', () {
      // Anchored on 15 Dec 2030: next due date 15 Jan 2031.
      final container =
          _containerWith([_monthlyTemplate(anchorDate: DateTime(2030, 12, 15))]);

      expect(
        container.read(reservedBudgetForMonthProvider((year: 2030, month: 12))),
        0,
      );
      expect(
        container.read(reservedBudgetForMonthProvider((year: 2031, month: 1))),
        5000,
      );
    });

    test('returns 0 when there are no recurring expenses', () {
      final container = _containerWith(const []);

      expect(
        container.read(reservedBudgetForMonthProvider((year: 2030, month: 2))),
        0,
      );
    });
  });
}
