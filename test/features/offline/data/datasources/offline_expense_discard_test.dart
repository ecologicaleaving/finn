import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:family_expense_tracker/features/auth/domain/entities/user_entity.dart';
import 'package:family_expense_tracker/features/expenses/data/datasources/expense_local_cache_datasource.dart';
import 'package:family_expense_tracker/features/expenses/data/datasources/expense_remote_datasource.dart';
import 'package:family_expense_tracker/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:family_expense_tracker/features/expenses/domain/entities/expense_entity.dart';
import 'package:family_expense_tracker/features/offline/data/datasources/offline_expense_local_datasource.dart';
import 'package:family_expense_tracker/features/offline/data/local/offline_database.dart';
import 'package:family_expense_tracker/shared/services/connectivity_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Issue #48 / AC5: deleting an expense must discard it locally only when it
// never reached the server; anything already synced must be deleted remotely.
// These tests run the real drift datasource on an in-memory database.

const _userId = 'user-1';

const _user = UserEntity(
  id: _userId,
  email: 'test@example.com',
  displayName: 'Test User',
  groupId: 'group-1',
);

class _FakeRemote implements ExpenseRemoteDataSource {
  final List<String> deletedIds = [];

  @override
  Future<void> deleteExpense({required String expenseId}) async {
    deletedIds.add(expenseId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCache implements ExpenseLocalCacheDataSource {
  final List<String> removedIds = [];

  @override
  Future<void> removeExpense(String userId, String expenseId) async {
    removedIds.add(expenseId);
  }

  @override
  Future<void> upsertExpense(String userId, ExpenseEntity expense) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late OfflineDatabase db;
  late OfflineExpenseLocalDataSourceImpl offline;

  setUp(() {
    db = OfflineDatabase.forTesting(NativeDatabase.memory());
    offline = OfflineExpenseLocalDataSourceImpl(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> createOffline() async {
    final created = await offline.createOfflineExpense(
      userId: _userId,
      amount: 12,
      date: DateTime(2026, 9, 25),
      categoryId: 'cat-1',
    );
    return created.id;
  }

  /// Mirrors SyncQueueProcessor on a successful sync: the queue item is
  /// removed and the offline row is marked 'completed'.
  Future<void> simulateSuccessfulSync(String expenseId) async {
    final items = await (db.select(db.syncQueueItems)
          ..where((t) => t.entityId.equals(expenseId)))
        .get();
    await offline.deleteCompletedSyncItems(items.map((i) => i.id).toList());
    await offline.updateSyncStatus(expenseId, 'completed');
  }

  Future<void> addOfflineImage(String expenseId) async {
    await db.into(db.offlineExpenseImages).insert(
          OfflineExpenseImagesCompanion.insert(
            expenseId: expenseId,
            userId: _userId,
            compressedImageData: Uint8List.fromList([1, 2, 3]),
            originalSizeBytes: 3,
            compressedSizeBytes: 3,
            compressionRatio: 1,
            uploadStatus: 'pending',
            createdAt: DateTime(2026, 9, 25),
          ),
        );
  }

  Future<int> offlineRows(String id) async => (await (db.select(
            db.offlineExpenses)
          ..where((t) => t.id.equals(id)))
          .get())
      .length;

  Future<List<SyncQueueItem>> queueItems(String id) =>
      (db.select(db.syncQueueItems)..where((t) => t.entityId.equals(id))).get();

  Future<int> images(String id) async => (await (db.select(
            db.offlineExpenseImages)
          ..where((t) => t.expenseId.equals(id)))
          .get())
      .length;

  ExpenseRepositoryImpl repo(_FakeRemote remote, _FakeCache cache,
          {NetworkStatus network = NetworkStatus.online}) =>
      ExpenseRepositoryImpl(
        remoteDataSource: remote,
        localCacheDataSource: cache,
        offlineLocalDataSource: offline,
        currentUser: _user,
        networkStatusGetter: () => network,
      );

  group('discardUnsyncedExpense', () {
    test('pending offline expense: removes row, queue items and images',
        () async {
      final id = await createOffline();
      await addOfflineImage(id);

      final discarded =
          await offline.discardUnsyncedExpense(expenseId: id, userId: _userId);

      expect(discarded, isTrue);
      expect(await offlineRows(id), 0);
      expect(await queueItems(id), isEmpty);
      expect(await images(id), 0);
    });

    test('failed offline create is still discarded', () async {
      final id = await createOffline();
      await (db.update(db.syncQueueItems)..where((t) => t.entityId.equals(id)))
          .write(const SyncQueueItemsCompanion(syncStatus: Value('failed')));
      await offline.updateSyncStatus(id, 'failed');

      expect(
        await offline.discardUnsyncedExpense(expenseId: id, userId: _userId),
        isTrue,
      );
      expect(await offlineRows(id), 0);
    });

    test('created offline and then synced: not discarded, data untouched',
        () async {
      final id = await createOffline();
      await simulateSuccessfulSync(id);

      final discarded =
          await offline.discardUnsyncedExpense(expenseId: id, userId: _userId);

      expect(discarded, isFalse);
      expect(await offlineRows(id), 1);
    });

    test('synced and then edited offline (queued update): not discarded',
        () async {
      final id = await createOffline();
      await simulateSuccessfulSync(id);
      await offline.updateOfflineExpense(
        expenseId: id,
        userId: _userId,
        amount: 20,
      );
      expect((await queueItems(id)).single.operation, 'update');

      final discarded =
          await offline.discardUnsyncedExpense(expenseId: id, userId: _userId);

      expect(discarded, isFalse);
      expect(await offlineRows(id), 1);
      expect(await queueItems(id), hasLength(1));
    });

    test('expense unknown locally: not discarded', () async {
      expect(
        await offline.discardUnsyncedExpense(
            expenseId: 'server-only', userId: _userId),
        isFalse,
      );
    });

    test('another user\'s pending expense is not discarded', () async {
      final id = await createOffline();

      expect(
        await offline.discardUnsyncedExpense(expenseId: id, userId: 'user-2'),
        isFalse,
      );
      expect(await offlineRows(id), 1);
      expect(await queueItems(id), hasLength(1));
    });
  });

  group('ExpenseRepositoryImpl.deleteExpense with the real offline store', () {
    for (final network in [NetworkStatus.online, NetworkStatus.offline]) {
      test('pending offline expense is discarded locally ($network)', () async {
        final id = await createOffline();
        final remote = _FakeRemote();
        final cache = _FakeCache();

        final result =
            await repo(remote, cache, network: network).deleteExpense(
          expenseId: id,
        );

        expect(result.isRight(), isTrue);
        expect(remote.deletedIds, isEmpty);
        expect(cache.removedIds, [id]);
        expect(await offlineRows(id), 0);
        // Nothing left for the sync to replay: no create, no remote delete.
        expect(await queueItems(id), isEmpty);
      });
    }

    test('offline-created expense already synced is deleted on the server',
        () async {
      final id = await createOffline();
      await simulateSuccessfulSync(id);
      final remote = _FakeRemote();
      final cache = _FakeCache();

      final result = await repo(remote, cache).deleteExpense(expenseId: id);

      expect(result.isRight(), isTrue);
      expect(remote.deletedIds, [id]);
      expect(cache.removedIds, [id]);
      expect(await offlineRows(id), 0);
      expect(await queueItems(id), isEmpty);
    });

    test('synced expense with a queued offline update is deleted on the server '
        'and the stale update is dropped', () async {
      final id = await createOffline();
      await simulateSuccessfulSync(id);
      await offline.updateOfflineExpense(
        expenseId: id,
        userId: _userId,
        amount: 20,
      );
      final remote = _FakeRemote();
      final cache = _FakeCache();

      final result = await repo(remote, cache).deleteExpense(expenseId: id);

      expect(result.isRight(), isTrue);
      expect(remote.deletedIds, [id]);
      expect(await offlineRows(id), 0);
      expect(await queueItems(id), isEmpty);
    });

    test('server-only expense is deleted on the server', () async {
      final remote = _FakeRemote();
      final cache = _FakeCache();

      final result =
          await repo(remote, cache).deleteExpense(expenseId: 'srv-1');

      expect(result.isRight(), isTrue);
      expect(remote.deletedIds, ['srv-1']);
      expect(cache.removedIds, ['srv-1']);
    });
  });
}
