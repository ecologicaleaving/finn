import 'package:drift/drift.dart';
import '../../../offline/data/local/offline_database.dart';
import '../models/income_source_model.dart';
import '../models/savings_goal_model.dart';
import '../models/group_expense_assignment_model.dart';
import '../../domain/entities/income_source_entity.dart';

/// Local data source for budget management using Drift/SQLite
///
/// Provides CRUD operations for income sources, savings goals, and group expense
/// assignments using the local Drift database for offline-first functionality.
/// All operations are synchronous with the local database and return immediately.
abstract class BudgetLocalDataSource {
  // ============================================================================
  // Income Source Operations
  // ============================================================================

  /// Get all income sources for a user from local database
  Future<List<IncomeSourceModel>> getLocalIncomeSources(String userId);

  /// Get a specific income source by ID from local database
  Future<IncomeSourceModel?> getLocalIncomeSource(String id);

  /// Insert or update income source in local database
  Future<void> upsertLocalIncomeSource(IncomeSourceModel incomeSource);

  /// Insert or update multiple income sources in local database
  Future<void> upsertLocalIncomeSources(List<IncomeSourceModel> incomeSources);

  /// Align the user's local income sources to the server list, atomically:
  /// rows of [userId] not in [incomeSources] are deleted (an empty list
  /// removes them all), the others are inserted or updated. Rows of other
  /// users are never touched.
  Future<void> replaceLocalIncomeSources(
      String userId, List<IncomeSourceModel> incomeSources);

  /// Delete income source from local database
  Future<void> deleteLocalIncomeSource(String id);

  /// Delete all income sources for a user from local database
  Future<void> deleteAllLocalIncomeSources(String userId);

  /// Watch income sources for a user (returns stream for reactive updates)
  Stream<List<IncomeSourceModel>> watchLocalIncomeSources(String userId);

  // ============================================================================
  // Savings Goal Operations
  // ============================================================================

  /// Get savings goal for a user from local database
  Future<SavingsGoalModel?> getLocalSavingsGoal(String userId);

  /// Insert or update savings goal in local database
  Future<void> upsertLocalSavingsGoal(SavingsGoalModel savingsGoal);

  /// Delete savings goal from local database
  Future<void> deleteLocalSavingsGoal(String userId);

  /// Watch savings goal for a user (returns stream for reactive updates)
  Stream<SavingsGoalModel?> watchLocalSavingsGoal(String userId);

  // ============================================================================
  // Group Expense Assignment Operations
  // ============================================================================

  /// Get all group expense assignments for a user from local database
  Future<List<GroupExpenseAssignmentModel>> getLocalGroupExpenseAssignments(
      String userId);

  /// Get a specific group expense assignment by ID from local database
  Future<GroupExpenseAssignmentModel?> getLocalGroupExpenseAssignment(
      String id);

  /// Insert or update group expense assignment in local database
  Future<void> upsertLocalGroupExpenseAssignment(
      GroupExpenseAssignmentModel assignment);

  /// Insert or update multiple group expense assignments in local database
  Future<void> upsertLocalGroupExpenseAssignments(
      List<GroupExpenseAssignmentModel> assignments);

  /// Delete group expense assignment from local database
  Future<void> deleteLocalGroupExpenseAssignment(String id);

  /// Delete all group expense assignments for a user from local database
  Future<void> deleteAllLocalGroupExpenseAssignments(String userId);

  /// Watch group expense assignments for a user (returns stream)
  Stream<List<GroupExpenseAssignmentModel>> watchLocalGroupExpenseAssignments(
      String userId);

  // ============================================================================
  // Batch Operations
  // ============================================================================

  /// Clear all budget data for a user (income sources, savings goal, assignments)
  /// Used when user signs out or resets budget
  Future<void> clearAllLocalBudgetData(String userId);
}

/// Implementation of BudgetLocalDataSource using Drift
class BudgetLocalDataSourceImpl implements BudgetLocalDataSource {
  final OfflineDatabase database;

  BudgetLocalDataSourceImpl(this.database);

  // ============================================================================
  // Income Source Operations
  // ============================================================================

  @override
  Future<List<IncomeSourceModel>> getLocalIncomeSources(String userId) async {
    final query = database.select(database.incomeSources)
      ..where((t) => t.userId.equals(userId))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);

    final results = await query.get();
    return results.map(_incomeSourceDataToModel).toList();
  }

  @override
  Future<IncomeSourceModel?> getLocalIncomeSource(String id) async {
    final query = database.select(database.incomeSources)
      ..where((t) => t.id.equals(id));

    final result = await query.getSingleOrNull();
    return result != null ? _incomeSourceDataToModel(result) : null;
  }

  @override
  Future<void> upsertLocalIncomeSource(IncomeSourceModel incomeSource) async {
    await database.into(database.incomeSources).insertOnConflictUpdate(
          IncomeSourcesCompanion(
            id: Value(incomeSource.id),
            userId: Value(incomeSource.userId),
            type: Value(IncomeTypeExtension.fromString(incomeSource.type)),
            customTypeName: Value(incomeSource.customTypeName),
            amount: Value(incomeSource.amount),
            createdAt: Value(incomeSource.createdAt),
            updatedAt: Value(incomeSource.updatedAt),
          ),
        );
  }

  @override
  Future<void> upsertLocalIncomeSources(
      List<IncomeSourceModel> incomeSources) async {
    await database.batch((batch) {
      batch.insertAllOnConflictUpdate(
        database.incomeSources,
        incomeSources.map((model) => IncomeSourcesCompanion(
              id: Value(model.id),
              userId: Value(model.userId),
              type: Value(IncomeTypeExtension.fromString(model.type)),
              customTypeName: Value(model.customTypeName),
              amount: Value(model.amount),
              createdAt: Value(model.createdAt),
              updatedAt: Value(model.updatedAt),
            )),
      );
    });
  }

  @override
  Future<void> replaceLocalIncomeSources(
      String userId, List<IncomeSourceModel> incomeSources) async {
    final mine = incomeSources.where((m) => m.userId == userId).toList();
    final keepIds = mine.map((m) => m.id).toList();
    await database.transaction(() async {
      await (database.delete(database.incomeSources)
            ..where((t) => t.userId.equals(userId) & t.id.isNotIn(keepIds)))
          .go();
      await upsertLocalIncomeSources(mine);
    });
  }

  @override
  Future<void> deleteLocalIncomeSource(String id) async {
    await (database.delete(database.incomeSources)
          ..where((t) => t.id.equals(id)))
        .go();
  }

  @override
  Future<void> deleteAllLocalIncomeSources(String userId) async {
    await (database.delete(database.incomeSources)
          ..where((t) => t.userId.equals(userId)))
        .go();
  }

  @override
  Stream<List<IncomeSourceModel>> watchLocalIncomeSources(String userId) {
    final query = database.select(database.incomeSources)
      ..where((t) => t.userId.equals(userId))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);

    return query.watch().map(
          (results) => results.map(_incomeSourceDataToModel).toList(),
        );
  }

  // ============================================================================
  // Savings Goal Operations
  // ============================================================================

  @override
  Future<SavingsGoalModel?> getLocalSavingsGoal(String userId) async {
    final query = database.select(database.savingsGoals)
      ..where((t) => t.userId.equals(userId));

    final result = await query.getSingleOrNull();
    return result != null ? _savingsGoalDataToModel(result) : null;
  }

  @override
  Future<void> upsertLocalSavingsGoal(SavingsGoalModel savingsGoal) async {
    await database.into(database.savingsGoals).insertOnConflictUpdate(
          SavingsGoalsCompanion(
            id: Value(savingsGoal.id),
            userId: Value(savingsGoal.userId),
            amount: Value(savingsGoal.amount),
            originalAmount: Value(savingsGoal.originalAmount),
            adjustedAt: Value(savingsGoal.adjustedAt),
            createdAt: Value(savingsGoal.createdAt),
            updatedAt: Value(savingsGoal.updatedAt),
          ),
        );
  }

  @override
  Future<void> deleteLocalSavingsGoal(String userId) async {
    await (database.delete(database.savingsGoals)
          ..where((t) => t.userId.equals(userId)))
        .go();
  }

  @override
  Stream<SavingsGoalModel?> watchLocalSavingsGoal(String userId) {
    final query = database.select(database.savingsGoals)
      ..where((t) => t.userId.equals(userId));

    return query.watchSingleOrNull().map(
          (result) => result != null ? _savingsGoalDataToModel(result) : null,
        );
  }

  // ============================================================================
  // Group Expense Assignment Operations
  // ============================================================================

  @override
  Future<List<GroupExpenseAssignmentModel>> getLocalGroupExpenseAssignments(
      String userId) async {
    final query = database.select(database.groupExpenseAssignments)
      ..where((t) => t.userId.equals(userId))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);

    final results = await query.get();
    return results.map(_groupExpenseAssignmentDataToModel).toList();
  }

  @override
  Future<GroupExpenseAssignmentModel?> getLocalGroupExpenseAssignment(
      String id) async {
    final query = database.select(database.groupExpenseAssignments)
      ..where((t) => t.id.equals(id));

    final result = await query.getSingleOrNull();
    return result != null ? _groupExpenseAssignmentDataToModel(result) : null;
  }

  @override
  Future<void> upsertLocalGroupExpenseAssignment(
      GroupExpenseAssignmentModel assignment) async {
    await database
        .into(database.groupExpenseAssignments)
        .insertOnConflictUpdate(
          GroupExpenseAssignmentsCompanion(
            id: Value(assignment.id),
            groupId: Value(assignment.groupId),
            userId: Value(assignment.userId),
            spendingLimit: Value(assignment.spendingLimit),
            createdAt: Value(assignment.createdAt),
            updatedAt: Value(assignment.updatedAt),
          ),
        );
  }

  @override
  Future<void> upsertLocalGroupExpenseAssignments(
      List<GroupExpenseAssignmentModel> assignments) async {
    await database.batch((batch) {
      batch.insertAllOnConflictUpdate(
        database.groupExpenseAssignments,
        assignments.map((model) => GroupExpenseAssignmentsCompanion(
              id: Value(model.id),
              groupId: Value(model.groupId),
              userId: Value(model.userId),
              spendingLimit: Value(model.spendingLimit),
              createdAt: Value(model.createdAt),
              updatedAt: Value(model.updatedAt),
            )),
      );
    });
  }

  @override
  Future<void> deleteLocalGroupExpenseAssignment(String id) async {
    await (database.delete(database.groupExpenseAssignments)
          ..where((t) => t.id.equals(id)))
        .go();
  }

  @override
  Future<void> deleteAllLocalGroupExpenseAssignments(String userId) async {
    await (database.delete(database.groupExpenseAssignments)
          ..where((t) => t.userId.equals(userId)))
        .go();
  }

  @override
  Stream<List<GroupExpenseAssignmentModel>> watchLocalGroupExpenseAssignments(
      String userId) {
    final query = database.select(database.groupExpenseAssignments)
      ..where((t) => t.userId.equals(userId))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);

    return query.watch().map(
          (results) =>
              results.map(_groupExpenseAssignmentDataToModel).toList(),
        );
  }

  // ============================================================================
  // Batch Operations
  // ============================================================================

  @override
  Future<void> clearAllLocalBudgetData(String userId) async {
    await database.transaction(() async {
      await deleteAllLocalIncomeSources(userId);
      await deleteLocalSavingsGoal(userId);
      await deleteAllLocalGroupExpenseAssignments(userId);
    });
  }

  // ============================================================================
  // Helper Methods (Data Conversions)
  // ============================================================================

  IncomeSourceModel _incomeSourceDataToModel(IncomeSourceData data) {
    return IncomeSourceModel(
      id: data.id,
      userId: data.userId,
      type: data.type.toString().split('.').last, // Convert enum to string
      customTypeName: data.customTypeName,
      amount: data.amount,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  SavingsGoalModel _savingsGoalDataToModel(SavingsGoalData data) {
    return SavingsGoalModel(
      id: data.id,
      userId: data.userId,
      amount: data.amount,
      originalAmount: data.originalAmount,
      adjustedAt: data.adjustedAt,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  GroupExpenseAssignmentModel _groupExpenseAssignmentDataToModel(
      GroupExpenseAssignmentData data) {
    return GroupExpenseAssignmentModel(
      id: data.id,
      groupId: data.groupId,
      userId: data.userId,
      spendingLimit: data.spendingLimit,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }
}
