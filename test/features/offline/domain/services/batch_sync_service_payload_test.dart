import 'package:family_expense_tracker/features/offline/domain/services/batch_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
