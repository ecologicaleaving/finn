import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:uuid/uuid.dart';
import 'package:workmanager/workmanager.dart';

import '../core/database/daos/recurring_expenses_dao.dart';
import '../core/services/recurring_expense_scheduler.dart';
import '../features/expenses/domain/services/recurrence_calculator.dart';
import '../features/offline/data/local/offline_database.dart';

/// Background tasks initialization and management.
///
/// Handles:
/// - Recurring expense instance generation
/// - Workmanager callback dispatcher setup
class BackgroundTasks {
  /// Initialize workmanager for all background tasks.
  ///
  /// Must be called once during app initialization in main().
  static Future<void> initialize() async {
    await Workmanager().initialize(
      recurringExpenseCallbackDispatcher,
      isInDebugMode: false, // Set to true for debugging
    );
  }

  /// Register all background tasks.
  ///
  /// Should be called after user login to activate background processing.
  static Future<void> registerAllTasks() async {
    // Register recurring expense instance generation
    await RecurringExpenseScheduler.registerPeriodicCheck();

    // Future: Add other background tasks here
  }

  /// Cancel all background tasks.
  ///
  /// Should be called on user logout or when user disables features.
  static Future<void> cancelAllTasks() async {
    await RecurringExpenseScheduler.cancelPeriodicCheck();

    // Future: Cancel other background tasks here
  }
}

/// Workmanager callback dispatcher for recurring expense instance generation.
///
/// This function runs in a separate isolate and:
/// 1. Checks all active recurring expense templates
/// 2. Creates expense instances for templates that are due
/// 3. Updates template metadata (lastInstanceCreatedAt, nextDueDate)
///
/// Runs every 15 minutes (platform minimum).
@pragma('vm:entry-point')
void recurringExpenseCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Initialize timezone data for the background isolate
      tz_data.initializeTimeZones();

      // Use UTC as default for background tasks
      tz.setLocalLocation(tz.getLocation('UTC'));

      print('Recurring expense task started: $task');

      // Initialize database
      final database = OfflineDatabase();
      final dao = RecurringExpensesDao(database);

      final now = DateTime.now();

      // Get all due recurring expenses
      final dueTemplates = await dao.getDueRecurringExpenses(now);

      print('Found ${dueTemplates.length} due recurring expenses');

      int instancesCreated = 0;

      // Process each due template
      for (final template in dueTemplates) {
        try {
          // Double-check template is due and not paused
          if (template.isPaused) {
            print('Skipping paused template: ${template.id}');
            continue;
          }

          final nextDueDate = template.nextDueDate;
          if (nextDueDate == null) {
            print('Template ${template.id} has no nextDueDate, skipping');
            continue;
          }

          // Check if due now using RecurrenceCalculator
          final isDue = RecurrenceCalculator.isDueNow(nextDueDate, now);
          if (!isDue) {
            print('Template ${template.id} not due yet, skipping');
            continue;
          }

          // Create expense instance
          final expenseId = const Uuid().v4();

          await database.into(database.offlineExpenses).insert(
            OfflineExpensesCompanion.insert(
              id: expenseId,
              userId: template.userId,
              amount: template.amount,
              date: nextDueDate, // Use scheduled due date
              categoryId: template.categoryId,
              merchant: Value(template.merchant),
              notes: Value(template.notes),
              isGroupExpense: template.isGroupExpense,
              reimbursementStatus: Value(template.defaultReimbursementStatus.value),
              recurringExpenseId: Value(template.id),
              isRecurringInstance: const Value(true),
              syncStatus: const Value('pending'),
              retryCount: const Value(0),
              hasConflict: const Value(false),
              localCreatedAt: now,
              localUpdatedAt: now,
            ),
          );

          // Create instance mapping
          await dao.insertRecurringExpenseInstance(
            RecurringExpenseInstancesCompanion.insert(
              recurringExpenseId: template.id,
              expenseId: expenseId,
              scheduledDate: nextDueDate,
              createdAt: now,
            ),
          );

          // Calculate next due date
          final newNextDueDate = RecurrenceCalculator.calculateNextDueDate(
            anchorDate: template.anchorDate,
            frequency: template.frequency,
            lastCreated: now,
          );

          // Update template
          await dao.updateAfterInstanceCreation(
            template.id,
            now, // lastInstanceCreatedAt
            newNextDueDate, // nextDueDate
          );

          instancesCreated++;
          print('Created expense instance for template: ${template.id}');
        } catch (e) {
          print('Error creating instance for template ${template.id}: $e');
          // Continue with next template even if one fails
          continue;
        }
      }

      print('Recurring expense task completed: created $instancesCreated instances');

      // Clean up
      await database.close();

      return Future.value(true);
    } catch (e) {
      print('Recurring expense task error: $e');
      return Future.value(false);
    }
  });
}
