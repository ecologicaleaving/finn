import 'dart:async';

import '../../../expenses/data/datasources/expense_local_cache_datasource.dart';
import '../../data/datasources/offline_expense_local_datasource.dart';
import '../../data/local/offline_database.dart';
import '../../data/models/sync_queue_item_model.dart';
import 'batch_sync_service.dart';

/// Processes sync queue in batches with retry logic
///
/// Features:
/// - Batch processing (max 10 items per batch)
/// - Exponential backoff retry (30s, 2min, 5min)
/// - Conflict detection and handling
/// - Progress tracking
class SyncQueueProcessor {
  final OfflineExpenseLocalDataSource _localDataSource;
  final BatchSyncService _batchSyncService;
  final String _userId;
  final ExpenseLocalCacheDataSource? _localCacheDataSource;

  // Retry delays in seconds (30s, 2min, 5min)
  static const List<int> _retryDelays = [30, 120, 300];
  static const int _batchSize = 10;

  bool _isSyncing = false;

  SyncQueueProcessor({
    required OfflineExpenseLocalDataSource localDataSource,
    required BatchSyncService batchSyncService,
    required String userId,
    ExpenseLocalCacheDataSource? localCacheDataSource,
  })  : _localDataSource = localDataSource,
        _batchSyncService = batchSyncService,
        _userId = userId,
        _localCacheDataSource = localCacheDataSource;

  /// Check if currently syncing
  bool get isSyncing => _isSyncing;

  /// Process the entire sync queue
  Future<SyncQueueResult> processQueue() async {
    if (_isSyncing) {
      return SyncQueueResult.alreadySyncing();
    }

    _isSyncing = true;
    try {
      return await _processSyncQueue();
    } finally {
      _isSyncing = false;
    }
  }

  Future<SyncQueueResult> _processSyncQueue() async {
    var totalProcessed = 0;
    var totalSuccessful = 0;
    var totalFailed = 0;
    var totalConflicts = 0;

    // Keep processing batches until queue is empty
    while (true) {
      // Get next batch of pending items
      final pendingItems = await _localDataSource.getPendingSyncItems(
        _userId,
        limit: _batchSize,
      );

      if (pendingItems.isEmpty) break;

      // Filter items ready to retry (check exponential backoff)
      final readyItems = pendingItems.where((item) {
        final model = SyncQueueItemModel(item);
        return model.isReadyToRetry();
      }).toList();

      if (readyItems.isEmpty) break;

      // Group by operation type
      final creates = readyItems.where((i) => i.operation == 'create').toList();
      final updates = readyItems.where((i) => i.operation == 'update').toList();
      final deletes = readyItems.where((i) => i.operation == 'delete').toList();

      // Process each operation type
      final batchResults = <String, SyncItemResult>{};

      if (creates.isNotEmpty) {
        batchResults.addAll(await _batchSyncService.batchCreateExpenses(creates));
      }

      if (updates.isNotEmpty) {
        batchResults.addAll(await _batchSyncService.batchUpdateExpenses(updates));
      }

      if (deletes.isNotEmpty) {
        batchResults.addAll(await _batchSyncService.batchDeleteExpenses(deletes));
      }

      // Update queue items based on results
      await _updateQueueItems(readyItems, batchResults);

      // Update statistics
      totalProcessed += batchResults.length;
      totalSuccessful += batchResults.values.where((r) => r.success).length;
      totalFailed += batchResults.values.where((r) => !r.success && !r.isConflict).length;
      totalConflicts += batchResults.values.where((r) => r.isConflict).length;

      // If batch was not full, we're done
      if (readyItems.length < _batchSize) break;
    }

    return SyncQueueResult(
      processed: totalProcessed,
      successful: totalSuccessful,
      failed: totalFailed,
      conflicts: totalConflicts,
    );
  }

  Future<void> _updateQueueItems(
    List<SyncQueueItem> items,
    Map<String, SyncItemResult> results,
  ) async {
    for (final item in items) {
      final result = results[item.entityId];
      if (result == null) continue;

      if (result.success) {
        // Success - delete from queue
        await _localDataSource.deleteCompletedSyncItems([item.id]);

        // Update offline expense status if it exists
        try {
          await _localDataSource.updateSyncStatus(
            item.entityId,
            'completed',
          );
          await _localCacheDataSource?.updateExpenseSyncStatus(
            _userId,
            item.entityId,
            'completed',
          );
        } catch (e) {
          // Expense might already be deleted, ignore
        }
      } else if (result.isConflict) {
        // Conflict - mark offline expense
        await _localDataSource.updateSyncStatus(
          item.entityId,
          'conflict',
          errorMessage: 'Server version is newer',
        );
        await _localCacheDataSource?.updateExpenseSyncStatus(
          _userId,
          item.entityId,
          'conflict',
        );

        // Delete from queue - conflicts are handled separately
        await _localDataSource.deleteCompletedSyncItems([item.id]);

        // TODO: Store conflict for User Story 4
      } else {
        // Failure - update with retry logic
        final companion = SyncQueueItemModel.markAsFailed(
          item,
          result.errorMessage ?? 'Unknown error',
          retryDelays: _retryDelays,
        );

        await _localDataSource.updateSyncQueueItem(companion);

        // Update offline expense status
        await _localDataSource.updateSyncStatus(
          item.entityId,
          item.retryCount + 1 > _retryDelays.length ? 'failed' : 'pending',
          errorMessage: result.errorMessage,
        );
        await _localCacheDataSource?.updateExpenseSyncStatus(
          _userId,
          item.entityId,
          item.retryCount + 1 > _retryDelays.length ? 'failed' : 'pending',
        );
      }
    }
  }
}

/// Result of processing sync queue
class SyncQueueResult {
  final int processed;
  final int successful;
  final int failed;
  final int conflicts;

  SyncQueueResult({
    required this.processed,
    required this.successful,
    required this.failed,
    required this.conflicts,
  });

  factory SyncQueueResult.alreadySyncing() {
    return SyncQueueResult(
      processed: 0,
      successful: 0,
      failed: 0,
      conflicts: 0,
    );
  }

  bool get hasFailures => failed > 0;
  bool get hasConflicts => conflicts > 0;
  bool get allSuccess => processed == successful;

  @override
  String toString() {
    return 'SyncQueueResult(processed: $processed, successful: $successful, '
        'failed: $failed, conflicts: $conflicts)';
  }
}
