import 'package:drift/drift.dart';
import '../drift/tables/recurring_expenses_table.dart';
import '../drift/tables/recurring_expense_instances_table.dart';
import '../../../features/offline/data/local/offline_database.dart';

part 'recurring_expenses_dao.g.dart';

/// Data Access Object for recurring_expenses table operations.
///
/// Provides CRUD operations and specialized queries for recurring expense templates.
@DriftAccessor(tables: [RecurringExpenses, RecurringExpenseInstances])
class RecurringExpensesDao extends DatabaseAccessor<OfflineDatabase>
    with _$RecurringExpensesDaoMixin {
  RecurringExpensesDao(super.db);

  // =========================================================================
  // CREATE
  // =========================================================================

  /// Insert a new recurring expense template
  Future<int> insertRecurringExpense(RecurringExpensesCompanion entry) {
    return into(recurringExpenses).insert(entry);
  }

  /// Insert a new recurring expense instance mapping
  Future<int> insertRecurringExpenseInstance(
      RecurringExpenseInstancesCompanion entry) {
    return into(recurringExpenseInstances).insert(entry);
  }

  // =========================================================================
  // READ
  // =========================================================================

  /// Get all recurring expenses for a user
  Future<List<RecurringExpenseData>> getAllRecurringExpenses(String userId) {
    return (select(recurringExpenses)
          ..where((tbl) => tbl.userId.equals(userId)))
        .get();
  }

  /// Get all active (not paused) recurring expenses for a user
  Future<List<RecurringExpenseData>> getActiveRecurringExpenses(
      String userId) {
    return (select(recurringExpenses)
          ..where((tbl) =>
              tbl.userId.equals(userId) & tbl.isPaused.equals(false)))
        .get();
  }

  /// Get all paused recurring expenses for a user
  Future<List<RecurringExpenseData>> getPausedRecurringExpenses(
      String userId) {
    return (select(recurringExpenses)
          ..where((tbl) => tbl.userId.equals(userId) & tbl.isPaused.equals(true)))
        .get();
  }

  /// Get recurring expenses with budget reservation enabled
  Future<List<RecurringExpenseData>> getRecurringExpensesWithBudgetReservation(
      String userId) {
    return (select(recurringExpenses)
          ..where((tbl) =>
              tbl.userId.equals(userId) &
              tbl.budgetReservationEnabled.equals(true) &
              tbl.isPaused.equals(false)))
        .get();
  }

  /// Get a single recurring expense by ID
  Future<RecurringExpenseData?> getRecurringExpenseById(String id) {
    return (select(recurringExpenses)..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();
  }

  /// Get recurring expenses due for instance creation (background task query)
  ///
  /// Returns all active templates where nextDueDate <= now
  Future<List<RecurringExpenseData>> getDueRecurringExpenses(DateTime now) {
    return (select(recurringExpenses)
          ..where((tbl) =>
              tbl.isPaused.equals(false) &
              tbl.nextDueDate.isSmallerOrEqualValue(now)))
        .get();
  }

  /// Get all instances (expense IDs) generated from a recurring template
  Future<List<RecurringExpenseInstanceData>> getInstancesForTemplate(
      String recurringExpenseId) {
    return (select(recurringExpenseInstances)
          ..where((tbl) => tbl.recurringExpenseId.equals(recurringExpenseId)))
        .get();
  }

  /// Check if an expense is a recurring instance
  Future<RecurringExpenseInstanceData?> getInstanceMapping(String expenseId) {
    return (select(recurringExpenseInstances)
          ..where((tbl) => tbl.expenseId.equals(expenseId)))
        .getSingleOrNull();
  }

  // =========================================================================
  // UPDATE
  // =========================================================================

  /// Update a recurring expense template
  Future<bool> updateRecurringExpense(
      String id, RecurringExpensesCompanion entry) async {
    final updated = await (update(recurringExpenses)
          ..where((tbl) => tbl.id.equals(id)))
        .write(entry);
    return updated > 0;
  }

  /// Pause a recurring expense
  Future<bool> pauseRecurringExpense(String id) async {
    final updated = await (update(recurringExpenses)
          ..where((tbl) => tbl.id.equals(id)))
        .write(
      const RecurringExpensesCompanion(
        isPaused: Value(true),
        updatedAt: Value.absent(), // Will be set by trigger
      ),
    );
    return updated > 0;
  }

  /// Resume a paused recurring expense
  Future<bool> resumeRecurringExpense(
      String id, DateTime nextDueDate) async {
    final updated = await (update(recurringExpenses)
          ..where((tbl) => tbl.id.equals(id)))
        .write(
      RecurringExpensesCompanion(
        isPaused: const Value(false),
        nextDueDate: Value(nextDueDate),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return updated > 0;
  }

  /// Update template after creating an instance
  ///
  /// Updates lastInstanceCreatedAt and nextDueDate
  Future<bool> updateAfterInstanceCreation(
    String id,
    DateTime lastInstanceCreatedAt,
    DateTime? nextDueDate,
  ) async {
    final updated = await (update(recurringExpenses)
          ..where((tbl) => tbl.id.equals(id)))
        .write(
      RecurringExpensesCompanion(
        lastInstanceCreatedAt: Value(lastInstanceCreatedAt),
        nextDueDate: Value(nextDueDate),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return updated > 0;
  }

  // =========================================================================
  // DELETE
  // =========================================================================

  /// Delete a recurring expense template
  ///
  /// CASCADE will automatically delete related recurring_expense_instances
  Future<int> deleteRecurringExpense(String id) {
    return (delete(recurringExpenses)..where((tbl) => tbl.id.equals(id))).go();
  }

  /// Delete all instance mappings for a template
  ///
  /// Used when deleting a template with deleteInstances=true
  Future<int> deleteInstanceMappingsForTemplate(String recurringExpenseId) {
    return (delete(recurringExpenseInstances)
          ..where((tbl) => tbl.recurringExpenseId.equals(recurringExpenseId)))
        .go();
  }

  /// Delete a specific instance mapping
  Future<int> deleteInstanceMapping(String expenseId) {
    return (delete(recurringExpenseInstances)
          ..where((tbl) => tbl.expenseId.equals(expenseId)))
        .go();
  }

  // =========================================================================
  // WATCH (Reactive Queries)
  // =========================================================================

  /// Watch all recurring expenses for a user (reactive)
  Stream<List<RecurringExpenseData>> watchRecurringExpenses(String userId) {
    return (select(recurringExpenses)
          ..where((tbl) => tbl.userId.equals(userId)))
        .watch();
  }

  /// Watch a single recurring expense by ID (reactive)
  Stream<RecurringExpenseData?> watchRecurringExpense(String id) {
    return (select(recurringExpenses)..where((tbl) => tbl.id.equals(id)))
        .watchSingleOrNull();
  }

  /// Watch active recurring expenses (reactive)
  Stream<List<RecurringExpenseData>> watchActiveRecurringExpenses(
      String userId) {
    return (select(recurringExpenses)
          ..where((tbl) =>
              tbl.userId.equals(userId) & tbl.isPaused.equals(false)))
        .watch();
  }
}
