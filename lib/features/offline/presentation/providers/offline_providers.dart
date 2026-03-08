import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as legacy;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../expenses/data/datasources/expense_local_cache_datasource.dart';
import '../../data/datasources/offline_expense_local_datasource.dart';
import '../../data/local/offline_database.dart';
import '../../domain/entities/offline_expense_entity.dart';
import '../../domain/services/batch_sync_service.dart';
import '../../domain/services/sync_queue_processor.dart';
import '../../../../shared/services/connectivity_service.dart';
import '../widgets/sync_progress_indicator.dart';

part 'offline_providers.g.dart';

/// Provides the offline database instance
@riverpod
OfflineDatabase offlineDatabase(OfflineDatabaseRef ref) {
  final db = OfflineDatabase();
  ref.onDispose(() => db.close());
  return db;
}

/// Provides the offline expense local data source
@riverpod
OfflineExpenseLocalDataSource offlineExpenseLocalDataSource(
  OfflineExpenseLocalDataSourceRef ref,
) {
  final database = ref.watch(offlineDatabaseProvider);
  return OfflineExpenseLocalDataSourceImpl(
    database: database,
    uuid: const Uuid(),
  );
}

final expenseLocalCacheDataSourceProvider = legacy.Provider<ExpenseLocalCacheDataSource>((ref) {
  return HiveExpenseLocalCacheDataSource();
});

/// Provides the batch sync service
@riverpod
BatchSyncService batchSyncService(BatchSyncServiceRef ref) {
  final supabase = Supabase.instance.client;
  return BatchSyncService(supabase: supabase);
}

/// Provides the sync queue processor for current user
@riverpod
SyncQueueProcessor syncQueueProcessor(SyncQueueProcessorRef ref) {
  final localDataSource = ref.watch(offlineExpenseLocalDataSourceProvider);
  final batchSyncService = ref.watch(batchSyncServiceProvider);
  final localCacheDataSource = ref.watch(expenseLocalCacheDataSourceProvider);

  // Get current user ID from Supabase auth
  final userId = Supabase.instance.client.auth.currentUser?.id;

  if (userId == null) {
    throw StateError('User must be authenticated to use sync queue processor');
  }

  return SyncQueueProcessor(
    localDataSource: localDataSource,
    batchSyncService: batchSyncService,
    userId: userId,
    localCacheDataSource: localCacheDataSource,
  );
}

/// Stream provider for all offline expenses
@riverpod
Stream<List<OfflineExpenseEntity>> offlineExpenses(
  OfflineExpensesRef ref,
) async* {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return;

  final dataSource = ref.watch(offlineExpenseLocalDataSourceProvider);

  // Initial load
  yield await dataSource.getAllOfflineExpenses(userId);

  // Watch for changes (poll every 5 seconds)
  // In production, you might use Drift's watch() streams
  await for (final _ in Stream.periodic(const Duration(seconds: 5))) {
    yield await dataSource.getAllOfflineExpenses(userId);
  }
}

/// Provider for pending sync count
@riverpod
Future<int> pendingSyncCount(PendingSyncCountRef ref) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return 0;

  final dataSource = ref.watch(offlineExpenseLocalDataSourceProvider);
  return await dataSource.getPendingSyncCount(userId);
}

/// Provider for last sync timestamp (Feature 012-expense-improvements T026)
/// Returns null if never synced, otherwise returns DateTime of last successful sync
@riverpod
Future<DateTime?> lastSyncTime(LastSyncTimeRef ref) async {
  // TODO: Implement persistent storage of last sync time
  // For now, return null (will always show as potentially stale)
  // In production, this should:
  // 1. Read from shared preferences or Hive
  // 2. Update after successful sync operations
  // 3. Clear on logout
  return null;
}

/// Provider to trigger manual sync
@riverpod
class SyncTrigger extends _$SyncTrigger {
  @override
  FutureOr<void> build() async {
    // Auto-sync when connectivity changes to online
    ref.listen(
      connectivityServiceProvider,
      (previous, next) {
        next.whenData((status) {
          if (status == NetworkStatus.online &&
              previous?.value != NetworkStatus.online) {
            // Network restored - trigger sync
            sync();
          }
        });
      },
    );
  }

  /// Manually trigger sync
  Future<void> sync() async {
    state = const AsyncLoading();

    try {
      final processor = ref.read(syncQueueProcessorProvider);
      final result = await processor.processQueue();

      // Refresh pending count
      ref.invalidate(pendingSyncCountProvider);

      state = AsyncData(null);

      // Log result
      print('Sync completed: $result');
    } catch (e, stack) {
      state = AsyncError(e, stack);
    }
  }
}

/// Provider for sync status indicator
@riverpod
class SyncStatus extends _$SyncStatus {
  @override
  Future<SyncStatusState> build() async {
    // Watch connectivity
    final connectivity = ref.watch(connectivityServiceProvider);
    final pendingCount = await ref.watch(pendingSyncCountProvider.future);

    return connectivity.when(
      data: (status) {
        if (status == NetworkStatus.offline && pendingCount > 0) {
          return SyncStatusState.offlineWithPending(pendingCount);
        } else if (status == NetworkStatus.online && pendingCount > 0) {
          return SyncStatusState.syncing(pendingCount);
        } else if (pendingCount == 0) {
          return const SyncStatusState.allSynced();
        }
        return const SyncStatusState.idle();
      },
      loading: () => const SyncStatusState.idle(),
      error: (_, __) => const SyncStatusState.idle(),
    );
  }
}

/// Sync status state
class SyncStatusState {
  final String status; // 'idle', 'offline_pending', 'syncing', 'all_synced'
  final int pendingCount;

  const SyncStatusState({
    required this.status,
    this.pendingCount = 0,
  });

  const SyncStatusState.idle() : this(status: 'idle');

  const SyncStatusState.offlineWithPending(int count)
      : this(status: 'offline_pending', pendingCount: count);

  const SyncStatusState.syncing(int count)
      : this(status: 'syncing', pendingCount: count);

  const SyncStatusState.allSynced() : this(status: 'all_synced');

  bool get isOfflineWithPending => status == 'offline_pending';
  bool get isSyncing => status == 'syncing';
  bool get isAllSynced => status == 'all_synced';
}

/// T083: Provider for sync state (tracks progress)
@riverpod
class SyncStateNotifier extends _$SyncStateNotifier {
  @override
  SyncState build() {
    return const SyncState();
  }

  /// Start sync operation
  void startSync() {
    state = state.copyWith(isSyncing: true);
  }

  /// Complete sync with result
  void completeSync(SyncResult result) {
    state = SyncState(
      isSyncing: false,
      lastResult: result,
    );
  }

  /// Clear last result
  void clearResult() {
    state = const SyncState();
  }
}

/// Convenience provider for current sync state
@riverpod
SyncState syncState(SyncStateRef ref) {
  return ref.watch(syncStateNotifierProvider);
}

/// T084: Enhanced manual sync provider with progress tracking
extension SyncTriggerExtensions on SyncTrigger {
  Future<void> manualSync() async {
    // Track sync progress
    ref.read(syncStateNotifierProvider.notifier).startSync();

    await sync();

    // Get the result from the last sync
    final pendingCount = await ref.read(pendingSyncCountProvider.future);
    final result = SyncResult(
      processed: 0,
      successful: 0,
      failed: pendingCount,
      conflicts: 0,
    );

    ref.read(syncStateNotifierProvider.notifier).completeSync(result);
  }
}
