import 'dart:async';
import 'package:workmanager/workmanager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/datasources/offline_expense_local_datasource.dart';
import '../data/local/offline_database.dart';
import '../domain/services/batch_sync_service.dart';
import '../domain/services/sync_queue_processor.dart';

/// T120-T129: Background Sync Service using WorkManager
///
/// Features:
/// - Periodic background sync (every 15 minutes)
/// - Constraints: network available, not low battery
/// - Runs even when app is closed
/// - Battery efficient
class BackgroundSyncService {
  static const String taskName = 'offline-expense-sync';
  static const Duration syncInterval = Duration(minutes: 15);

  /// T120: Initialize WorkManager for background sync
  ///
  /// NOTE (issue #69): this service is not used. Workmanager accepts a single
  /// callback dispatcher: the app's only one is
  /// `backgroundCallbackDispatcher` in lib/app/background_tasks.dart. Do NOT
  /// call this `initialize` together with `BackgroundTasks.initialize`.
  static Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
  }

  /// T121: Register periodic background sync task
  static Future<void> registerPeriodicSync() async {
    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: syncInterval,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }

  /// T122: Cancel background sync
  static Future<void> cancelPeriodicSync() async {
    await Workmanager().cancelByUniqueName(taskName);
  }

  /// T123: Check if background sync is registered
  static Future<bool> isRegistered() async {
    // WorkManager doesn't provide direct API to check registration
    // This is a workaround - we'll assume it's registered if we set it up
    return true;
  }
}

/// T124: WorkManager callback dispatcher
///
/// This function runs in a separate isolate and performs the sync
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Initialize Supabase (required for background isolate)
      await Supabase.initialize(
        url: const String.fromEnvironment('SUPABASE_URL'),
        anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
      );

      // Get current user
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        return Future.value(true); // User not authenticated, skip
      }

      // Initialize dependencies
      final database = OfflineDatabase();
      final localDataSource = OfflineExpenseLocalDataSourceImpl(
        database: database,
        uuid: const Uuid(),
      );
      final batchSyncService = BatchSyncService(
        supabase: Supabase.instance.client,
      );
      final processor = SyncQueueProcessor(
        localDataSource: localDataSource,
        batchSyncService: batchSyncService,
        userId: userId,
      );

      // T125: Execute background sync
      final result = await processor.processQueue();

      // T126: Log result
      print('Background sync completed: $result');

      // Clean up
      await database.close();

      return Future.value(true);
    } catch (e) {
      // T127: Handle errors
      print('Background sync error: $e');
      return Future.value(false);
    }
  });
}

/// T128: Platform-specific setup helpers
class BackgroundSyncSetup {
  /// Android-specific setup (if needed)
  static Future<void> setupAndroid() async {
    // WorkManager handles Android setup automatically
  }

  /// iOS-specific setup (if needed)
  static Future<void> setupIOS() async {
    // Background fetch configuration
    // Note: iOS has stricter background execution rules
    // User should enable background refresh in Settings
  }
}
