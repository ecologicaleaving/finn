import 'package:dartz/dartz.dart';

import '../../../../core/enums/recurrence_frequency.dart';
import '../../../../core/enums/reimbursement_status.dart';
import '../../../../core/errors/failures.dart';
import '../entities/recurring_expense.dart';
import '../entities/expense_entity.dart';

/// Abstract repository interface for recurring expense operations.
///
/// Defines the contract for creating, managing, and generating instances
/// from recurring expense templates.
abstract class RecurringExpenseRepository {
  /// Create a new recurring expense template.
  ///
  /// Returns the created recurring expense with generated ID and calculated nextDueDate.
  ///
  /// Errors:
  /// - [ValidationFailure] if amount <= 0 or invalid parameters
  /// - [NetworkFailure] if offline and unable to queue
  /// - [ServerFailure] for database errors
  Future<Either<Failure, RecurringExpense>> createRecurringExpense({
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
    String? templateExpenseId,
  });

  /// Update an existing recurring expense template.
  ///
  /// Only updates provided fields. Recalculates nextDueDate if frequency changed.
  ///
  /// Note: Updating a template does NOT affect already-generated instances.
  ///
  /// Errors:
  /// - [NotFoundFailure] if template doesn't exist
  /// - [UnauthorizedFailure] if user doesn't own the template
  /// - [ValidationFailure] for invalid updates
  Future<Either<Failure, RecurringExpense>> updateRecurringExpense({
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

  /// Pause a recurring expense template (stops generating instances).
  ///
  /// Paused templates:
  /// - Do not generate new expense instances
  /// - Do not reserve budget (if budget reservation enabled)
  /// - Can be resumed later
  ///
  /// Errors:
  /// - [NotFoundFailure] if template doesn't exist
  /// - [UnauthorizedFailure] if user doesn't own the template
  /// - [ValidationFailure] if already paused
  Future<Either<Failure, RecurringExpense>> pauseRecurringExpense({
    required String id,
  });

  /// Resume a paused recurring expense template.
  ///
  /// Recalculates nextDueDate from current date forward.
  /// Does NOT retroactively create missed instances.
  ///
  /// Errors:
  /// - [NotFoundFailure] if template doesn't exist
  /// - [UnauthorizedFailure] if user doesn't own the template
  /// - [ValidationFailure] if not paused
  Future<Either<Failure, RecurringExpense>> resumeRecurringExpense({
    required String id,
  });

  /// Delete a recurring expense template.
  ///
  /// [deleteInstances] controls whether to delete generated expense instances:
  /// - false (default): Only delete template, keep existing instances
  /// - true: Delete template AND all generated instances (cascade)
  ///
  /// Errors:
  /// - [NotFoundFailure] if template doesn't exist
  /// - [UnauthorizedFailure] if user doesn't own the template
  Future<Either<Failure, Unit>> deleteRecurringExpense({
    required String id,
    bool deleteInstances = false,
  });

  /// Get all recurring expenses for the current user's group.
  ///
  /// Optional filters:
  /// - [isPaused]: Filter by paused status (null = all)
  /// - [budgetReservationEnabled]: Filter by budget reservation (null = all)
  ///
  /// Returns empty list if no recurring expenses found.
  Future<Either<Failure, List<RecurringExpense>>> getRecurringExpenses({
    bool? isPaused,
    bool? budgetReservationEnabled,
  });

  /// Get a single recurring expense by ID.
  ///
  /// Errors:
  /// - [NotFoundFailure] if template doesn't exist
  Future<Either<Failure, RecurringExpense>> getRecurringExpense({
    required String id,
  });

  /// Manually generate an expense instance from a recurring template.
  ///
  /// This is primarily used by the background task scheduler.
  /// Developers should rarely need to call this directly.
  ///
  /// Creates:
  /// 1. New expense in expenses table
  /// 2. Mapping record in recurring_expense_instances table
  /// 3. Updates template's lastInstanceCreatedAt and nextDueDate
  ///
  /// Errors:
  /// - [NotFoundFailure] if template doesn't exist
  /// - [ValidationFailure] if template is paused
  Future<Either<Failure, ExpenseEntity>> generateExpenseInstance({
    required String recurringExpenseId,
    required DateTime scheduledDate,
  });

  /// Get all expense instances generated from a recurring template.
  ///
  /// Returns complete expense entities, not just IDs.
  /// Useful for displaying history or deletion preview.
  ///
  /// Errors:
  /// - [NotFoundFailure] if template doesn't exist
  Future<Either<Failure, List<ExpenseEntity>>> getRecurringExpenseInstances({
    required String recurringExpenseId,
  });
}
