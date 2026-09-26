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

  @override
  Future<void> updateSyncStatus(
    String expenseId,
    String status, {
    String? errorMessage,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBatchSyncService implements BatchSyncService {
  final List<String> createdIds = [];

  @override
  Future<Map<String, SyncItemResult>> batchCreateExpenses(
    List<SyncQueueItem> items,
  ) async {
    return {
      for (final item in items)
        item.entityId: () {
          createdIds.add(item.entityId);
          return SyncItemResult(id: item.entityId, success: true);
        }(),
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SyncQueueItem _item(int id, {DateTime? nextRetryAt}) {
  return SyncQueueItem(
    id: id,
    userId: 'user-1',
    operation: 'create',
    entityType: 'expense',
    entityId: 'expense-$id',
    payload: '{}',
    syncStatus: 'pending',
    retryCount: nextRetryAt == null ? 0 : 1,
    nextRetryAt: nextRetryAt,
    priority: 0,
    createdAt: DateTime(2026, 9, 1).add(Duration(minutes: id)),
  );
}

void main() {
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
