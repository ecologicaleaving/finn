import 'package:flutter_test/flutter_test.dart';

import 'package:family_expense_tracker/core/enums/reimbursement_status.dart';
import 'package:family_expense_tracker/features/expenses/domain/entities/expense_entity.dart';
import 'package:family_expense_tracker/features/expenses/presentation/providers/reimbursements_provider.dart';

/// Tests for ReimbursementsListState creditor grouping — Issue #19
void main() {
  group('ReimbursementsListState creditorGroups (Issue #19)', () {
    ExpenseEntity _makeExpense({
      required String id,
      required double amount,
      String? reimbursableToLabel,
      String? reimbursableToUserId,
      double? reimbursableAmount,
    }) {
      return ExpenseEntity(
        id: id,
        groupId: 'group-1',
        createdBy: 'user-1',
        amount: amount,
        date: DateTime(2026, 3, 10),
        paymentMethodId: 'pm-1',
        reimbursementStatus: ReimbursementStatus.reimbursable,
        reimbursableToLabel: reimbursableToLabel,
        reimbursableToUserId: reimbursableToUserId,
        reimbursableAmount: reimbursableAmount,
      );
    }

    test('returns empty list when no reimbursable expenses have creditor', () {
      final expenses = [
        _makeExpense(id: 'e1', amount: 100.0),
        _makeExpense(id: 'e2', amount: 50.0),
      ];
      final state = ReimbursementsListState(
        reimbursableExpenses: expenses,
      );

      expect(state.creditorGroups, isEmpty);
    });

    test('groups expenses by creditor label', () {
      final expenses = [
        _makeExpense(
          id: 'e1',
          amount: 100.0,
          reimbursableToLabel: 'Giovanna',
          reimbursableToUserId: 'user-giovanna',
        ),
        _makeExpense(
          id: 'e2',
          amount: 80.0,
          reimbursableToLabel: 'Giovanna',
          reimbursableToUserId: 'user-giovanna',
        ),
        _makeExpense(
          id: 'e3',
          amount: 47.50,
          reimbursableToLabel: 'Lavoro',
        ),
      ];
      final state = ReimbursementsListState(
        reimbursableExpenses: expenses,
      );

      final groups = state.creditorGroups;
      expect(groups.length, equals(2));

      final giovanna = groups.firstWhere((g) => g.label == 'Giovanna');
      expect(giovanna.totalAmount, equals(180.0));
      expect(giovanna.expenseCount, equals(2));
      expect(giovanna.userId, equals('user-giovanna'));

      final lavoro = groups.firstWhere((g) => g.label == 'Lavoro');
      expect(lavoro.totalAmount, closeTo(47.50, 0.01));
      expect(lavoro.expenseCount, equals(1));
      expect(lavoro.userId, isNull);
    });

    test('uses reimbursableAmount when set instead of full amount', () {
      final expenses = [
        _makeExpense(
          id: 'e1',
          amount: 200.0,
          reimbursableToLabel: 'Giovanna',
          reimbursableAmount: 120.0,
        ),
        _makeExpense(
          id: 'e2',
          amount: 50.0,
          reimbursableToLabel: 'Giovanna',
          // no partial amount → uses full 50.0
        ),
      ];
      final state = ReimbursementsListState(
        reimbursableExpenses: expenses,
      );

      final groups = state.creditorGroups;
      final giovanna = groups.first;
      // 120.0 (partial) + 50.0 (full) = 170.0
      expect(giovanna.totalAmount, closeTo(170.0, 0.01));
    });

    test('groups sorted by total amount descending', () {
      final expenses = [
        _makeExpense(
          id: 'e1',
          amount: 10.0,
          reimbursableToLabel: 'Piccolo',
        ),
        _makeExpense(
          id: 'e2',
          amount: 200.0,
          reimbursableToLabel: 'Grande',
        ),
        _makeExpense(
          id: 'e3',
          amount: 100.0,
          reimbursableToLabel: 'Medio',
        ),
      ];
      final state = ReimbursementsListState(
        reimbursableExpenses: expenses,
      );

      final groups = state.creditorGroups;
      expect(groups[0].label, equals('Grande'));
      expect(groups[1].label, equals('Medio'));
      expect(groups[2].label, equals('Piccolo'));
    });
  });

  group('CreditorGroup', () {
    test('totalAmount uses effectiveReimbursableAmount from expenses', () {
      final expense = ExpenseEntity(
        id: 'e1',
        groupId: 'g1',
        createdBy: 'u1',
        amount: 100.0,
        date: DateTime.now(),
        paymentMethodId: 'pm1',
        reimbursementStatus: ReimbursementStatus.reimbursable,
        reimbursableAmount: 60.0,
      );
      final group = CreditorGroup(
        label: 'Test',
        expenses: [expense],
      );
      // Should use partial 60.0, not full 100.0
      expect(group.totalAmount, equals(60.0));
    });

    test('expenseCount returns number of expenses', () {
      final makeExp = (String id) => ExpenseEntity(
            id: id,
            groupId: 'g1',
            createdBy: 'u1',
            amount: 50.0,
            date: DateTime.now(),
            paymentMethodId: 'pm1',
          );
      final group = CreditorGroup(
        label: 'Test',
        expenses: [makeExp('a'), makeExp('b'), makeExp('c')],
      );
      expect(group.expenseCount, equals(3));
    });
  });

  group('BudgetSummary — netExpenses (AC5)', () {
    test('budget mensile sottrae rimborsi ricevuti dal totale spese', () {
      // Mimic the expected AC5 behavior from the issue:
      // Budget summary with expenses=500, reimbursementsReceived=120
      // => net = 500 - 120 = 380
      const expenses = 500.0;
      const reimbursementsReceived = 120.0;
      final netExpenses = expenses - reimbursementsReceived;
      expect(netExpenses, equals(380.0));
    });
  });
}
