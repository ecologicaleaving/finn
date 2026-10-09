import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:family_expense_tracker/core/database/daos/recurring_expenses_dao.dart';
import 'package:family_expense_tracker/core/enums/recurrence_frequency.dart';
import 'package:family_expense_tracker/features/expenses/data/datasources/recurring_expense_remote_datasource.dart';
import 'package:family_expense_tracker/features/expenses/data/services/recurring_template_sync_service.dart';
import 'package:family_expense_tracker/features/offline/data/local/offline_database.dart';
import 'package:flutter_test/flutter_test.dart';

// Issue #69 - AC2 / AC7: template sync with a fake remote.

class _FakeRemote implements RecurringTemplateSyncRemote {
  final Map<String, Map<String, dynamic>> rows = {};
  bool tableMissing = false;
  String? groupId = 'g1';
  int upserts = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchOwnTemplatesForSync(
      String userId) async {
    if (tableMissing) throw const RemoteTableMissing('PGRST205');
    return rows.values.where((r) => r['user_id'] == userId).toList();
  }

  @override
  Future<void> upsertTemplateRow(Map<String, dynamic> row) async {
    if (tableMissing) throw const RemoteTableMissing('PGRST205');
    upserts++;
    rows[row['id'] as String] = {
      ...?rows[row['id'] as String],
      ...row,
      'updated_at': '2026-10-09T10:00:00Z',
      'created_at': row['created_at'] ?? '2026-10-01T10:00:00Z',
    };
  }

  @override
  Future<String?> fetchUserGroupId(String userId) async => groupId;
}

Map<String, dynamic> _remoteRow(
  String id, {
  double amount = 10,
  String? nextDue = '2026-10-20T10:00:00Z',
  String? last,
  String? deletedAt,
  bool paused = false,
}) =>
    {
      'id': id,
      'user_id': 'u1',
      'group_id': 'g1',
      'template_expense_id': null,
      'amount': amount,
      'category_id': 'cat-1',
      'category_name': 'Casa',
      'merchant': null,
      'notes': null,
      'is_group_expense': true,
      'frequency': 'monthly',
      'anchor_date': '2026-09-20T10:00:00Z',
      'is_paused': paused,
      'last_instance_created_at': last,
      'next_due_date': nextDue,
      'budget_reservation_enabled': false,
      'default_reimbursement_status': 'none',
      'payment_method_id': null,
      'payment_method_name': null,
      'deleted_at': deletedAt,
      'created_at': '2026-09-20T10:00:00Z',
      'updated_at': '2026-10-01T10:00:00Z',
    };

void main() {
  late OfflineDatabase db;
  late RecurringExpensesDao dao;
  late _FakeRemote remote;
  late RecurringTemplateSyncService service;
  final t0 = DateTime.utc(2026, 9, 20, 10);

  setUp(() {
    db = OfflineDatabase.forTesting(NativeDatabase.memory());
    dao = RecurringExpensesDao(db);
    remote = _FakeRemote();
    service = RecurringTemplateSyncService(dao: dao, remote: remote);
  });

  tearDown(() async => db.close());

  Future<void> addLocal(
    String id, {
    double amount = 10,
    DateTime? nextDue,
    DateTime? last,
    DateTime? deletedAt,
    String? groupId = 'g1',
  }) async {
    await db.into(db.recurringExpenses).insert(
          RecurringExpensesCompanion.insert(
            id: id,
            userId: 'u1',
            groupId: Value(groupId),
            amount: amount,
            categoryId: 'cat-1',
            categoryName: 'Casa',
            frequency: RecurrenceFrequency.monthly,
            anchorDate: t0,
            nextDueDate: Value(nextDue ?? DateTime.utc(2026, 10, 20, 10)),
            lastInstanceCreatedAt: Value(last),
            deletedAt: Value(deletedAt),
            createdAt: t0,
            updatedAt: t0,
          ),
        );
  }

  Future<void> queue(String id, {String op = 'update'}) =>
      db.into(db.syncQueueItems).insert(SyncQueueItemsCompanion.insert(
            userId: 'u1',
            operation: op,
            entityType: 'recurring_expense',
            entityId: id,
            payload: '{}',
            syncStatus: 'pending',
            createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          ));

  Future<RecurringExpenseData> local(String id) =>
      (db.select(db.recurringExpenses)..where((t) => t.id.equals(id)))
          .getSingle();

  test('local-only template is uploaded with the same id', () async {
    await addLocal('a');
    await queue('a', op: 'create');

    final r = await service.sync('u1');

    expect(r.pushed, 1);
    expect(remote.rows.keys, ['a']);
    expect(remote.rows['a']!['user_id'], 'u1');
    expect(remote.rows['a']!['frequency'], 'monthly');
    // Queue entries covered by the push are cleared
    expect(await dao.getTemplateQueueItems('u1'), isEmpty);
  });

  test('missing group falls back to the profile group', () async {
    await addLocal('a', groupId: null);
    await service.sync('u1');
    expect(remote.rows['a']!['group_id'], 'g1');
  });

  test('server-only own template is inserted locally', () async {
    remote.rows['b'] = _remoteRow('b');
    final r = await service.sync('u1');
    expect(r.inserted, 1);
    expect((await local('b')).amount, 10);
    // Nothing is pushed back
    expect(remote.upserts, 0);
  });

  test('server-only deleted template is not inserted', () async {
    remote.rows['b'] = _remoteRow('b', deletedAt: '2026-10-05T10:00:00Z');
    await service.sync('u1');
    expect(await db.select(db.recurringExpenses).get(), isEmpty);
  });

  test('local with pending changes wins on content and is pushed', () async {
    await addLocal('c', amount: 99);
    await queue('c');
    remote.rows['c'] = _remoteRow('c', amount: 10);

    await service.sync('u1');

    expect(remote.rows['c']!['amount'], 99);
    expect((await local('c')).amount, 99);
    expect(await dao.getTemplateQueueItems('u1'), isEmpty);
  });

  test('local without pending changes is updated from the server', () async {
    await addLocal('d', amount: 10);
    remote.rows['d'] = _remoteRow('d', amount: 55);

    final r = await service.sync('u1');

    expect(r.pulled, 1);
    expect((await local('d')).amount, 55);
    expect(remote.upserts, 0);
  });

  test('schedule dates take the most recent value on both sides', () async {
    await addLocal(
      'e',
      nextDue: DateTime.utc(2026, 10, 25, 10),
      last: DateTime.utc(2026, 10, 20, 10),
    );
    remote.rows['e'] = _remoteRow(
      'e',
      nextDue: '2026-11-20T10:00:00Z',
      last: '2026-10-19T10:00:00Z',
    );

    await service.sync('u1');

    final l = await local('e');
    expect(l.nextDueDate!.toUtc(), DateTime.utc(2026, 11, 20, 10));
    expect(l.lastInstanceCreatedAt!.toUtc(), DateTime.utc(2026, 10, 20, 10));
    // The remote got the most recent last_instance_created_at too
    expect(
      DateTime.parse(remote.rows['e']!['last_instance_created_at'] as String)
          .toUtc(),
      DateTime.utc(2026, 10, 20, 10),
    );
  });

  test('remote tombstone propagates locally as a soft delete', () async {
    await addLocal('f');
    remote.rows['f'] = _remoteRow('f', deletedAt: '2026-10-05T10:00:00Z');

    await service.sync('u1');

    final l = await local('f');
    expect(l.deletedAt, isNotNull);
    expect(l.isPaused, isTrue);
  });

  test('local tombstone propagates to the server', () async {
    await addLocal('g', deletedAt: DateTime.utc(2026, 10, 6));
    await queue('g');
    remote.rows['g'] = _remoteRow('g');

    await service.sync('u1');

    expect(remote.rows['g']!['deleted_at'], isNotNull);
    expect(remote.rows['g']!['is_paused'], true);
  });

  test('never decreases the number of local rows', () async {
    await addLocal('h1');
    await addLocal('h2', deletedAt: DateTime.utc(2026, 10, 6));
    await addLocal('h3');
    remote.rows['h3'] = _remoteRow('h3', deletedAt: '2026-10-05T10:00:00Z');
    remote.rows['h4'] = _remoteRow('h4');
    final before = (await db.select(db.recurringExpenses).get()).length;

    await service.sync('u1');

    final after = (await db.select(db.recurringExpenses).get()).length;
    expect(after, greaterThanOrEqualTo(before));
  });

  test('missing remote table is a no-op and leaves local data intact',
      () async {
    remote.tableMissing = true;
    await addLocal('i');
    await queue('i', op: 'create');

    final r = await service.sync('u1');

    expect(r.tableMissing, isTrue);
    expect((await db.select(db.recurringExpenses).get()), hasLength(1));
    expect(await dao.getTemplateQueueItems('u1'), hasLength(1));
  });

  test('old hard-delete queue entry without local row is discarded',
      () async {
    await queue('ghost', op: 'delete');
    await service.sync('u1');
    expect(await dao.getTemplateQueueItems('u1'), isEmpty);
    expect(remote.rows, isEmpty);
  });

  test('sync never touches expenses or expense queue entries', () async {
    await db.into(db.syncQueueItems).insert(SyncQueueItemsCompanion.insert(
          userId: 'u1',
          operation: 'create',
          entityType: 'expense',
          entityId: 'x1',
          payload: '{}',
          syncStatus: 'pending',
          createdAt: DateTime.now(),
        ));
    await addLocal('j');
    await service.sync('u1');
    final items = await db.select(db.syncQueueItems).get();
    expect(items.where((q) => q.entityType == 'expense'), hasLength(1));
  });
}
