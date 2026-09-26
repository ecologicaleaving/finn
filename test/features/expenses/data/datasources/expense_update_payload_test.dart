import 'package:family_expense_tracker/core/enums/reimbursement_status.dart';
import 'package:family_expense_tracker/features/expenses/data/datasources/expense_remote_datasource.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildTimestampUpdatePayload (issue #48)', () {
    test('always contains last_modified_by and nothing else by default', () {
      final payload = ExpenseRemoteDataSourceImpl.buildTimestampUpdatePayload(
        lastModifiedBy: 'u1',
      );
      expect(payload, {'last_modified_by': 'u1'});
    });

    test('isGroupExpense false is sent as is_group_expense (AC3)', () {
      final payload = ExpenseRemoteDataSourceImpl.buildTimestampUpdatePayload(
        lastModifiedBy: 'u1',
        isGroupExpense: false,
      );
      expect(payload['is_group_expense'], false);
      expect(payload.containsKey('paid_by'), isFalse);
      expect(payload.containsKey('paid_by_name'), isFalse);
    });

    test('paidBy is sent with paid_by_name (AC4)', () {
      final payload = ExpenseRemoteDataSourceImpl.buildTimestampUpdatePayload(
        lastModifiedBy: 'u1',
        paidBy: 'u2',
        paidByName: 'Maria',
      );
      expect(payload['paid_by'], 'u2');
      expect(payload['paid_by_name'], 'Maria');
      expect(payload.containsKey('is_group_expense'), isFalse);
    });

    test('paid_by_name falls back to Utente when the profile has no name', () {
      final payload = ExpenseRemoteDataSourceImpl.buildTimestampUpdatePayload(
        lastModifiedBy: 'u1',
        paidBy: 'u2',
      );
      expect(payload['paid_by_name'], 'Utente');
    });

    test('other fields are mapped as before', () {
      final payload = ExpenseRemoteDataSourceImpl.buildTimestampUpdatePayload(
        lastModifiedBy: 'u1',
        amount: 12.5,
        date: DateTime(2026, 9, 26, 15, 30),
        categoryId: 'c1',
        paymentMethodId: 'pm1',
        paymentMethodName: 'Carta',
        notes: 'nota',
        reimbursementStatus: ReimbursementStatus.reimbursable,
        isGroupExpense: true,
      );
      expect(payload, {
        'last_modified_by': 'u1',
        'amount': 12.5,
        'date': '2026-09-26',
        'category_id': 'c1',
        'payment_method_id': 'pm1',
        'payment_method_name': 'Carta',
        'notes': 'nota',
        'reimbursement_status': 'reimbursable',
        // #47: reimbursed_at always travels with the status
        'reimbursed_at': null,
        'is_group_expense': true,
      });
    });
  });
}
