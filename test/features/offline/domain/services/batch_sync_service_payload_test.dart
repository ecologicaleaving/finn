import 'package:family_expense_tracker/features/offline/domain/services/batch_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('buildCreateRow sends the local day for a payload just after midnight',
      () {
    final row = BatchSyncService.buildCreateRow(
      {
        'amount': 12.5,
        'date': '2026-10-04T00:30:00.000',
        'category_id': 'c1',
        'merchant': 'Bar',
        'notes': null,
      },
      id: 'e1',
      groupId: 'g1',
      createdBy: 'u1',
      createdByName: 'Anna',
      paidBy: 'u1',
      paidByName: 'Anna',
      paymentMethodId: 'pm1',
      paymentMethodName: 'Contanti',
    );

    expect(row['date'], '2026-10-04');
    expect(row['id'], 'e1');
    expect(row['group_id'], 'g1');
    expect(row['amount'], 12.5);
    expect(row['category_id'], 'c1');
    expect(row['payment_method_name'], 'Contanti');
    expect(row['is_group_expense'], true);
    expect(row['reimbursement_status'], 'none');
    expect(row['last_modified_by'], 'u1');
    expect(row.containsKey('transaction_type'), isFalse);
    expect(row.containsKey('created_at'), isFalse);
  });

  group('recurring instances (issue #69)', () {
    Map<String, dynamic> build(Map<String, dynamic> payload) =>
        BatchSyncService.buildCreateRow(
          {
            'amount': 10.0,
            'date': '2026-10-09',
            'category_id': 'c1',
            ...payload,
          },
          id: 'e1',
          groupId: 'g1',
          createdBy: 'u1',
          createdByName: 'Anna',
          paidBy: 'u1',
          paidByName: 'Anna',
          paymentMethodId: 'pm1',
          paymentMethodName: 'Contanti',
        );

    test('includes the recurring fields when present', () {
      final row = build({
        'recurring_expense_id': 't1',
        'is_recurring_instance': true,
      });
      expect(row['recurring_expense_id'], 't1');
      expect(row['is_recurring_instance'], true);
    });

    test('omits the recurring fields when absent', () {
      final row = build({});
      expect(row.containsKey('recurring_expense_id'), isFalse);
      expect(row.containsKey('is_recurring_instance'), isFalse);
    });

    test('PGRST204 on a recurring column triggers the retry without them',
        () {
      final row = build({
        'recurring_expense_id': 't1',
        'is_recurring_instance': true,
      });
      const e = PostgrestException(
        message:
            "Could not find the 'recurring_expense_id' column of 'expenses' in the schema cache",
        code: 'PGRST204',
      );
      expect(BatchSyncService.isMissingRecurringColumn(e), isTrue);

      final retry = BatchSyncService.withoutRecurringColumns(row);
      expect(retry.containsKey('recurring_expense_id'), isFalse);
      expect(retry.containsKey('is_recurring_instance'), isFalse);
      expect(retry['id'], 'e1');
      expect(retry['amount'], 10.0);
    });

    test('other errors do not trigger the retry', () {
      expect(
        BatchSyncService.isMissingRecurringColumn(const PostgrestException(
          message: "Could not find the 'foo' column of 'expenses'",
          code: 'PGRST204',
        )),
        isFalse,
      );
      expect(
        BatchSyncService.isMissingRecurringColumn(const PostgrestException(
          message: 'recurring_expense_id duplicate',
          code: '23505',
        )),
        isFalse,
      );
    });
  });
}
