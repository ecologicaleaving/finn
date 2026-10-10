import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/budget_composition_entity.dart';
import '../../domain/entities/budget_stats_entity.dart';
import '../../domain/entities/category_budget_entity.dart';
import '../../domain/entities/computed_budget_totals_entity.dart';
import '../../domain/entities/group_budget_entity.dart';
import '../../domain/entities/personal_budget_entity.dart';
import '../../domain/entities/virtual_group_expenses_category_entity.dart';
import '../../domain/entities/income_source_entity.dart';
import '../../domain/entities/savings_goal_entity.dart';
import '../../domain/entities/group_expense_assignment_entity.dart';
import '../../domain/entities/budget_summary_entity.dart';
import '../../domain/repositories/budget_repository.dart';
import '../datasources/budget_remote_datasource.dart';
import '../datasources/budget_local_datasource.dart';
import '../models/income_source_model.dart';
import '../models/savings_goal_model.dart';
import '../models/group_expense_assignment_model.dart';
import 'package:rxdart/rxdart.dart';

/// Implementation of [BudgetRepository] using remote and local data sources.
class BudgetRepositoryImpl implements BudgetRepository {
  BudgetRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  final BudgetRemoteDataSource remoteDataSource;
  final BudgetLocalDataSource localDataSource;

  /// Last background income-sources sync (lets tests await it).
  @visibleForTesting
  Future<void>? lastIncomeSourcesSync;

  // ========== Group Budget Operations ==========

  @override
  Future<Either<Failure, GroupBudgetEntity>> setGroupBudget({
    required String groupId,
    required int amount,
    required int month,
    required int year,
  }) async {
    try {
      final budget = await remoteDataSource.setGroupBudget(
        groupId: groupId,
        amount: amount,
        month: month,
        year: year,
      );
      return Right(budget.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on PermissionException catch (e) {
      return Left(PermissionFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, GroupBudgetEntity?>> getGroupBudget({
    required String groupId,
    required int month,
    required int year,
  }) async {
    try {
      final budget = await remoteDataSource.getGroupBudget(
        groupId: groupId,
        month: month,
        year: year,
      );
      return Right(budget?.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, BudgetStatsEntity>> getGroupBudgetStats({
    required String groupId,
    required int month,
    required int year,
  }) async {
    try {
      final stats = await remoteDataSource.getGroupBudgetStats(
        groupId: groupId,
        month: month,
        year: year,
      );
      return Right(stats.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<GroupBudgetEntity>>> getGroupBudgetHistory({
    required String groupId,
    int? limit,
  }) async {
    try {
      final budgets = await remoteDataSource.getGroupBudgetHistory(
        groupId: groupId,
        limit: limit,
      );
      return Right(budgets.map((b) => b.toEntity()).toList());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  // ========== Personal Budget Operations ==========

  @override
  Future<Either<Failure, PersonalBudgetEntity>> setPersonalBudget({
    required String userId,
    required int amount,
    required int month,
    required int year,
  }) async {
    try {
      final budget = await remoteDataSource.setPersonalBudget(
        userId: userId,
        amount: amount,
        month: month,
        year: year,
      );
      return Right(budget.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, PersonalBudgetEntity?>> getPersonalBudget({
    required String userId,
    required int month,
    required int year,
  }) async {
    try {
      final budget = await remoteDataSource.getPersonalBudget(
        userId: userId,
        month: month,
        year: year,
      );
      return Right(budget?.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, BudgetStatsEntity>> getPersonalBudgetStats({
    required String userId,
    required int month,
    required int year,
  }) async {
    try {
      final stats = await remoteDataSource.getPersonalBudgetStats(
        userId: userId,
        month: month,
        year: year,
      );
      return Right(stats.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<PersonalBudgetEntity>>> getPersonalBudgetHistory({
    required String userId,
    int? limit,
  }) async {
    try {
      final budgets = await remoteDataSource.getPersonalBudgetHistory(
        userId: userId,
        limit: limit,
      );
      return Right(budgets.map((b) => b.toEntity()).toList());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  // ========== Category Budget Operations (Feature 004 - T030) ==========

  @override
  Future<Either<Failure, List>> getCategoryBudgets({
    required String groupId,
    required int year,
    required int month,
  }) async {
    try {
      final budgets = await remoteDataSource.getCategoryBudgets(
        groupId: groupId,
        year: year,
        month: month,
      );
      return Right(budgets);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, dynamic>> getCategoryBudget({
    required String categoryId,
    required String groupId,
    required int year,
    required int month,
  }) async {
    try {
      final budget = await remoteDataSource.getCategoryBudget(
        categoryId: categoryId,
        groupId: groupId,
        year: year,
        month: month,
      );
      return Right(budget);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, dynamic>> createCategoryBudget({
    required String categoryId,
    required String groupId,
    required int amount,
    required int month,
    required int year,
    bool isGroupBudget = true,
  }) async {
    try {
      final budget = await remoteDataSource.createCategoryBudget(
        categoryId: categoryId,
        groupId: groupId,
        amount: amount,
        month: month,
        year: year,
        isGroupBudget: isGroupBudget,
      );
      return Right(budget);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on PermissionException catch (e) {
      return Left(PermissionFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, dynamic>> updateCategoryBudget({
    required String budgetId,
    required int amount,
  }) async {
    try {
      final budget = await remoteDataSource.updateCategoryBudget(
        budgetId: budgetId,
        amount: amount,
      );
      return Right(budget);
    } on PermissionException catch (e) {
      return Left(PermissionFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteCategoryBudget(String budgetId) async {
    try {
      await remoteDataSource.deleteCategoryBudget(budgetId);
      return const Right(unit);
    } on PermissionException catch (e) {
      return Left(PermissionFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, dynamic>> getCategoryBudgetStats({
    required String groupId,
    required String categoryId,
    required int year,
    required int month,
  }) async {
    try {
      final stats = await remoteDataSource.getCategoryBudgetStats(
        groupId: groupId,
        categoryId: categoryId,
        year: year,
        month: month,
      );
      return Right(stats);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, dynamic>> getOverallGroupBudgetStats({
    required String groupId,
    required int year,
    required int month,
  }) async {
    try {
      final stats = await remoteDataSource.getOverallGroupBudgetStats(
        groupId: groupId,
        year: year,
        month: month,
      );
      return Right(stats);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  // ========== Percentage Budget Operations (Feature 004 Extension) ==========

  @override
  Future<Either<Failure, List>> getGroupMembersWithPercentages({
    required String groupId,
    required String categoryId,
    required int year,
    required int month,
  }) async {
    try {
      final members = await remoteDataSource.getGroupMembersWithPercentages(
        groupId: groupId,
        categoryId: categoryId,
        year: year,
        month: month,
      );
      return Right(members);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, int>> calculatePercentageBudget({
    required int groupBudgetAmount,
    required double percentage,
  }) async {
    try {
      final amount = await remoteDataSource.calculatePercentageBudget(
        groupBudgetAmount: groupBudgetAmount,
        percentage: percentage,
      );
      return Right(amount);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List>> getBudgetChangeNotifications({
    required String groupId,
    required int year,
    required int month,
    String? userId,
  }) async {
    try {
      final notifications = await remoteDataSource.getBudgetChangeNotifications(
        groupId: groupId,
        year: year,
        month: month,
        userId: userId,
      );
      return Right(notifications);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, dynamic>> setPersonalPercentageBudget({
    required String categoryId,
    required String groupId,
    required String userId,
    required double percentage,
    required int month,
    required int year,
  }) async {
    try {
      final budget = await remoteDataSource.setPersonalPercentageBudget(
        categoryId: categoryId,
        groupId: groupId,
        userId: userId,
        percentage: percentage,
        month: month,
        year: year,
      );
      return Right(budget);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on PermissionException catch (e) {
      return Left(PermissionFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, double?>> getPreviousMonthPercentage({
    required String categoryId,
    required String groupId,
    required String userId,
    required int year,
    required int month,
  }) async {
    try {
      final percentage = await remoteDataSource.getPreviousMonthPercentage(
        categoryId: categoryId,
        groupId: groupId,
        userId: userId,
        year: year,
        month: month,
      );
      return Right(percentage);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List>> getPercentageHistory({
    required String categoryId,
    required String groupId,
    required String userId,
    int? limit,
  }) async {
    try {
      final history = await remoteDataSource.getPercentageHistory(
        categoryId: categoryId,
        groupId: groupId,
        userId: userId,
        limit: limit,
      );
      return Right(history);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  // ========== Unified Budget Composition (New System) ==========

  @override
  Future<Either<Failure, BudgetComposition>> getBudgetComposition({
    required String groupId,
    required int year,
    required int month,
  }) async {
    try {
      final composition = await remoteDataSource.getBudgetComposition(
        groupId: groupId,
        year: year,
        month: month,
      );
      return Right(composition);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Errore nel caricamento budget: ${e.toString()}'));
    }
  }

  // ========== Computed Budget Totals (Category-Only System) ==========

  @override
  Future<Either<Failure, ComputedBudgetTotals>> getComputedBudgetTotals({
    required String groupId,
    required String userId,
    required int year,
    required int month,
  }) async {
    try {
      final totals = await remoteDataSource.getComputedBudgetTotals(
        groupId: groupId,
        userId: userId,
        year: year,
        month: month,
      );
      return Right(totals);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Errore nel calcolo totali budget: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, CategoryBudgetEntity>> ensureAltroCategory({
    required String groupId,
    required int year,
    required int month,
  }) async {
    try {
      final altroCategory = await remoteDataSource.ensureAltroCategory(
        groupId: groupId,
        year: year,
        month: month,
      );
      return Right(altroCategory);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Errore nella creazione categoria Altro: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, CategoryBudgetEntity>> distributeToAltroCategory({
    required String groupId,
    required int amount,
    required int year,
    required int month,
  }) async {
    try {
      final altroCategory = await remoteDataSource.distributeToAltroCategory(
        groupId: groupId,
        amount: amount,
        year: year,
        month: month,
      );
      return Right(altroCategory);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on PermissionException catch (e) {
      return Left(PermissionFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Errore nell\'assegnazione budget ad Altro: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, VirtualGroupExpensesCategory>> calculateVirtualGroupCategory({
    required String groupId,
    required String userId,
    required int year,
    required int month,
  }) async {
    try {
      final virtualCategory = await remoteDataSource.calculateVirtualGroupCategory(
        groupId: groupId,
        userId: userId,
        year: year,
        month: month,
      );
      return Right(virtualCategory);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Errore nel calcolo categoria virtuale: ${e.toString()}'));
    }
  }

  // ========== Personal Income & Savings Operations (Feature 001) ==========

  @override
  Future<Either<Failure, List<IncomeSourceEntity>>> getIncomeSources(
      String userId) async {
    try {
      // Try to get from local cache first
      final localIncomeSources = await localDataSource.getLocalIncomeSources(userId);

      if (localIncomeSources.isNotEmpty) {
        // Return local data immediately (optimistic UI)
        final entities = localIncomeSources.map((model) => model.toEntity()).toList();

        // Sync with remote in background: a source deleted on another device
        // disappears from the next call (the cache is aligned to the server).
        lastIncomeSourcesSync = _syncIncomeSourcesInBackground(userId);

        return Right(entities);
      }

      // If no local data, fetch from remote
      final remoteModels = await remoteDataSource.fetchIncomeSources(userId);

      // Align the local cache to the server (also drops rows deleted elsewhere)
      await localDataSource.replaceLocalIncomeSources(userId, remoteModels);

      return Right(remoteModels.map((model) => model.toEntity()).toList());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to get income sources: ${e.toString()}'));
    }
  }

  Future<void> _syncIncomeSourcesInBackground(String userId) async {
    try {
      final remoteModels = await remoteDataSource.fetchIncomeSources(userId);
      await localDataSource.replaceLocalIncomeSources(userId, remoteModels);
    } catch (e) {
      // Silent fail for background sync: the cache stays as it is
    }
  }

  @override
  Future<Either<Failure, IncomeSourceEntity>> getIncomeSource(String id) async {
    try {
      // Try local first
      final localModel = await localDataSource.getLocalIncomeSource(id);
      if (localModel != null) {
        return Right(localModel.toEntity());
      }

      // Fetch from remote
      final remoteModel = await remoteDataSource.fetchIncomeSource(id);

      // Cache locally
      await localDataSource.upsertLocalIncomeSource(remoteModel);

      return Right(remoteModel.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to get income source: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, IncomeSourceEntity>> addIncomeSource(
      IncomeSourceEntity incomeSource) async {
    try {
      // Create in remote first
      final model = await remoteDataSource.createIncomeSource(
        IncomeSourceModel.fromEntity(incomeSource),
      );

      // Cache locally
      await localDataSource.upsertLocalIncomeSource(model);

      return Right(model.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to add income source: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, IncomeSourceEntity>> updateIncomeSource(
      IncomeSourceEntity incomeSource) async {
    try {
      // Update in remote first
      final model = await remoteDataSource.updateIncomeSource(
        IncomeSourceModel.fromEntity(incomeSource),
      );

      // Update local cache
      await localDataSource.upsertLocalIncomeSource(model);

      return Right(model.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to update income source: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteIncomeSource(String id) async {
    try {
      // Delete from remote first
      await remoteDataSource.deleteIncomeSource(id);

      // Delete from local cache
      await localDataSource.deleteLocalIncomeSource(id);

      return const Right(null);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to delete income source: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, int>> getTotalIncome(String userId) async {
    try {
      final result = await getIncomeSources(userId);

      return result.fold(
        (failure) => Left(failure),
        (sources) {
          final total = sources.fold<int>(0, (sum, source) => sum + source.amount);
          return Right(total);
        },
      );
    } catch (e) {
      return Left(ServerFailure('Failed to calculate total income: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, SavingsGoalEntity?>> getSavingsGoal(String userId) async {
    try {
      // Try local first
      final localModel = await localDataSource.getLocalSavingsGoal(userId);
      if (localModel != null) {
        // Return local data and sync in background
        _syncSavingsGoalInBackground(userId);
        return Right(localModel.toEntity());
      }

      // Fetch from remote
      final remoteModel = await remoteDataSource.fetchSavingsGoal(userId);

      if (remoteModel != null) {
        // Cache locally
        await localDataSource.upsertLocalSavingsGoal(remoteModel);
        return Right(remoteModel.toEntity());
      }

      return const Right(null);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to get savings goal: ${e.toString()}'));
    }
  }

  Future<void> _syncSavingsGoalInBackground(String userId) async {
    try {
      final remoteModel = await remoteDataSource.fetchSavingsGoal(userId);
      if (remoteModel != null) {
        await localDataSource.upsertLocalSavingsGoal(remoteModel);
      }
    } catch (e) {
      // Silent fail for background sync
    }
  }

  @override
  Future<Either<Failure, SavingsGoalEntity>> setSavingsGoal(
      SavingsGoalEntity savingsGoal) async {
    try {
      // Check if goal already exists
      final existingGoal = await remoteDataSource.fetchSavingsGoal(savingsGoal.userId);

      final model = existingGoal != null
          ? await remoteDataSource.updateSavingsGoal(
              SavingsGoalModel.fromEntity(savingsGoal),
            )
          : await remoteDataSource.createSavingsGoal(
              SavingsGoalModel.fromEntity(savingsGoal),
            );

      // Cache locally
      await localDataSource.upsertLocalSavingsGoal(model);

      return Right(model.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to set savings goal: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, SavingsGoalEntity>> updateSavingsGoalAmount({
    required String userId,
    required int newAmount,
  }) async {
    try {
      final existingGoalResult = await getSavingsGoal(userId);

      return existingGoalResult.fold(
        (failure) => Left(failure),
        (existingGoal) async {
          if (existingGoal == null) {
            return Left(ServerFailure('No savings goal found for user'));
          }

          final updatedGoal = existingGoal.copyWith(
            amount: newAmount,
            updatedAt: DateTime.now(),
          );

          return await setSavingsGoal(updatedGoal);
        },
      );
    } catch (e) {
      return Left(ServerFailure('Failed to update savings goal amount: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, SavingsGoalEntity>> autoAdjustSavingsGoal({
    required String userId,
    required int newAmount,
  }) async {
    try {
      final existingGoalResult = await getSavingsGoal(userId);

      return existingGoalResult.fold(
        (failure) => Left(failure),
        (existingGoal) async {
          if (existingGoal == null) {
            return Left(ServerFailure('No savings goal found for user'));
          }

          // Set original_amount to current amount if not already adjusted
          final originalAmount = existingGoal.originalAmount ?? existingGoal.amount;

          final updatedGoal = existingGoal.copyWith(
            amount: newAmount,
            originalAmount: originalAmount,
            adjustedAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );

          return await setSavingsGoal(updatedGoal);
        },
      );
    } catch (e) {
      return Left(ServerFailure('Failed to auto-adjust savings goal: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteSavingsGoal(String userId) async {
    try {
      // Delete from remote
      await remoteDataSource.deleteSavingsGoal(userId);

      // Delete from local cache
      await localDataSource.deleteLocalSavingsGoal(userId);

      return const Right(null);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to delete savings goal: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, List<GroupExpenseAssignmentEntity>>>
      getGroupExpenseAssignments(String userId) async {
    try {
      // Try local first
      final localModels = await localDataSource.getLocalGroupExpenseAssignments(userId);

      if (localModels.isNotEmpty) {
        // Return local data and sync in background
        _syncGroupExpenseAssignmentsInBackground(userId);
        return Right(localModels.map((model) => model.toEntity()).toList());
      }

      // Fetch from remote
      final remoteModels = await remoteDataSource.fetchGroupExpenseAssignments(userId);

      // Cache locally
      await localDataSource.upsertLocalGroupExpenseAssignments(remoteModels);

      return Right(remoteModels.map((model) => model.toEntity()).toList());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to get group expense assignments: ${e.toString()}'));
    }
  }

  Future<void> _syncGroupExpenseAssignmentsInBackground(String userId) async {
    try {
      final remoteModels = await remoteDataSource.fetchGroupExpenseAssignments(userId);
      await localDataSource.upsertLocalGroupExpenseAssignments(remoteModels);
    } catch (e) {
      // Silent fail for background sync
    }
  }

  @override
  Future<Either<Failure, GroupExpenseAssignmentEntity>> getGroupExpenseAssignment(
      String id) async {
    try {
      // Try local first
      final localModel = await localDataSource.getLocalGroupExpenseAssignment(id);
      if (localModel != null) {
        return Right(localModel.toEntity());
      }

      // Fetch from remote
      final remoteModel = await remoteDataSource.fetchGroupExpenseAssignment(id);

      // Cache locally
      await localDataSource.upsertLocalGroupExpenseAssignment(remoteModel);

      return Right(remoteModel.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to get group expense assignment: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, GroupExpenseAssignmentEntity>> addGroupExpenseAssignment(
      GroupExpenseAssignmentEntity assignment) async {
    try {
      // Create in remote
      final model = await remoteDataSource.createGroupExpenseAssignment(
        GroupExpenseAssignmentModel.fromEntity(assignment),
      );

      // Cache locally
      await localDataSource.upsertLocalGroupExpenseAssignment(model);

      return Right(model.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to add group expense assignment: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, GroupExpenseAssignmentEntity>> updateGroupExpenseAssignment(
      GroupExpenseAssignmentEntity assignment) async {
    try {
      // Update in remote
      final model = await remoteDataSource.updateGroupExpenseAssignment(
        GroupExpenseAssignmentModel.fromEntity(assignment),
      );

      // Update local cache
      await localDataSource.upsertLocalGroupExpenseAssignment(model);

      return Right(model.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to update group expense assignment: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteGroupExpenseAssignment(String id) async {
    try {
      // Delete from remote
      await remoteDataSource.deleteGroupExpenseAssignment(id);

      // Delete from local cache
      await localDataSource.deleteLocalGroupExpenseAssignment(id);

      return const Right(null);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to delete group expense assignment: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, int>> getTotalGroupExpenses(String userId) async {
    try {
      final result = await getGroupExpenseAssignments(userId);

      return result.fold(
        (failure) => Left(failure),
        (assignments) {
          final total = assignments.fold<int>(
            0,
            (sum, assignment) => sum + assignment.spendingLimit,
          );
          return Right(total);
        },
      );
    } catch (e) {
      return Left(ServerFailure('Failed to calculate total group expenses: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, BudgetSummaryEntity>> getBudgetSummary(String userId) async {
    try {
      // Fetch all components
      final incomeResult = await getTotalIncome(userId);
      final savingsGoalResult = await getSavingsGoal(userId);
      final groupExpensesResult = await getTotalGroupExpenses(userId);

      // Check for failures
      if (incomeResult.isLeft()) return incomeResult as Either<Failure, BudgetSummaryEntity>;
      if (savingsGoalResult.isLeft()) return savingsGoalResult as Either<Failure, BudgetSummaryEntity>;
      if (groupExpensesResult.isLeft()) return groupExpensesResult as Either<Failure, BudgetSummaryEntity>;

      // Extract values
      final totalIncome = incomeResult.getOrElse(() => 0);
      final savingsGoal = savingsGoalResult.getOrElse(() => null);
      final totalGroupExpenses = groupExpensesResult.getOrElse(() => 0);

      // Create summary
      final summary = BudgetSummaryEntity.fromComponents(
        userId: userId,
        totalIncome: totalIncome,
        savingsGoal: savingsGoal?.amount ?? 0,
        totalGroupExpenses: totalGroupExpenses,
        hasIncome: totalIncome > 0,
        hasSavingsGoal: savingsGoal != null,
        hasGroupAssignments: totalGroupExpenses > 0,
      );

      return Right(summary);
    } catch (e) {
      return Left(ServerFailure('Failed to get budget summary: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, int>> getAvailableBudget(String userId) async {
    try {
      final summaryResult = await getBudgetSummary(userId);

      return summaryResult.fold(
        (failure) => Left(failure),
        (summary) => Right(summary.availableBudget),
      );
    } catch (e) {
      return Left(ServerFailure('Failed to calculate available budget: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, List<IncomeSourceEntity>>> addIncomeSources(
      List<IncomeSourceEntity> incomeSources) async {
    try {
      final models = incomeSources
          .map((entity) => IncomeSourceModel.fromEntity(entity))
          .toList();

      // Create all in remote
      final createdModels = await remoteDataSource.createIncomeSources(models);

      // Cache locally
      await localDataSource.upsertLocalIncomeSources(createdModels);

      return Right(createdModels.map((model) => model.toEntity()).toList());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to add income sources: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteAllIncomeSources(String userId) async {
    try {
      // Delete from remote
      await remoteDataSource.deleteAllIncomeSources(userId);

      // Delete from local cache
      await localDataSource.deleteAllLocalIncomeSources(userId);

      return const Right(null);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to delete all income sources: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteAllGroupExpenseAssignments(String userId) async {
    try {
      // Delete from remote
      await remoteDataSource.deleteAllGroupExpenseAssignments(userId);

      // Delete from local cache
      await localDataSource.deleteAllLocalGroupExpenseAssignments(userId);

      return const Right(null);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to delete all group expense assignments: ${e.toString()}'));
    }
  }

  @override
  Stream<List<IncomeSourceEntity>> watchIncomeSources(String userId) {
    return localDataSource
        .watchLocalIncomeSources(userId)
        .map((models) => models.map((model) => model.toEntity()).toList());
  }

  @override
  Stream<SavingsGoalEntity?> watchSavingsGoal(String userId) {
    return localDataSource
        .watchLocalSavingsGoal(userId)
        .map((model) => model?.toEntity());
  }

  @override
  Stream<List<GroupExpenseAssignmentEntity>> watchGroupExpenseAssignments(
      String userId) {
    return localDataSource
        .watchLocalGroupExpenseAssignments(userId)
        .map((models) => models.map((model) => model.toEntity()).toList());
  }

  @override
  Stream<BudgetSummaryEntity> watchBudgetSummary(String userId) {
    // Combine all three streams to compute budget summary reactively
    return Rx.combineLatest3(
      watchIncomeSources(userId),
      watchSavingsGoal(userId),
      watchGroupExpenseAssignments(userId),
      (List<IncomeSourceEntity> incomeSources,
          SavingsGoalEntity? savingsGoal,
          List<GroupExpenseAssignmentEntity> assignments) {
        final totalIncome = incomeSources.fold<int>(0, (sum, source) => sum + source.amount);
        final totalGroupExpenses = assignments.fold<int>(
          0,
          (sum, assignment) => sum + assignment.spendingLimit,
        );

        return BudgetSummaryEntity.fromComponents(
          userId: userId,
          totalIncome: totalIncome,
          savingsGoal: savingsGoal?.amount ?? 0,
          totalGroupExpenses: totalGroupExpenses,
          hasIncome: incomeSources.isNotEmpty,
          hasSavingsGoal: savingsGoal != null,
          hasGroupAssignments: assignments.isNotEmpty,
        );
      },
    );
  }
}
