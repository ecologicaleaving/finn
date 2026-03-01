import 'package:dartz/dartz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/enums/recurrence_frequency.dart';
import '../../../../core/enums/reimbursement_status.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/expense_entity.dart';
import '../../domain/entities/recurring_expense.dart';
import '../../domain/repositories/recurring_expense_repository.dart';
import '../../domain/services/recurrence_calculator.dart';
import '../datasources/recurring_expense_local_datasource.dart';
import '../datasources/expense_remote_datasource.dart';

/// Implementation of [RecurringExpenseRepository] using local data source.
///
/// Follows offline-first architecture:
/// - All operations write to local Drift database immediately
/// - Sync queue handles upload to Supabase when online
/// - RecurrenceCalculator provides domain logic for date calculations
class RecurringExpenseRepositoryImpl implements RecurringExpenseRepository {
  RecurringExpenseRepositoryImpl({
    required this.localDataSource,
    required this.expenseRemoteDataSource,
    required this.supabaseClient,
  });

  final RecurringExpenseLocalDataSource localDataSource;
  final ExpenseRemoteDataSource expenseRemoteDataSource;
  final SupabaseClient supabaseClient;

  String get _currentUserId {
    final userId = supabaseClient.auth.currentUser?.id;
    if (userId == null) {
      throw const AppAuthException('User not authenticated', 'not_authenticated');
    }
    return userId;
  }

  String? get _currentGroupId {
    // TODO: Implement group ID retrieval from user profile
    // For now, return null
    return null;
  }

  @override
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
  }) async {
    try {
      // Validate amount
      if (amount <= 0) {
        return Left(ValidationFailure('Amount must be greater than 0'));
      }

      // Validate merchant length
      if (merchant != null && merchant.length > 100) {
        return Left(ValidationFailure('Merchant name too long (max 100 characters)'));
      }

      // Validate notes length
      if (notes != null && notes.length > 500) {
        return Left(ValidationFailure('Notes too long (max 500 characters)'));
      }

      final userId = _currentUserId;
      final groupId = _currentGroupId;

      final entity = await localDataSource.createRecurringExpense(
        userId: userId,
        groupId: groupId,
        templateExpenseId: templateExpenseId,
        amount: amount,
        categoryId: categoryId,
        categoryName: categoryName,
        frequency: frequency,
        anchorDate: anchorDate,
        merchant: merchant,
        notes: notes,
        isGroupExpense: isGroupExpense,
        budgetReservationEnabled: budgetReservationEnabled,
        defaultReimbursementStatus: defaultReimbursementStatus,
        paymentMethodId: paymentMethodId,
        paymentMethodName: paymentMethodName,
      );

      // T031: Queue sync operation to upload to Supabase when online
      await localDataSource.addToSyncQueue(
        userId: userId,
        operation: 'create',
        entityId: entity.id,
        payload: {
          'id': entity.id,
          'user_id': userId,
          'group_id': groupId,
          'amount': amount,
          'category_id': categoryId,
          'frequency': frequency.name,
          'anchor_date': anchorDate.toIso8601String(),
          'merchant': merchant,
          'notes': notes,
          'is_group_expense': isGroupExpense,
          'budget_reservation_enabled': budgetReservationEnabled,
          'default_reimbursement_status': defaultReimbursementStatus.name,
          'payment_method_id': paymentMethodId,
        },
      );

      return Right(entity);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on CacheException catch (e) {
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
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
  }) async {
    try {
      // Validate amount if provided
      if (amount != null && amount <= 0) {
        return Left(ValidationFailure('Amount must be greater than 0'));
      }

      // Validate merchant length if provided
      if (merchant != null && merchant.length > 100) {
        return Left(ValidationFailure('Merchant name too long (max 100 characters)'));
      }

      // Validate notes length if provided
      if (notes != null && notes.length > 500) {
        return Left(ValidationFailure('Notes too long (max 500 characters)'));
      }

      final entity = await localDataSource.updateRecurringExpense(
        id: id,
        amount: amount,
        categoryId: categoryId,
        categoryName: categoryName,
        frequency: frequency,
        merchant: merchant,
        notes: notes,
        budgetReservationEnabled: budgetReservationEnabled,
        defaultReimbursementStatus: defaultReimbursementStatus,
        paymentMethodId: paymentMethodId,
        paymentMethodName: paymentMethodName,
      );

      // Recalculate nextDueDate if frequency changed
      if (frequency != null) {
        final newNextDueDate = RecurrenceCalculator.calculateNextDueDate(
          anchorDate: entity.anchorDate,
          frequency: entity.frequency,
          lastCreated: entity.lastInstanceCreatedAt,
        );

        if (newNextDueDate != null) {
          await localDataSource.updateAfterInstanceCreation(
            id: id,
            lastInstanceCreatedAt: entity.lastInstanceCreatedAt ?? entity.createdAt,
            nextDueDate: newNextDueDate,
          );
        }
      }

      // T031: Queue sync operation
      final updatePayload = <String, dynamic>{};
      if (amount != null) updatePayload['amount'] = amount;
      if (categoryId != null) updatePayload['category_id'] = categoryId;
      if (frequency != null) updatePayload['frequency'] = frequency.name;
      if (merchant != null) updatePayload['merchant'] = merchant;
      if (notes != null) updatePayload['notes'] = notes;
      if (budgetReservationEnabled != null) {
        updatePayload['budget_reservation_enabled'] = budgetReservationEnabled;
      }
      if (defaultReimbursementStatus != null) {
        updatePayload['default_reimbursement_status'] = defaultReimbursementStatus.name;
      }
      if (paymentMethodId != null) {
        updatePayload['payment_method_id'] = paymentMethodId;
      }

      await localDataSource.addToSyncQueue(
        userId: _currentUserId,
        operation: 'update',
        entityId: id,
        payload: updatePayload,
      );

      return Right(entity);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on CacheException catch (e) {
      if (e.code == 'not_found') {
        return Left(CacheFailure('Recurring expense not found'));
      }
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, RecurringExpense>> pauseRecurringExpense({
    required String id,
  }) async {
    try {
      final entity = await localDataSource.pauseRecurringExpense(id: id);

      // T031: Queue sync operation
      await localDataSource.addToSyncQueue(
        userId: _currentUserId,
        operation: 'update',
        entityId: id,
        payload: {'is_paused': true},
      );

      return Right(entity);
    } on CacheException catch (e) {
      if (e.code == 'not_found') {
        return Left(CacheFailure('Recurring expense not found'));
      }
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, RecurringExpense>> resumeRecurringExpense({
    required String id,
  }) async {
    try {
      // Get the template to calculate next due date
      final template = await localDataSource.getRecurringExpense(id: id);

      // Calculate next due date from now
      final nextDueDate = RecurrenceCalculator.calculateNextDueDate(
        anchorDate: template.anchorDate,
        frequency: template.frequency,
        lastCreated: template.lastInstanceCreatedAt,
      );

      if (nextDueDate == null) {
        return Left(ValidationFailure(
          'Failed to calculate next due date',
        ));
      }

      final entity = await localDataSource.resumeRecurringExpense(
        id: id,
        nextDueDate: nextDueDate,
      );

      // T031: Queue sync operation
      await localDataSource.addToSyncQueue(
        userId: _currentUserId,
        operation: 'update',
        entityId: id,
        payload: {
          'is_paused': false,
          'next_due_date': nextDueDate.toIso8601String(),
        },
      );

      return Right(entity);
    } on CacheException catch (e) {
      if (e.code == 'not_found') {
        return Left(CacheFailure('Recurring expense not found'));
      }
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteRecurringExpense({
    required String id,
    bool deleteInstances = false,
  }) async {
    try {
      if (deleteInstances) {
        // Get all instance IDs
        final instanceIds = await localDataSource.getInstanceIdsForTemplate(
          recurringExpenseId: id,
        );

        // Delete all expense instances
        // TODO: Implement expense deletion through expense repository
        // for (final expenseId in instanceIds) {
        //   await expenseRepository.deleteExpense(expenseId: expenseId);
        // }

        // Delete instance mappings
        await localDataSource.deleteInstanceMappingsForTemplate(
          recurringExpenseId: id,
        );
      }

      // Delete template (cascade deletes mappings automatically)
      await localDataSource.deleteRecurringExpense(id: id);

      // T031: Queue sync operation
      await localDataSource.addToSyncQueue(
        userId: _currentUserId,
        operation: 'delete',
        entityId: id,
        payload: {'id': id},
      );

      return const Right(unit);
    } on CacheException catch (e) {
      if (e.code == 'not_found') {
        return Left(CacheFailure('Recurring expense not found'));
      }
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<RecurringExpense>>> getRecurringExpenses({
    bool? isPaused,
    bool? budgetReservationEnabled,
  }) async {
    try {
      final userId = _currentUserId;

      final entities = await localDataSource.getRecurringExpenses(
        userId: userId,
        isPaused: isPaused,
        budgetReservationEnabled: budgetReservationEnabled,
      );

      return Right(entities);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on CacheException catch (e) {
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, RecurringExpense>> getRecurringExpense({
    required String id,
  }) async {
    try {
      final entity = await localDataSource.getRecurringExpense(id: id);
      return Right(entity);
    } on CacheException catch (e) {
      if (e.code == 'not_found') {
        return Left(CacheFailure('Recurring expense not found'));
      }
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ExpenseEntity>> generateExpenseInstance({
    required String recurringExpenseId,
    required DateTime scheduledDate,
  }) async {
    try {
      // Get the template
      final template = await localDataSource.getRecurringExpense(
        id: recurringExpenseId,
      );

      // Validate template is not paused
      if (template.isPaused) {
        return Left(ValidationFailure(
          'Cannot generate instance from paused template',
        ));
      }

      // Create expense using expense repository
      // TODO: Implement using ExpenseRepository
      // For now, this is a placeholder that would be implemented
      // when wiring up the repositories

      throw UnimplementedError(
        'generateExpenseInstance will be implemented when expense repository is wired up',
      );
    } on CacheException catch (e) {
      if (e.code == 'not_found') {
        return Left(CacheFailure(
          'Recurring expense template not found',
        ));
      }
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<ExpenseEntity>>> getRecurringExpenseInstances({
    required String recurringExpenseId,
  }) async {
    try {
      // Get all instance IDs
      final instanceIds = await localDataSource.getInstanceIdsForTemplate(
        recurringExpenseId: recurringExpenseId,
      );

      // Get all expenses for these IDs
      // TODO: Implement batch expense retrieval through expense repository
      // For now, return empty list as placeholder

      return const Right([]);
    } on CacheException catch (e) {
      if (e.code == 'not_found') {
        return Left(CacheFailure(
          'Recurring expense template not found',
        ));
      }
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
