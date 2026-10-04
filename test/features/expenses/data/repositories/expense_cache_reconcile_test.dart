import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:family_expense_tracker/core/enums/reimbursement_status.dart';
import 'package:family_expense_tracker/features/expenses/data/datasources/expense_local_cache_datasource.dart';
import 'package:family_expense_tracker/features/expenses/data/models/expense_model.dart';
import 'package:family_expense_tracker/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:family_expense_tracker/features/expenses/domain/entities/expense_entity.dart';
import 'package:family_expense_tracker/features/offline/data/datasources/offline_expense_local_datasource.dart';
import 'package:family_expense_tracker/features/offline/data/local/offline_database.dart';
import 'package:family_expense_tracker/shared/services/connectivity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'expense_test_support.dart';

// Issue #65 / AC3, AC4: an expense deleted on another device disappears from
// the local cache, but nothing the user has not synced yet is ever removed.
// Uses a real Hive box and the real drift datasource on an in-memory db.

class _ThrowingOffline extends OfflineExpenseLocalDataSourceImpl {
  _ThrowingOffline(OfflineDatabase db) : super(database: db);

  @override
  Future<Set<String>> getUnsyncedExpenseIds(String userId) =>
      throw StateError('db down');
}

void main() {
  late Directory dir;
  late Box<String> box;
  late OfflineDatabase db;
  late HiveExpenseLocalCacheDataSource cache;
  late OfflineExpenseLocalDataSourceImpl offline;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('finn_cache_test');
    Hive.init(dir.path);
    box = await Hive.openBox<String>('expense_cache_test');
    cache = HiveExpenseLocalCacheDataSource(box: box);
    db = OfflineDatabase.forTesting(NativeDatabase.memory());
    offline = OfflineExpenseLocalDataSourceImpl(database: db);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteFromDisk();
    await db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ExpenseRepositoryImpl repo(
    FakeServer server, {
    OfflineExpenseLocalDataSource? offlineOverride,
  }) =>
      ExpenseRepositoryImpl(
        remoteDataSource: server,
        localCacheDataSource: cache,
        offlineLocalDataSource: offlineOverride ?? offline,
        currentUser: testUser,
        networkStatusGetter: () => NetworkStatus.online,
      );

  Future<List<String>> cachedIds() async =>
      (await cache.getCachedExpenses(testUserId)).map((e) => e.id).toList();

  DateTime day(int d) => DateTime(2026, 9, d);

  ExpenseEntity ex(String id, int d,
          {String? status = 'completed', bool group = true, String cat = 'cat-1'}) =>
      makeExpense(id, date: day(d), syncStatus: status, isGroupExpense: group, categoryId: cat);

  group('removal of expenses deleted on the server', () {
    test('a completed expense missing on the server is removed', () async {
      await cache.cacheExpenses(testUserId, [ex('a', 5), ex('gone', 4), ex('b', 3)]);
      final server = FakeServer([ex('a', 5), ex('b', 3)]);

      await repo(server).getExpenses(limit: 20, offset: 0);

      expect(await cachedIds(), ['a', 'b']);
    });

    test('pending, failed, syncing and conflict expenses are never removed', () async {
      await cache.cacheExpenses(testUserId, [
        ex('p', 5, status: 'pending'),
        ex('f', 4, status: 'failed'),
        ex('s', 3, status: 'syncing'),
        ex('c', 2, status: 'conflict'),
        ex('n', 1, status: null),
      ]);
      final server = FakeServer([]);

      await repo(server).getExpenses(limit: 20, offset: 0);

      expect((await cachedIds()).toSet(), {'p', 'f', 's', 'c', 'n'});
    });

    test('a completed expense with queued local work is kept', () async {
      await cache.cacheExpenses(testUserId, [ex('q', 5), ex('plain', 4)]);
      await offline.addToSyncQueue(
        userId: testUserId,
        operation: 'update',
        entityType: 'expense',
        entityId: 'q',
        payload: {'amount': 1},
      );
      final server = FakeServer([]);

      await repo(server).getExpenses(limit: 20, offset: 0);

      expect(await cachedIds(), ['q']);
    });

    test('a completed expense with a failed queue item is kept', () async {
      await cache.cacheExpenses(testUserId, [ex('q', 5)]);
      await offline.addToSyncQueue(
        userId: testUserId,
        operation: 'create',
        entityType: 'expense',
        entityId: 'q',
        payload: {'amount': 1},
      );
      await (db.update(db.syncQueueItems)).write(
        const SyncQueueItemsCompanion(syncStatus: Value('failed')),
      );

      await repo(FakeServer([])).getExpenses(limit: 20, offset: 0);

      expect(await cachedIds(), ['q']);
    });

    test('an offline row not completed protects the expense', () async {
      final created = await offline.createOfflineExpense(
        userId: testUserId,
        amount: 5,
        date: day(5),
        categoryId: 'cat-1',
      );
      // Hive says completed, drift says it is still being synced.
      await cache.cacheExpenses(testUserId, [ex(created.id, 5)]);
      await offline.updateSyncStatus(created.id, 'syncing');
      await (db.delete(db.syncQueueItems)).go();

      await repo(FakeServer([])).getExpenses(limit: 20, offset: 0);

      expect(await cachedIds(), [created.id]);
    });

    test('a pending expense that completes during the fetch is kept', () async {
      await cache.cacheExpenses(testUserId, [ex('x', 5, status: 'pending')]);
      final server = FakeServer([]);
      // The sync finishes while the repository waits for the server: it was
      // pending in the snapshot, so it must not be a removal candidate.
      final slow = _HookedServer(server, () async {
        await cache.updateExpenseSyncStatus(testUserId, 'x', 'completed');
      });

      await repo(slow).getExpenses(limit: 20, offset: 0);

      expect(await cachedIds(), ['x']);
    });

    test('with offset > 0 only the window of the page is cleaned', () async {
      await cache.cacheExpenses(testUserId, [
        for (var d = 9; d >= 1; d--) ex('e$d', d),
      ]);
      // Server still has everything except e5 (deleted elsewhere) and e8.
      final server = FakeServer([
        for (var d = 9; d >= 1; d--)
          if (d != 5 && d != 8) ex('e$d', d),
      ]);

      // Page offset 3 limit 3 over [9,7,6,4,3,2,1] -> 4,3,2: window is
      // [e4 .. e2]. e5 sits between e6 and e4 in the order, outside the window
      // of this page (above e4), e8 is far above: both stay.
      await repo(server).getExpenses(limit: 3, offset: 3);
      expect((await cachedIds()).toSet().containsAll({'e5', 'e8'}), isTrue);

      // A page covering e5's position removes it: offset 2 limit 3 -> 6,4,3;
      // window e6..e3 contains e5.
      await repo(server).getExpenses(limit: 3, offset: 2);
      final ids = (await cachedIds()).toSet();
      expect(ids.contains('e5'), isFalse);
      expect(ids.contains('e8'), isTrue, reason: 'above the window');
      expect(ids.contains('e1'), isTrue, reason: 'below the window');
    });

    test('with a filter only expenses matching it are removed', () async {
      await cache.cacheExpenses(testUserId, [
        ex('g-gone', 5, group: true),
        ex('p-other', 4, group: false),
      ]);

      await repo(FakeServer([])).getExpenses(
        isGroupExpense: true,
        limit: 20,
        offset: 0,
      );

      expect(await cachedIds(), ['p-other']);
    });

    test('if the unsynced lookup fails nothing is removed', () async {
      await cache.cacheExpenses(testUserId, [ex('a', 5)]);

      await repo(
        FakeServer([]),
        offlineOverride: _ThrowingOffline(db),
      ).getExpenses(limit: 20, offset: 0);

      expect(await cachedIds(), ['a']);
    });

    test('if the server answers with an error nothing is removed', () async {
      await cache.cacheExpenses(testUserId, [ex('a', 5)]);
      final server = FakeServer([])..error = Exception('boom');

      final result = await repo(server).getExpenses(limit: 20, offset: 0);

      expect(result.isLeft(), isTrue);
      expect(await cachedIds(), ['a']);
    });

    test('an empty page with offset > 0 removes nothing', () async {
      await cache.cacheExpenses(testUserId, [ex('a', 5)]);

      await repo(FakeServer([])).getExpenses(limit: 20, offset: 20);

      expect(await cachedIds(), ['a']);
    });
  });

  group('removeSyncedExpenses', () {
    test('keeps an expense that went back to pending in the meantime', () async {
      await cache.cacheExpenses(testUserId, [ex('x', 5), ex('y', 4)]);
      // The caller picked x and y while they were completed, then x was edited
      // offline and became pending again.
      await cache.updateExpenseSyncStatus(testUserId, 'x', 'pending');

      final removed = await cache.removeSyncedExpenses(testUserId, {'x', 'y'});

      expect(removed, 1);
      expect(await cachedIds(), ['x']);
    });

    test('is safe against a concurrent pending upsert', () async {
      await cache.cacheExpenses(testUserId, [ex('x', 5), ex('y', 4)]);

      await Future.wait([
        cache.removeSyncedExpenses(testUserId, {'x', 'y'}),
        cache.upsertExpense(testUserId, ex('new', 6, status: 'pending')),
      ]);

      expect(await cachedIds(), ['new']);
    });
  });
}

/// Runs [onFetch] after the wrapped server has answered, before the
/// repository sees the result.
class _HookedServer extends FakeServer {
  _HookedServer(FakeServer inner, this.onFetch) : super(inner.rows);

  final Future<void> Function() onFetch;

  @override
  Future<List<ExpenseModel>> getExpenses({
    DateTime? startDate,
    DateTime? endDate,
    String? categoryId,
    String? createdBy,
    String? paidBy,
    bool? isGroupExpense,
    ReimbursementStatus? reimbursementStatus,
    int? limit,
    int? offset,
  }) async {
    final result = await super.getExpenses(
      startDate: startDate,
      endDate: endDate,
      categoryId: categoryId,
      createdBy: createdBy,
      paidBy: paidBy,
      isGroupExpense: isGroupExpense,
      reimbursementStatus: reimbursementStatus,
      limit: limit,
      offset: offset,
    );
    await onFetch();
    return result;
  }
}
