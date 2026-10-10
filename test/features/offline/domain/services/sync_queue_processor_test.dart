import 'package:family_expense_tracker/features/offline/data/datasources/offline_expense_local_datasource.dart';
import 'package:family_expense_tracker/features/offline/data/local/offline_database.dart';
import 'package:family_expense_tracker/features/offline/domain/services/batch_sync_service.dart';
import 'package:family_expense_tracker/features/offline/domain/services/sync_queue_processor.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLocalDataSource implements OfflineExpenseLocalDataSource {
  _FakeLocalDataSource(this.items);

  final List<SyncQueueItem> items;
  final List<int> deletedIds = [];

  @override
  Future<List<SyncQueueItem>> getPendingSyncItems(
    String userId, {
    int limit = 10,
  }) async {
    return items
        .where((item) => !deletedIds.contains(item.id))
        .take(limit)
        .toList();
  }

  @override
  Future<void> deleteCompletedSyncItems(List<int> itemIds) async {
    deletedIds.addAll(itemIds);
  }

  final List<SyncQueueItemsCompanion> queueUpdates = [];
  final List<(String, String)> statusUpdates = [];

  @override
  Future<void> updateSyncQueueItem(SyncQueueItemsCompanion companion) async {
    queueUpdates.add(companion);
  }

  @override
  Future<void> updateSyncStatus(
    String expenseId,
    String status, {
    String? errorMessage,
  }) async {
    statusUpdates.add((expenseId, status));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBatchSyncService implements BatchSyncService {
  final List<String> createdIds = [];

  /// When true the next batch fails with a check violation (23514).
  bool failNext = false;

  @override
  Future<Map<String, SyncItemResult>> batchCreateExpenses(
    List<SyncQueueItem> items,
  ) async {
    final fail = failNext;
    failNext = false;
    return {
      for (final item in items)
        item.entityId: () {
          createdIds.add(item.entityId);
          return fail
              ? SyncItemResult(
                  id: item.entityId,
                  success: false,
                  errorCode: '23514',
                  errorMessage:
                      'violates check constraint "expenses_date_check"',
                )
              : SyncItemResult(id: item.entityId, success: true);
        }(),
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SyncQueueItem _item(
  int id, {
  DateTime? nextRetryAt,
  String syncStatus = 'pending',
  int? retryCount,
}) {
  return SyncQueueItem(
    id: id,
    userId: 'user-1',
    operation: 'create',
    entityType: 'expense',
    entityId: 'expense-$id',
    payload: '{}',
    syncStatus: syncStatus,
    retryCount: retryCount ?? (nextRetryAt == null ? 0 : 1),
    nextRetryAt: nextRetryAt,
    priority: 0,
    createdAt: DateTime(2026, 9, 1).add(Duration(minutes: id)),
  );
}

void main() {
  group('check_violation 23514 (issue #66, AC4)', () {
    test('a failed item is kept in the queue and retried on the next run',
        () async {
      final local = _FakeLocalDataSource([
        _item(1, syncStatus: 'failed', retryCount: 4),
      ]);
      final batch = _FakeBatchSyncService()..failNext = true;
      final processor = SyncQueueProcessor(
        localDataSource: local,
        batchSyncService: batch,
        userId: 'user-1',
      );

      final first = await processor.processQueue();
      expect(first.failed, 1);
      expect(local.deletedIds, isEmpty);
      expect(local.queueUpdates, hasLength(1));
      expect(local.queueUpdates.single.syncStatus.value, 'failed');
      expect(local.statusUpdates.last, ('expense-1', 'failed'));

      final second = await processor.processQueue();
      expect(second.successful, 1);
      expect(batch.createdIds, ['expense-1', 'expense-1']);
      expect(local.deletedIds, [1]);
      expect(local.statusUpdates.last, ('expense-1', 'completed'));
    });

    test('a pending item whose backoff expired is sent on the next run',
        () async {
      final local = _FakeLocalDataSource([
        _item(
          2,
          retryCount: 1,
          nextRetryAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      ]);
      final batch = _FakeBatchSyncService();

      final result = await SyncQueueProcessor(
        localDataSource: local,
        batchSyncService: batch,
        userId: 'user-1',
      ).processQueue();

      expect(result.successful, 1);
      expect(local.deletedIds, [2]);
    });
  });

  test('items waiting for a retry do not block newer expenses', () async {
    final later = DateTime.now().add(const Duration(minutes: 5));
    final items = [
      for (var i = 1; i <= 10; i++) _item(i, nextRetryAt: later),
      for (var i = 11; i <= 25; i++) _item(i),
    ];
    final local = _FakeLocalDataSource(items);
    final batch = _FakeBatchSyncService();

    final result = await SyncQueueProcessor(
      localDataSource: local,
      batchSyncService: batch,
      userId: 'user-1',
    ).processQueue();

    expect(result.successful, 15);
    expect(batch.createdIds, [for (var i = 11; i <= 25; i++) 'expense-$i']);
    expect(local.deletedIds, [for (var i = 11; i <= 25; i++) i]);
  });
}
