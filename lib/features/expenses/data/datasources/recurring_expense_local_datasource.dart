import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/daos/recurring_expenses_dao.dart';
import '../../../../core/enums/recurrence_frequency.dart';
import '../../../../core/enums/reimbursement_status.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../offline/data/local/offline_database.dart';
import '../models/recurring_expense_entity.dart';

/// Local data source for recurring expense operations using Drift.
///
/// Handles all offline storage operations for recurring expenses.
abstract class RecurringExpenseLocalDataSource {
  /// Create a new recurring expense template
  Future<RecurringExpenseEntity> createRecurringExpense({
    required String userId,
    String? groupId,
    String? templateExpenseId,
    required double amount,
    required String categoryId,
    required String categoryName,
    required RecurrenceFrequency frequency,
    required DateTime anchorDate,
    String? merchant,
    String? notes,
    bool isGroupExpense = true,
    bool budgetReservationEnabled = false,
    ReimbursementStatus defaultReimbursementStatus = ReimbursementStatus.none,
    String? paymentMethodId,
    String? paymentMethodName,
  });

  /// Update a recurring expense template
  Future<RecurringExpenseEntity> updateRecurringExpense({
    required String id,
    double? amount,
    String? categoryId,
    String? categoryName,
    RecurrenceFrequency? frequency,
    String? merchant,
    String? notes,
    bool? budgetReservationEnabled,
    ReimbursementStatus? defaultReimbursementStatus,
    String? paymentMethodId,
    String? paymentMethodName,
  });

  /// Pause a recurring expense
  Future<RecurringExpenseEntity> pauseRecurringExpense({required String id});

  /// Resume a recurring expense
  Future<RecurringExpenseEntity> resumeRecurringExpense({
    required String id,
    required DateTime nextDueDate,
  });

  /// Delete a recurring expense template
  Future<void> deleteRecurringExpense({required String id});

  /// Get all recurring expenses for a user
  Future<List<RecurringExpenseEntity>> getRecurringExpenses({
    required String userId,
    bool? isPaused,
    bool? budgetReservationEnabled,
  });

  /// Get a single recurring expense by ID
  Future<RecurringExpenseEntity> getRecurringExpense({required String id});

  /// Update template after creating an instance
  Future<void> updateAfterInstanceCreation({
    required String id,
    required DateTime lastInstanceCreatedAt,
    DateTime? nextDueDate,
  });

  /// Create a recurring expense instance mapping
  Future<void> createInstanceMapping({
    required String recurringExpenseId,
    required String expenseId,
    required DateTime scheduledDate,
  });

  /// Get all instance mappings for a template
  Future<List<String>> getInstanceIdsForTemplate({
    required String recurringExpenseId,
  });

  /// Delete all instance mappings for a template
  Future<void> deleteInstanceMappingsForTemplate({
    required String recurringExpenseId,
  });

  /// Add operation to sync queue (T031)
  ///
  /// Queues recurring expense operations for upload to Supabase when online.
  /// Operations: 'create', 'update', 'delete'
  Future<void> addToSyncQueue({
    required String userId,
    required String operation,
    required String entityId,
    required Map<String, dynamic> payload,
    int priority = 0,
  });
}

/// Implementation of [RecurringExpenseLocalDataSource] using Drift DAO.
class RecurringExpenseLocalDataSourceImpl
    implements RecurringExpenseLocalDataSource {
  RecurringExpenseLocalDataSourceImpl({
    required this.dao,
    required this.database,
  });

  final RecurringExpensesDao dao;
  final OfflineDatabase database;

  @override
  Future<RecurringExpenseEntity> createRecurringExpense({
    required String userId,
    String? groupId,
    String? templateExpenseId,
    required double amount,
    required String categoryId,
    required String categoryName,
    required RecurrenceFrequency frequency,
    required DateTime anchorDate,
    String? merchant,
    String? notes,
    bool isGroupExpense = true,
    bool budgetReservationEnabled = false,
    ReimbursementStatus defaultReimbursementStatus = ReimbursementStatus.none,
    String? paymentMethodId,
    String? paymentMethodName,
  }) async {
    try {
      final id = const Uuid().v4();
      final now = DateTime.now();

      // Calculate initial nextDueDate (will be anchorDate for first occurrence)
      final nextDueDate = anchorDate;

      final companion = RecurringExpensesCompanion.insert(
        id: id,
        userId: userId,
        groupId: Value(groupId),
        templateExpenseId: Value(templateExpenseId),
        amount: amount,
        categoryId: categoryId,
        categoryName: categoryName,
        merchant: Value(merchant),
        notes: Value(notes),
        isGroupExpense: Value(isGroupExpense),
        frequency: frequency,
        anchorDate: anchorDate,
        isPaused: const Value(false),
        lastInstanceCreatedAt: const Value(null),
        nextDueDate: Value(nextDueDate),
        budgetReservationEnabled: Value(budgetReservationEnabled),
        defaultReimbursementStatus: Value(defaultReimbursementStatus),
        paymentMethodId: Value(paymentMethodId),
        paymentMethodName: Value(paymentMethodName),
        createdAt: now,
        updatedAt: now,
      );

      await dao.insertRecurringExpense(companion);

      // Retrieve the created entity
      final created = await dao.getRecurringExpenseById(id);
      if (created == null) {
        throw const CacheException(
          'Failed to retrieve created recurring expense',
          'creation_failed',
        );
      }

      return RecurringExpenseEntity.fromDrift(created);
    } catch (e) {
      throw CacheException(
        'Failed to create recurring expense: $e',
        'creation_error',
      );
    }
  }

  @override
  Future<RecurringExpenseEntity> updateRecurringExpense({
    required String id,
    double? amount,
    String? categoryId,
    String? categoryName,
    RecurrenceFrequency? frequency,
    String? merchant,
    String? notes,
    bool? budgetReservationEnabled,
    ReimbursementStatus? defaultReimbursementStatus,
    String? paymentMethodId,
    String? paymentMethodName,
  }) async {
    try {
      final companion = RecurringExpensesCompanion(
        amount: amount != null ? Value(amount) : const Value.absent(),
        categoryId: categoryId != null ? Value(categoryId) : const Value.absent(),
        categoryName:
            categoryName != null ? Value(categoryName) : const Value.absent(),
        frequency: frequency != null ? Value(frequency) : const Value.absent(),
        merchant: merchant != null ? Value(merchant) : const Value.absent(),
        notes: notes != null ? Value(notes) : const Value.absent(),
        budgetReservationEnabled: budgetReservationEnabled != null
            ? Value(budgetReservationEnabled)
            : const Value.absent(),
        defaultReimbursementStatus: defaultReimbursementStatus != null
            ? Value(defaultReimbursementStatus)
            : const Value.absent(),
        paymentMethodId: paymentMethodId != null
            ? Value(paymentMethodId)
            : const Value.absent(),
        paymentMethodName: paymentMethodName != null
            ? Value(paymentMethodName)
            : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      );

      final success = await dao.updateRecurringExpense(id, companion);
      if (!success) {
        throw const CacheException(
          'Recurring expense not found',
          'not_found',
        );
      }

      // Retrieve updated entity
      final updated = await dao.getRecurringExpenseById(id);
      if (updated == null) {
        throw const CacheException(
          'Failed to retrieve updated recurring expense',
          'update_failed',
        );
      }

      return RecurringExpenseEntity.fromDrift(updated);
    } catch (e) {
      if (e is CacheException) rethrow;
      throw CacheException(
        'Failed to update recurring expense: $e',
        'update_error',
      );
    }
  }

  @override
  Future<RecurringExpenseEntity> pauseRecurringExpense({
    required String id,
  }) async {
    try {
      final success = await dao.pauseRecurringExpense(id);
      if (!success) {
        throw const CacheException(
          'Recurring expense not found',
          'not_found',
        );
      }

      final paused = await dao.getRecurringExpenseById(id);
      if (paused == null) {
        throw const CacheException(
          'Failed to retrieve paused recurring expense',
          'pause_failed',
        );
      }

      return RecurringExpenseEntity.fromDrift(paused);
    } catch (e) {
      if (e is CacheException) rethrow;
      throw CacheException(
        'Failed to pause recurring expense: $e',
        'pause_error',
      );
    }
  }

  @override
  Future<RecurringExpenseEntity> resumeRecurringExpense({
    required String id,
    required DateTime nextDueDate,
  }) async {
    try {
      final success = await dao.resumeRecurringExpense(id, nextDueDate);
      if (!success) {
        throw const CacheException(
          'Recurring expense not found',
          'not_found',
        );
      }

      final resumed = await dao.getRecurringExpenseById(id);
      if (resumed == null) {
        throw const CacheException(
          'Failed to retrieve resumed recurring expense',
          'resume_failed',
        );
      }

      return RecurringExpenseEntity.fromDrift(resumed);
    } catch (e) {
      if (e is CacheException) rethrow;
      throw CacheException(
        'Failed to resume recurring expense: $e',
        'resume_error',
      );
    }
  }

  @override
  Future<void> deleteRecurringExpense({required String id}) async {
    try {
      final deleted = await dao.deleteRecurringExpense(id);
      if (deleted == 0) {
        throw const CacheException(
          'Recurring expense not found',
          'not_found',
        );
      }
    } catch (e) {
      if (e is CacheException) rethrow;
      throw CacheException(
        'Failed to delete recurring expense: $e',
        'delete_error',
      );
    }
  }

  @override
  Future<List<RecurringExpenseEntity>> getRecurringExpenses({
    required String userId,
    bool? isPaused,
    bool? budgetReservationEnabled,
  }) async {
    try {
      List<RecurringExpenseData> results;

      if (isPaused == true) {
        results = await dao.getPausedRecurringExpenses(userId);
      } else if (isPaused == false) {
        results = await dao.getActiveRecurringExpenses(userId);
      } else if (budgetReservationEnabled == true) {
        results = await dao.getRecurringExpensesWithBudgetReservation(userId);
      } else {
        results = await dao.getAllRecurringExpenses(userId);
      }

      return results.map((data) => RecurringExpenseEntity.fromDrift(data)).toList();
    } catch (e) {
      throw CacheException(
        'Failed to get recurring expenses: $e',
        'query_error',
      );
    }
  }

  @override
  Future<RecurringExpenseEntity> getRecurringExpense({
    required String id,
  }) async {
    try {
      final result = await dao.getRecurringExpenseById(id);
      if (result == null) {
        throw const CacheException(
          'Recurring expense not found',
          'not_found',
        );
      }

      return RecurringExpenseEntity.fromDrift(result);
    } catch (e) {
      if (e is CacheException) rethrow;
      throw CacheException(
        'Failed to get recurring expense: $e',
        'query_error',
      );
    }
  }

  @override
  Future<void> updateAfterInstanceCreation({
    required String id,
    required DateTime lastInstanceCreatedAt,
    DateTime? nextDueDate,
  }) async {
    try {
      final success = await dao.updateAfterInstanceCreation(
        id,
        lastInstanceCreatedAt,
        nextDueDate,
      );
      if (!success) {
        throw const CacheException(
          'Recurring expense not found',
          'not_found',
        );
      }
    } catch (e) {
      if (e is CacheException) rethrow;
      throw CacheException(
        'Failed to update after instance creation: $e',
        'update_error',
      );
    }
  }

  @override
  Future<void> createInstanceMapping({
    required String recurringExpenseId,
    required String expenseId,
    required DateTime scheduledDate,
  }) async {
    try {
      final companion = RecurringExpenseInstancesCompanion.insert(
        recurringExpenseId: recurringExpenseId,
        expenseId: expenseId,
        scheduledDate: scheduledDate,
        createdAt: DateTime.now(),
      );

      await dao.insertRecurringExpenseInstance(companion);
    } catch (e) {
      throw CacheException(
        'Failed to create instance mapping: $e',
        'mapping_error',
      );
    }
  }

  @override
  Future<List<String>> getInstanceIdsForTemplate({
    required String recurringExpenseId,
  }) async {
    try {
      final instances = await dao.getInstancesForTemplate(recurringExpenseId);
      return instances.map((instance) => instance.expenseId).toList();
    } catch (e) {
      throw CacheException(
        'Failed to get instance IDs: $e',
        'query_error',
      );
    }
  }

  @override
  Future<void> deleteInstanceMappingsForTemplate({
    required String recurringExpenseId,
  }) async {
    try {
      await dao.deleteInstanceMappingsForTemplate(recurringExpenseId);
    } catch (e) {
      throw CacheException(
        'Failed to delete instance mappings: $e',
        'delete_error',
      );
    }
  }

  @override
  Future<void> addToSyncQueue({
    required String userId,
    required String operation,
    required String entityId,
    required Map<String, dynamic> payload,
    int priority = 0,
  }) async {
    try {
      // T031: Queue sync operation for upload to Supabase
      final companion = SyncQueueItemsCompanion.insert(
        userId: userId,
        operation: operation,
        entityType: 'recurring_expense',
        entityId: entityId,
        payload: jsonEncode(payload),
        syncStatus: 'pending',
        priority: Value(priority),
        createdAt: DateTime.now(),
      );

      await database.into(database.syncQueueItems).insert(companion);
    } catch (e) {
      throw CacheException(
        'Failed to add to sync queue: $e',
        'sync_queue_error',
      );
    }
  }
}
