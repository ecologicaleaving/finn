import 'package:workmanager/workmanager.dart';

/// Service for scheduling recurring expense instance generation using workmanager.
///
/// Registers periodic background tasks to check for due recurring expenses
/// and create expense instances automatically.
class RecurringExpenseScheduler {
  /// Unique task identifier for recurring expense checks
  static const String taskName = 'recurring-expense-creation';

  /// Task interval (15 minutes - platform minimum)
  static const Duration checkInterval = Duration(minutes: 15);

  /// Register periodic task to check for due recurring expenses.
  ///
  /// This task runs every 15 minutes (platform minimum) and:
  /// - Checks all active recurring expense templates
  /// - Creates expense instances for templates that are due
  /// - Updates template metadata (lastInstanceCreatedAt, nextDueDate)
  ///
  /// Platform behavior:
  /// - **Android**: WorkManager guarantees execution (may delay if battery low)
  /// - **iOS**: BackgroundFetch is less reliable (may skip if app not used)
  ///
  /// Note: User must open app at least once to register the task.
  static Future<void> registerPeriodicCheck() async {
    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: checkInterval,
      constraints: Constraints(
        networkType: NetworkType.not_required, // Can work offline
        requiresBatteryNotLow: true, // Don't drain battery
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep, // Don't duplicate
    );
  }

  /// Cancel the recurring expense background task.
  ///
  /// Stops automatic expense instance generation.
  /// Does NOT delete existing recurring expenses or instances.
  ///
  /// Use cases:
  /// - User disables recurring expenses feature
  /// - User logs out
  /// - Testing/debugging
  static Future<void> cancelPeriodicCheck() async {
    await Workmanager().cancelByUniqueName(taskName);
  }

  /// Register a one-time immediate task for testing.
  ///
  /// Useful for development and debugging - executes immediately
  /// instead of waiting for the 15-minute interval.
  ///
  /// Note: This is for testing only. Production uses periodic task.
  static Future<void> registerImmediateCheck() async {
    await Workmanager().registerOneOffTask(
      '${taskName}_immediate',
      taskName,
      constraints: Constraints(
        networkType: NetworkType.not_required,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  /// Check if the periodic task is currently registered.
  ///
  /// Note: Workmanager doesn't provide a direct way to query task status,
  /// so this is a best-effort check based on re-registration behavior.
  ///
  /// Returns true if we believe the task is registered, false otherwise.
  static Future<bool> isTaskRegistered() async {
    // Workmanager doesn't expose task query API
    // Best practice: Assume registered after calling registerPeriodicCheck()
    // Use ExistingWorkPolicy.keep to prevent duplicates
    return true; // Placeholder - actual implementation may vary
  }
}
