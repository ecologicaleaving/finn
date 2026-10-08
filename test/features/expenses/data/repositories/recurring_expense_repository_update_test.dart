import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import 'package:family_expense_tracker/core/enums/recurrence_frequency.dart';
import 'package:family_expense_tracker/core/enums/reimbursement_status.dart';
import 'package:family_expense_tracker/features/expenses/data/datasources/expense_remote_datasource.dart';
import 'package:family_expense_tracker/features/expenses/data/datasources/recurring_expense_local_datasource.dart';
import 'package:family_expense_tracker/features/expenses/data/models/recurring_expense_entity.dart';
import 'package:family_expense_tracker/features/expenses/data/repositories/recurring_expense_repository_impl.dart';

class _FakeLocalDataSource extends Fake
    implements RecurringExpenseLocalDataSource {
  final Map<String, RecurringExpenseEntity> store = {};
  int updateAfterInstanceCreationCalls = 0;
  final List<Map<String, dynamic>> syncPayloads = [];

  @override
  Future<RecurringExpenseEntity> getRecurringExpense({
    required String id,
  }) async {
    return store[id]!;
  }

  @override
  Future<RecurringExpenseEntity> updateRecurringExpense({
    required String id,
    double? amount,
    String? categoryId,
    String? categoryName,
    RecurrenceFrequency? frequency,
    String? merchant,
    String? notes,
    bool? budgetReservationEnabled,
    ReimbursementStatus? defaultReimbursementStatus,
    String? paymentMethodId,
    String? paymentMethodName,
    DateTime? anchorDate,
    DateTime? nextDueDate,
  }) async {
    final current = store[id]!;
    final updated = RecurringExpenseEntity.fromDomain(
      current.copyWith(
        amount: amount,
        categoryId: categoryId,
        categoryName: categoryName,
        frequency: frequency,
        merchant: merchant,
        notes: notes,
        budgetReservationEnabled: budgetReservationEnabled,
        defaultReimbursementStatus: defaultReimbursementStatus,
        paymentMethodId: paymentMethodId,
        paymentMethodName: paymentMethodName,
        anchorDate: anchorDate,
        nextDueDate: nextDueDate,
        updatedAt: DateTime.now(),
      ),
    );
    store[id] = updated;
    return updated;
  }

  @override
  Future<void> updateAfterInstanceCreation({
    required String id,
    required DateTime lastInstanceCreatedAt,
    DateTime? nextDueDate,
  }) async {
    updateAfterInstanceCreationCalls++;
    store[id] = RecurringExpenseEntity.fromDomain(
      store[id]!.copyWith(
        lastInstanceCreatedAt: lastInstanceCreatedAt,
        nextDueDate: nextDueDate,
      ),
    );
  }

  @override
  Future<void> addToSyncQueue({
    required String userId,
    required String operation,
    required String entityId,
    required Map<String, dynamic> payload,
    int priority = 0,
  }) async {
    syncPayloads.add(payload);
  }
}

class _FakeExpenseRemoteDataSource extends Fake
    implements ExpenseRemoteDataSource {}

class _FakeGoTrueClient extends Fake implements GoTrueClient {
  @override
  User? get currentUser => User(
        id: 'u1',
        appMetadata: {},
        userMetadata: {},
        aud: '',
        createdAt: '',
      );
}

class _FakeSupabaseClient extends Fake implements SupabaseClient {
  final _auth = _FakeGoTrueClient();

  @override
  GoTrueClient get auth => _auth;
}

RecurringExpenseEntity _template({
  required DateTime anchorDate,
  RecurrenceFrequency frequency = RecurrenceFrequency.monthly,
  DateTime? lastInstanceCreatedAt,
  DateTime? nextDueDate,
}) {
  return RecurringExpenseEntity(
    id: 'r1',
    userId: 'u1',
    amount: 50,
    categoryId: 'cat1',
    categoryName: 'Casa',
    isGroupExpense: true,
    frequency: frequency,
    anchorDate: anchorDate,
    isPaused: false,
    lastInstanceCreatedAt: lastInstanceCreatedAt,
    nextDueDate: nextDueDate ?? anchorDate,
    budgetReservationEnabled: false,
    defaultReimbursementStatus: ReimbursementStatus.none,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  late _FakeLocalDataSource local;
  late RecurringExpenseRepositoryImpl repository;

  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  setUp(() {
    local = _FakeLocalDataSource();
    repository = RecurringExpenseRepositoryImpl(
      localDataSource: local,
      expenseRemoteDataSource: _FakeExpenseRemoteDataSource(),
      supabaseClient: _FakeSupabaseClient(),
    );
  });

  test(
      'editing only the amount (same frequency passed) keeps nextDueDate '
      'and lastInstanceCreatedAt unchanged', () async {
    final anchor = DateTime(2026, 10, 15);
    local.store['r1'] = _template(anchorDate: anchor);

    final result = await repository.updateRecurringExpense(
      id: 'r1',
      amount: 75,
      frequency: RecurrenceFrequency.monthly,
    );

    final updated = result.getOrElse(() => throw StateError('failure'));
    expect(updated.amount, 75);
    expect(updated.nextDueDate, anchor);
    expect(updated.lastInstanceCreatedAt, isNull);
    expect(local.store['r1']!.nextDueDate, anchor);
    expect(local.store['r1']!.lastInstanceCreatedAt, isNull);
    expect(local.updateAfterInstanceCreationCalls, 0);
    expect(local.syncPayloads.single.containsKey('next_due_date'), isFalse);
  });

  test('passing the same anchor date with a different time is not a change',
      () async {
    final anchor = DateTime(2026, 10, 15, 9, 30);
    local.store['r1'] = _template(anchorDate: anchor);

    await repository.updateRecurringExpense(
      id: 'r1',
      anchorDate: DateTime(2026, 10, 15),
      frequency: RecurrenceFrequency.monthly,
    );

    expect(local.store['r1']!.anchorDate, anchor);
    expect(local.store['r1']!.nextDueDate, anchor);
    expect(local.syncPayloads.single.containsKey('anchor_date'), isFalse);
  });

  test('updating the anchor date persists it and sets nextDueDate to it',
      () async {
    local.store['r1'] = _template(anchorDate: DateTime(2026, 10, 15));
    final newAnchor = DateTime(2026, 11, 3);

    final result = await repository.updateRecurringExpense(
      id: 'r1',
      anchorDate: newAnchor,
      frequency: RecurrenceFrequency.monthly,
    );

    final updated = result.getOrElse(() => throw StateError('failure'));
    expect(updated.anchorDate, newAnchor);
    expect(updated.nextDueDate, newAnchor);
    expect(updated.lastInstanceCreatedAt, isNull);
    expect(local.store['r1']!.anchorDate, newAnchor);
    expect(local.updateAfterInstanceCreationCalls, 0);
  });

  test(
      'changing frequency on a template with instances computes nextDueDate '
      'from lastInstanceCreatedAt and keeps it', () async {
    final lastCreated = DateTime.utc(2026, 3, 15);
    local.store['r1'] = _template(
      anchorDate: DateTime.utc(2026, 1, 15),
      lastInstanceCreatedAt: lastCreated,
      nextDueDate: DateTime.utc(2026, 4, 15),
    );

    final result = await repository.updateRecurringExpense(
      id: 'r1',
      frequency: RecurrenceFrequency.weekly,
    );

    final updated = result.getOrElse(() => throw StateError('failure'));
    expect(updated.frequency, RecurrenceFrequency.weekly);
    expect(
      updated.nextDueDate!.isAtSameMomentAs(DateTime.utc(2026, 3, 22)),
      isTrue,
      reason: 'got ${updated.nextDueDate}',
    );
    expect(updated.lastInstanceCreatedAt, lastCreated);
    expect(local.updateAfterInstanceCreationCalls, 0);
  });

  test('sync payload contains anchor_date and next_due_date when date changes',
      () async {
    local.store['r1'] = _template(anchorDate: DateTime(2026, 10, 15));
    final newAnchor = DateTime(2026, 11, 3);

    await repository.updateRecurringExpense(
      id: 'r1',
      anchorDate: newAnchor,
    );

    final payload = local.syncPayloads.single;
    expect(payload['anchor_date'], newAnchor.toIso8601String());
    expect(payload['next_due_date'], newAnchor.toIso8601String());
  });
}
