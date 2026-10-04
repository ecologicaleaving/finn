import 'package:family_expense_tracker/core/enums/transaction_type.dart';
import 'package:family_expense_tracker/features/expenses/data/datasources/expense_remote_datasource.dart';
import 'package:family_expense_tracker/features/expenses/data/models/expense_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('date payload (issue #66)', () {
    test('buildUpdatePayload keeps the local day just after midnight', () {
      final payload = ExpenseRemoteDataSourceImpl.buildUpdatePayload(
        date: DateTime(2026, 10, 4, 0, 30),
      );
      expect(payload['date'], '2026-10-04');
    });

    test('buildTimestampUpdatePayload keeps the local day', () {
      final payload = ExpenseRemoteDataSourceImpl.buildTimestampUpdatePayload(
        lastModifiedBy: 'u1',
        date: DateTime(2026, 10, 4, 0, 30),
      );
      expect(payload['date'], '2026-10-04');
    });

    test('ExpenseModel.toJson keeps the local day', () {
      final model = ExpenseModel(
        id: '1',
        groupId: 'g1',
        createdBy: 'u1',
        amount: 500,
        date: DateTime(2026, 10, 4, 0, 30),
        paymentMethodId: 'pm1',
        transactionType: TransactionType.expense,
      );
      expect(model.toJson()['date'], '2026-10-04');
    });
  });
}
