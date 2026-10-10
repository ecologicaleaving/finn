import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:workmanager/workmanager.dart';

import '../core/services/recurring_expense_scheduler.dart';
import '../core/services/recurring_instance_generator.dart';
import '../features/offline/data/local/offline_database.dart';

/// SharedPreferences key where main() stores the device timezone identifier,
/// so the background isolate uses the same local day as the foreground app.
const String kDeviceTimezonePrefsKey = 'device_timezone';

/// Background tasks initialization and management.
///
/// Workmanager accepts ONE callback dispatcher only: every background task
/// of the app is routed through [backgroundCallbackDispatcher]. Never call
/// `Workmanager().initialize` anywhere else (e.g. BackgroundSyncService).
class BackgroundTasks {
  /// Task names handled by the recurring instance generation.
  static const Set<String> recurringTaskNames = {
    RecurringExpenseScheduler.taskName,
    '${RecurringExpenseScheduler.taskName}_immediate',
  };

  /// Initialize workmanager for all background tasks.
  ///
  /// Must be called once during app initialization in main().
  static Future<void> initialize() async {
    await Workmanager().initialize(backgroundCallbackDispatcher);
  }

  /// Register all background tasks.
  static Future<void> registerAllTasks() async {
    await RecurringExpenseScheduler.registerPeriodicCheck();
  }

  /// Cancel all background tasks.
  ///
  /// Not called on logout: instances already generated stay in the queue of
  /// their owner and templates keep generating.
  static Future<void> cancelAllTasks() async {
    await RecurringExpenseScheduler.cancelPeriodicCheck();
  }

  /// Routes a background task by name. Returns whether the task succeeded.
  ///
  /// Unknown tasks return true (nothing to do, never retried). The
  /// [recurringRunner] parameter makes the routing testable.
  static Future<bool> runTask(
    String task, {
    Future<bool> Function()? recurringRunner,
  }) async {
    if (recurringTaskNames.contains(task)) {
      return (recurringRunner ?? runRecurringGeneration)();
    }
    return true;
  }

  /// Generates the due recurring instances, locally only (no Supabase in the
  /// background: the sync runs when the app is open).
  static Future<bool> runRecurringGeneration() async {
    OfflineDatabase? database;
    try {
      tz_data.initializeTimeZones();
      var zoneName = 'Europe/Rome';
      try {
        final prefs = await SharedPreferences.getInstance();
        zoneName = prefs.getString(kDeviceTimezonePrefsKey) ?? zoneName;
      } catch (_) {}
      try {
        tz.setLocalLocation(tz.getLocation(zoneName));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Europe/Rome'));
      }

      database = OfflineDatabase();
      final created =
          await RecurringInstanceGenerator.generate(database, DateTime.now());
      debugPrint('Recurring generation: created $created instances');
      return true;
    } catch (e) {
      debugPrint('Recurring generation error: $e');
      return false;
    } finally {
      try {
        await database?.close();
      } catch (_) {}
    }
  }
}

/// The single Workmanager callback dispatcher of the app.
///
/// Runs in a separate isolate and routes by task name.
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    return BackgroundTasks.runTask(task);
  });
}
