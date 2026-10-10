import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:family_expense_tracker/core/enums/recurrence_frequency.dart';
import 'package:family_expense_tracker/core/enums/reimbursement_status.dart';
import 'package:family_expense_tracker/core/services/recurring_instance_generator.dart';
import 'package:family_expense_tracker/features/offline/data/local/offline_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// Issue #69 - AC4 / AC6: local generation of recurring instances.

DateTime _noon(int y, int m, int d) => tz.TZDateTime(tz.local, y, m, d, 12);

void main() {
  late OfflineDatabase db;
  late SharedPreferences prefs;
  late DateTime now;

  setUpAll(() {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Rome'));
    now = _noon(2026, 10, 9);
  });

  setUp(() async {
    db = OfflineDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    // Activation already done unless a test says otherwise.
    await prefs.setBool(RecurringInstanceGenerator.activationFlagKey, true);
  });

  tearDown(() async => db.close());

  Future<void> addTemplate(
    String id, {
    required DateTime nextDue,
    RecurrenceFrequency frequency = RecurrenceFrequency.daily,
    DateTime? anchor,
    bool paused = false,
    DateTime? deletedAt,
  }) async {
    await db.into(db.recurringExpenses).insert(
          RecurringExpensesCompanion.insert(
            id: id,
            userId: 'u1',
            groupId: const Value('g1'),
            amount: 12.5,
            categoryId: 'cat-1',
            categoryName: 'Casa',
            merchant: const Value('Affitto srl'),
            notes: const Value('nota'),
            frequency: frequency,
            anchorDate: anchor ?? nextDue,
            isPaused: Value(paused),
            nextDueDate: Value(nextDue),
            budgetReservationEnabled: const Value(true),
            defaultReimbursementStatus:
                const Value(ReimbursementStatus.reimbursable),
            paymentMethodId: const Value('pm-1'),
            createdAt: now,
            updatedAt: now,
            deletedAt: Value(deletedAt),
          ),
        );
  }

  Future<List<OfflineExpense>> expenses() => db.select(db.offlineExpenses).get();
  Future<List<SyncQueueItem>> expenseQueue() => (db.select(db.syncQueueItems)
        ..where((q) => q.entityType.equals('expense')))
      .get();

  test('a due occurrence creates one row, one queue entry and one mapping',
      () async {
    await addTemplate('t1', nextDue: _noon(2026, 10, 9));

    final created = await RecurringInstanceGenerator.generate(db, now, prefs: prefs);

    expect(created, 1);
    final rows = await expenses();
    expect(rows, hasLength(1));
    expect(rows.single.id, RecurringInstanceGenerator.instanceId('t1', '2026-10-09'));
    expect(rows.single.recurringExpenseId, 't1');
    expect(rows.single.isRecurringInstance, isTrue);
    expect(rows.single.syncStatus, 'pending');
    expect(rows.single.reimbursementStatus, 'reimbursable');

    final queue = await expenseQueue();
    expect(queue, hasLength(1));
    expect(queue.single.operation, 'create');
    expect(queue.single.userId, 'u1');
    expect(queue.single.entityId, rows.single.id);
    final payload = jsonDecode(queue.single.payload) as Map<String, dynamic>;
    expect(payload['id'], rows.single.id);
    expect(payload['date'], '2026-10-09');
    expect(payload['amount'], 12.5);
    expect(payload['category_id'], 'cat-1');
    expect(payload['payment_method_id'], 'pm-1');
    expect(payload['reimbursement_status'], 'reimbursable');
    expect(payload['recurring_expense_id'], 't1');
    expect(payload['is_recurring_instance'], true);
    expect(payload['created_by'], 'u1');
    expect(payload['is_group_expense'], true);

    final mappings = await db.select(db.recurringExpenseInstances).get();
    expect(mappings, hasLength(1));
    expect(mappings.single.expenseId, rows.single.id);

    // The template advanced from the scheduled date (not from now).
    final t = await (db.select(db.recurringExpenses)
          ..where((x) => x.id.equals('t1')))
        .getSingle();
    expect(RecurringInstanceGenerator.dayKeyOf(t.nextDueDate!), '2026-10-10');
    expect(RecurringInstanceGenerator.dayKeyOf(t.lastInstanceCreatedAt!), '2026-10-09');
  });

  test('running twice, also concurrently, leaves 0 duplicates', () async {
    await addTemplate('t1', nextDue: _noon(2026, 10, 9));

    await RecurringInstanceGenerator.generate(db, now, prefs: prefs);
    final second = await RecurringInstanceGenerator.generate(db, now, prefs: prefs);
    expect(second, 0);

    // Concurrent runs, plus a template forced back to the same day (as a
    // second device / isolate that did not see the advancement).
    await (db.update(db.recurringExpenses)..where((t) => t.id.equals('t1')))
        .write(RecurringExpensesCompanion(nextDueDate: Value(_noon(2026, 10, 9))));
    await Future.wait([
      RecurringInstanceGenerator.generate(db, now, prefs: prefs),
      RecurringInstanceGenerator.generate(db, now, prefs: prefs),
    ]);

    expect(await expenses(), hasLength(1));
    expect(await expenseQueue(), hasLength(1));
    expect(await db.select(db.recurringExpenseInstances).get(), hasLength(1));
  });

  test('never creates a future date', () async {
    await addTemplate('t1', nextDue: _noon(2026, 10, 10));
    expect(await RecurringInstanceGenerator.generate(db, now, prefs: prefs), 0);
    expect(await expenses(), isEmpty);
  });

  test('paused and deleted templates are skipped', () async {
    await addTemplate('paused', nextDue: _noon(2026, 10, 9), paused: true);
    await addTemplate('gone', nextDue: _noon(2026, 10, 9), deletedAt: now);
    expect(await RecurringInstanceGenerator.generate(db, now, prefs: prefs), 0);
    expect(await expenses(), isEmpty);
    expect(await expenseQueue(), isEmpty);
  });

  test('catches up missed days (phone off for 3 days)', () async {
    await addTemplate('t1', nextDue: _noon(2026, 10, 6));
    final created = await RecurringInstanceGenerator.generate(db, now, prefs: prefs);
    expect(created, 4); // 6, 7, 8, 9 October
    final days = (await expenses()).map((e) => e.date.day).toList()..sort();
    expect(days, [6, 7, 8, 9]);
  });

  test('respects the per-template limit', () async {
    await addTemplate('t1', nextDue: _noon(2026, 9, 1));
    final created = await RecurringInstanceGenerator.generate(
      db,
      now,
      maxPerTemplate: 3,
      prefs: prefs,
    );
    expect(created, 3);
    expect(await expenses(), hasLength(3));
  });

  test('first activation does not recover the past (decision D1)', () async {
    await prefs.remove(RecurringInstanceGenerator.activationFlagKey);
    await addTemplate('old', nextDue: _noon(2026, 10, 4));

    final created = await RecurringInstanceGenerator.generate(db, now, prefs: prefs);

    // Only the occurrence of today; the 4..8 October are not recreated.
    expect(created, 1);
    final rows = await expenses();
    expect(rows.single.date.day, 9);
    expect(prefs.getBool(RecurringInstanceGenerator.activationFlagKey), isTrue);

    // After activation the normal catch-up applies.
    await addTemplate('late', nextDue: _noon(2026, 10, 7));
    expect(await RecurringInstanceGenerator.generate(db, now, prefs: prefs), 3);
  });

  test('never deletes existing expenses or queue entries', () async {
    await db.into(db.offlineExpenses).insert(OfflineExpensesCompanion.insert(
          id: 'manual-1',
          userId: 'u1',
          amount: 3,
          date: now,
          categoryId: 'cat-1',
          syncStatus: 'failed',
          localCreatedAt: now,
          localUpdatedAt: now,
        ));
    await db.into(db.syncQueueItems).insert(SyncQueueItemsCompanion.insert(
          userId: 'u1',
          operation: 'create',
          entityType: 'expense',
          entityId: 'manual-1',
          payload: '{}',
          syncStatus: 'failed',
          createdAt: now,
        ));
    await addTemplate('t1', nextDue: _noon(2026, 10, 9));

    await RecurringInstanceGenerator.generate(db, now, prefs: prefs);

    final ids = (await expenses()).map((e) => e.id).toSet();
    expect(ids, contains('manual-1'));
    expect(ids, hasLength(2));
    final queueIds = (await expenseQueue()).map((q) => q.entityId).toSet();
    expect(queueIds, contains('manual-1'));
    final manual = await (db.select(db.offlineExpenses)
          ..where((e) => e.id.equals('manual-1')))
        .getSingle();
    expect(manual.syncStatus, 'failed');
  });

  test('instance ids are deterministic', () {
    expect(
      RecurringInstanceGenerator.instanceId('t1', '2026-10-09'),
      RecurringInstanceGenerator.instanceId('t1', '2026-10-09'),
    );
    expect(
      RecurringInstanceGenerator.instanceId('t1', '2026-10-09'),
      isNot(RecurringInstanceGenerator.instanceId('t1', '2026-10-10')),
    );
  });
}
