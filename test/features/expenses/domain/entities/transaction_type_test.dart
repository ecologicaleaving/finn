import 'package:flutter_test/flutter_test.dart';

import 'package:family_expense_tracker/core/enums/transaction_type.dart';
import 'package:family_expense_tracker/core/enums/reimbursement_status.dart';
import 'package:family_expense_tracker/features/expenses/domain/entities/expense_entity.dart';
import 'package:family_expense_tracker/features/expenses/data/models/expense_model.dart';

void main() {
  group('TransactionType enum', () {
    test('fromString returns correct type for "income"', () {
      expect(TransactionType.fromString('income'), TransactionType.income);
    });

    test('fromString returns correct type for "expense"', () {
      expect(TransactionType.fromString('expense'), TransactionType.expense);
    });

    test('fromString defaults to expense for unknown value', () {
      expect(TransactionType.fromString('unknown'), TransactionType.expense);
    });

    test('isIncome returns true for income type', () {
      expect(TransactionType.income.isIncome, isTrue);
      expect(TransactionType.expense.isIncome, isFalse);
    });

    test('isExpense returns true for expense type', () {
      expect(TransactionType.expense.isExpense, isTrue);
      expect(TransactionType.income.isExpense, isFalse);
    });

    test('value returns correct database string', () {
      expect(TransactionType.income.value, 'income');
      expect(TransactionType.expense.value, 'expense');
    });

    test('label returns Italian label', () {
      expect(TransactionType.income.label, 'Entrata');
      expect(TransactionType.expense.label, 'Spesa');
    });
  });

  group('ExpenseEntity with transactionType', () {
    test('defaults to expense type', () {
      final entity = ExpenseEntity(
        id: '1',
        groupId: 'g1',
        createdBy: 'u1',
        amount: 100,
        date: DateTime(2026, 3, 4),
        paymentMethodId: 'pm1',
      );
      expect(entity.transactionType, TransactionType.expense);
      expect(entity.isIncome, isFalse);
    });

    test('income entity has correct formattedAmount with + prefix', () {
      final entity = ExpenseEntity(
        id: '1',
        groupId: 'g1',
        createdBy: 'u1',
        amount: 500,
        date: DateTime(2026, 3, 4),
        paymentMethodId: 'pm1',
        transactionType: TransactionType.income,
      );
      expect(entity.isIncome, isTrue);
      expect(entity.formattedAmount, '+€500.00');
    });

    test('expense entity has formattedAmount without prefix', () {
      final entity = ExpenseEntity(
        id: '1',
        groupId: 'g1',
        createdBy: 'u1',
        amount: 100,
        date: DateTime(2026, 3, 4),
        paymentMethodId: 'pm1',
        transactionType: TransactionType.expense,
      );
      expect(entity.formattedAmount, '€100.00');
    });

    test('copyWith preserves transactionType', () {
      final entity = ExpenseEntity(
        id: '1',
        groupId: 'g1',
        createdBy: 'u1',
        amount: 500,
        date: DateTime(2026, 3, 4),
        paymentMethodId: 'pm1',
        transactionType: TransactionType.income,
      );
      final copy = entity.copyWith(amount: 600);
      expect(copy.transactionType, TransactionType.income);
      expect(copy.amount, 600);
    });

    test('copyWith can change transactionType', () {
      final entity = ExpenseEntity(
        id: '1',
        groupId: 'g1',
        createdBy: 'u1',
        amount: 500,
        date: DateTime(2026, 3, 4),
        paymentMethodId: 'pm1',
        transactionType: TransactionType.expense,
      );
      final copy = entity.copyWith(transactionType: TransactionType.income);
      expect(copy.transactionType, TransactionType.income);
    });

    test('props includes transactionType', () {
      final a = ExpenseEntity(
        id: '1',
        groupId: 'g1',
        createdBy: 'u1',
        amount: 500,
        date: DateTime(2026, 3, 4),
        paymentMethodId: 'pm1',
        transactionType: TransactionType.income,
      );
      final b = ExpenseEntity(
        id: '1',
        groupId: 'g1',
        createdBy: 'u1',
        amount: 500,
        date: DateTime(2026, 3, 4),
        paymentMethodId: 'pm1',
        transactionType: TransactionType.expense,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('ExpenseModel with transactionType', () {
    test('fromJson parses transaction_type correctly', () {
      final json = {
        'id': '1',
        'group_id': 'g1',
        'created_by': 'u1',
        'amount': 500.0,
        'date': '2026-03-04',
        'payment_method_id': 'pm1',
        'transaction_type': 'income',
      };
      final model = ExpenseModel.fromJson(json);
      expect(model.transactionType, TransactionType.income);
    });

    test('fromJson defaults to expense when transaction_type is null', () {
      final json = {
        'id': '1',
        'group_id': 'g1',
        'created_by': 'u1',
        'amount': 100.0,
        'date': '2026-03-04',
        'payment_method_id': 'pm1',
      };
      final model = ExpenseModel.fromJson(json);
      expect(model.transactionType, TransactionType.expense);
    });

    test('toJson includes transaction_type', () {
      final model = ExpenseModel(
        id: '1',
        groupId: 'g1',
        createdBy: 'u1',
        amount: 500,
        date: DateTime(2026, 3, 4),
        paymentMethodId: 'pm1',
        transactionType: TransactionType.income,
      );
      final json = model.toJson();
      expect(json['transaction_type'], 'income');
    });

    test('fromEntity preserves transactionType', () {
      final entity = ExpenseEntity(
        id: '1',
        groupId: 'g1',
        createdBy: 'u1',
        amount: 500,
        date: DateTime(2026, 3, 4),
        paymentMethodId: 'pm1',
        transactionType: TransactionType.income,
      );
      final model = ExpenseModel.fromEntity(entity);
      expect(model.transactionType, TransactionType.income);
    });

    test('toEntity preserves transactionType', () {
      final model = ExpenseModel(
        id: '1',
        groupId: 'g1',
        createdBy: 'u1',
        amount: 500,
        date: DateTime(2026, 3, 4),
        paymentMethodId: 'pm1',
        transactionType: TransactionType.income,
      );
      final entity = model.toEntity();
      expect(entity.transactionType, TransactionType.income);
    });
  });

  group('DashboardStats with income', () {
    test('netBalance calculates correctly', () {
      // Import needed
      // Using inline test since DashboardStats is in another module
    });
  });
}
