import 'package:family_expense_tracker/core/enums/reimbursement_status.dart';
import 'package:family_expense_tracker/features/expenses/domain/entities/expense_entity.dart';
import 'package:family_expense_tracker/features/expenses/presentation/screens/expense_edit_changes.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = 'admin-1';

ExpenseEntity _expense({
  bool isGroupExpense = true,
  String? paidBy = _me,
  String createdBy = _me,
}) {
  return ExpenseEntity(
    id: 'e1',
    groupId: 'g1',
    createdBy: createdBy,
    amount: 20,
    date: DateTime(2026, 9, 20),
    categoryId: 'c1',
    paymentMethodId: 'pm1',
    isGroupExpense: isGroupExpense,
    notes: 'nota',
    paidBy: paidBy,
  );
}

ExpenseEditChanges _compute(
  ExpenseEntity original, {
  bool? isGroupExpense,
  String? selectedMemberId,
  double? amount,
}) {
  return ExpenseEditChanges.compute(
    original: original,
    currentUserId: _me,
    amount: amount ?? original.amount,
    date: original.date,
    categoryId: original.categoryId,
    paymentMethodId: original.paymentMethodId,
    notes: original.notes ?? '',
    reimbursementStatus: original.reimbursementStatus,
    isGroupExpense: isGroupExpense ?? original.isGroupExpense,
    selectedMemberId: selectedMemberId,
  );
}

void main() {
  group('ExpenseEditChanges.compute (issue #48)', () {
    test('no change produces an empty diff', () {
      final changes = _compute(_expense());
      expect(changes.amount, isNull);
      expect(changes.date, isNull);
      expect(changes.categoryId, isNull);
      expect(changes.paymentMethodId, isNull);
      expect(changes.notes, isNull);
      expect(changes.reimbursementStatus, isNull);
      expect(changes.isGroupExpense, isNull);
      expect(changes.paidBy, isNull);
    });

    test('toggle changed sets isGroupExpense (AC3)', () {
      final changes = _compute(_expense(), isGroupExpense: false);
      expect(changes.isGroupExpense, false);
      expect(changes.paidBy, isNull);
    });

    test('toggle unchanged leaves isGroupExpense null', () {
      final changes = _compute(_expense(isGroupExpense: false),
          isGroupExpense: false);
      expect(changes.isGroupExpense, isNull);
    });

    test('selector changed to another member sets paidBy (AC4)', () {
      final changes = _compute(_expense(), selectedMemberId: 'member-2');
      expect(changes.paidBy, 'member-2');
    });

    test('Me stesso on an expense paid by someone else sets paidBy = me', () {
      final changes =
          _compute(_expense(paidBy: 'member-2'), selectedMemberId: null);
      expect(changes.paidBy, _me);
    });

    test('expense paid by me with selector null does not change paidBy', () {
      final changes = _compute(_expense(paidBy: _me), selectedMemberId: null);
      expect(changes.paidBy, isNull);
    });

    test('same member selected again does not change paidBy', () {
      final changes = _compute(_expense(paidBy: 'member-2'),
          selectedMemberId: 'member-2');
      expect(changes.paidBy, isNull);
    });

    test('legacy expense without paidBy falls back to createdBy', () {
      final changes = _compute(_expense(paidBy: null, createdBy: _me));
      expect(changes.paidBy, isNull);
    });

    test('member and classification change together are both sent', () {
      final changes = _compute(_expense(isGroupExpense: false),
          isGroupExpense: true, selectedMemberId: 'member-2', amount: 30);
      expect(changes.isGroupExpense, true);
      expect(changes.paidBy, 'member-2');
      expect(changes.amount, 30);
    });

    test('reimbursement status change is detected', () {
      final original = _expense();
      final changes = ExpenseEditChanges.compute(
        original: original,
        currentUserId: _me,
        amount: original.amount,
        date: original.date,
        categoryId: original.categoryId,
        paymentMethodId: original.paymentMethodId,
        notes: 'nota',
        reimbursementStatus: ReimbursementStatus.reimbursable,
        isGroupExpense: original.isGroupExpense,
        selectedMemberId: null,
      );
      expect(changes.reimbursementStatus, ReimbursementStatus.reimbursable);
    });
  });

  group('ExpenseEditChanges.initialSelectedMemberId (AC4 pre-fill)', () {
    test('paid by current user maps to null (Me stesso)', () {
      expect(
        ExpenseEditChanges.initialSelectedMemberId(_expense(paidBy: _me), _me),
        isNull,
      );
    });

    test('paid by another member maps to that member, not createdBy', () {
      expect(
        ExpenseEditChanges.initialSelectedMemberId(
          _expense(paidBy: 'member-2', createdBy: _me),
          _me,
        ),
        'member-2',
      );
    });

    test('legacy expense without paidBy uses createdBy', () {
      expect(
        ExpenseEditChanges.initialSelectedMemberId(
          _expense(paidBy: null, createdBy: 'member-3'),
          _me,
        ),
        'member-3',
      );
    });
  });
}
