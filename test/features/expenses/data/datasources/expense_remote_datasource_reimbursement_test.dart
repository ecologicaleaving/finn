import 'package:family_expense_tracker/core/enums/reimbursement_status.dart';
import 'package:family_expense_tracker/features/expenses/data/datasources/expense_remote_datasource.dart';
import 'package:flutter_test/flutter_test.dart';

/// Issue #47: the DB constraint `check_reimbursed_at_consistency` requires
/// `reimbursed_at` NOT NULL for status 'reimbursed' and NULL otherwise.
void main() {
  final now = DateTime.utc(2026, 9, 26, 10, 30, 15);

  group('ExpenseRemoteDataSourceImpl.reimbursementFields', () {
    test('reimbursed sets a non-null UTC ISO reimbursed_at equal to now', () {
      final fields = ExpenseRemoteDataSourceImpl.reimbursementFields(
        ReimbursementStatus.reimbursed,
        now: now,
      );

      expect(fields['reimbursement_status'], 'reimbursed');
      expect(fields['reimbursed_at'], isNotNull);
      expect(fields['reimbursed_at'], now.toIso8601String());
    });

    test('local time is converted to UTC', () {
      final local = DateTime(2026, 9, 26, 12);
      final fields = ExpenseRemoteDataSourceImpl.reimbursementFields(
        ReimbursementStatus.reimbursed,
        now: local,
      );

      expect(fields['reimbursed_at'], local.toUtc().toIso8601String());
      expect((fields['reimbursed_at'] as String).endsWith('Z'), isTrue);
    });

    test('reimbursed without injected now still sets reimbursed_at', () {
      final fields = ExpenseRemoteDataSourceImpl.reimbursementFields(
        ReimbursementStatus.reimbursed,
      );
      expect(fields['reimbursed_at'], isA<String>());
    });

    for (final status in [
      ReimbursementStatus.none,
      ReimbursementStatus.reimbursable,
    ]) {
      test('${status.value} sends reimbursed_at explicitly as null', () {
        final fields = ExpenseRemoteDataSourceImpl.reimbursementFields(
          status,
          now: now,
        );

        expect(fields['reimbursement_status'], status.value);
        expect(fields.containsKey('reimbursed_at'), isTrue);
        expect(fields['reimbursed_at'], isNull);
      });
    }

    test('create path with reimbursed produces a valid insert payload (AC2)', () {
      final insert = <String, dynamic>{
        'amount': 10.0,
        ...ExpenseRemoteDataSourceImpl.reimbursementFields(
          ReimbursementStatus.reimbursed,
          now: now,
        ),
      };

      expect(insert['reimbursement_status'], 'reimbursed');
      expect(insert['reimbursed_at'], now.toIso8601String());
    });
  });

  group('ExpenseRemoteDataSourceImpl.buildUpdatePayload', () {
    test('status reimbursed includes status and reimbursed_at', () {
      final payload = ExpenseRemoteDataSourceImpl.buildUpdatePayload(
        reimbursementStatus: ReimbursementStatus.reimbursed,
        now: now,
      );

      expect(payload, {
        'reimbursement_status': 'reimbursed',
        'reimbursed_at': now.toIso8601String(),
      });
    });

    test('reverting to none clears reimbursed_at explicitly', () {
      final payload = ExpenseRemoteDataSourceImpl.buildUpdatePayload(
        reimbursementStatus: ReimbursementStatus.none,
        now: now,
      );

      expect(payload['reimbursement_status'], 'none');
      expect(payload.containsKey('reimbursed_at'), isTrue);
      expect(payload['reimbursed_at'], isNull);
    });

    test('reverting to reimbursable clears reimbursed_at explicitly', () {
      final payload = ExpenseRemoteDataSourceImpl.buildUpdatePayload(
        reimbursementStatus: ReimbursementStatus.reimbursable,
        now: now,
      );

      expect(payload['reimbursement_status'], 'reimbursable');
      expect(payload.containsKey('reimbursed_at'), isTrue);
      expect(payload['reimbursed_at'], isNull);
    });

    test('update without status does not touch reimbursement columns', () {
      final payload = ExpenseRemoteDataSourceImpl.buildUpdatePayload(
        amount: 42.5,
        date: DateTime(2026, 9, 1),
        categoryId: 'cat-1',
        merchant: 'Shop',
        notes: 'note',
      );

      expect(payload.containsKey('reimbursement_status'), isFalse);
      expect(payload.containsKey('reimbursed_at'), isFalse);
      expect(payload['amount'], 42.5);
      expect(payload['date'], '2026-09-01');
      expect(payload['category_id'], 'cat-1');
      expect(payload['merchant'], 'Shop');
      expect(payload['notes'], 'note');
    });

    test('empty update produces an empty payload', () {
      expect(ExpenseRemoteDataSourceImpl.buildUpdatePayload(), isEmpty);
    });

    test('status-only update is not empty', () {
      final payload = ExpenseRemoteDataSourceImpl.buildUpdatePayload(
        reimbursementStatus: ReimbursementStatus.reimbursable,
      );
      expect(payload, isNotEmpty);
    });
  });
}
