import 'dart:typed_data';

import 'package:dartz/dartz.dart';

import '../../../../core/enums/reimbursement_status.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../shared/services/connectivity_service.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../offline/data/datasources/offline_expense_local_datasource.dart';
import '../../domain/entities/expense_entity.dart';
import '../../domain/repositories/expense_repository.dart';
import '../datasources/expense_local_cache_datasource.dart';
import '../datasources/expense_remote_datasource.dart';

/// Implementation of [ExpenseRepository] using remote data source.
class ExpenseRepositoryImpl implements ExpenseRepository {
  ExpenseRepositoryImpl({
    required this.remoteDataSource,
    required this.localCacheDataSource,
    required this.offlineLocalDataSource,
    required this.currentUser,
    required this.networkStatus,
  });

  final ExpenseRemoteDataSource remoteDataSource;
  final ExpenseLocalCacheDataSource localCacheDataSource;
  final OfflineExpenseLocalDataSource offlineLocalDataSource;
  final UserEntity? currentUser;
  final NetworkStatus? networkStatus;

  bool get _canUseRemote =>
      currentUser != null &&
      currentUser!.groupId != null &&
      networkStatus != NetworkStatus.offline;

  bool _isLikelyNetworkFailure(Object error) {
    final message = error.toString();
    return message.contains('SocketException') ||
        message.contains('ClientException') ||
        message.contains('Failed host lookup') ||
        message.contains('network') ||
        message.contains('timed out');
  }

  Future<List<ExpenseEntity>> _loadCachedExpenses() async {
    final userId = currentUser?.id;
    if (userId == null) {
      return const [];
    }

    return localCacheDataSource.getCachedExpenses(userId);
  }

  List<ExpenseEntity> _applyLocalFilters(
    List<ExpenseEntity> expenses, {
    DateTime? startDate,
    DateTime? endDate,
    String? categoryId,
    String? createdBy,
    String? paidBy,
    bool? isGroupExpense,
    ReimbursementStatus? reimbursementStatus,
    int? limit,
    int? offset,
  }) {
    var filtered = expenses.where((expense) {
      final matchesStart = startDate == null ||
          !expense.date.isBefore(DateTime(startDate.year, startDate.month, startDate.day));
      final matchesEnd = endDate == null ||
          !expense.date.isAfter(DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59));
      final matchesCategory = categoryId == null || expense.categoryId == categoryId;
      final matchesCreatedBy = createdBy == null || expense.createdBy == createdBy;
      final matchesPaidBy = paidBy == null || expense.paidBy == paidBy;
      final matchesGroup = isGroupExpense == null || expense.isGroupExpense == isGroupExpense;
      final matchesReimbursement = reimbursementStatus == null ||
          expense.reimbursementStatus == reimbursementStatus;

      return matchesStart &&
          matchesEnd &&
          matchesCategory &&
          matchesCreatedBy &&
          matchesPaidBy &&
          matchesGroup &&
          matchesReimbursement;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final safeOffset = offset ?? 0;
    if (safeOffset >= filtered.length) {
      return const [];
    }

    if (limit == null) {
      return filtered.skip(safeOffset).toList();
    }

    return filtered.skip(safeOffset).take(limit).toList();
  }

  Future<void> _cacheExpenses(List<ExpenseEntity> expenses) async {
    final userId = currentUser?.id;
    if (userId == null || expenses.isEmpty) {
      return;
    }

    await localCacheDataSource.cacheExpenses(
      userId,
      expenses.map((expense) => expense.copyWith(syncStatus: expense.syncStatus ?? 'completed')).toList(),
    );
  }

  List<ExpenseEntity> _mergeWithPendingCachedExpenses(
    List<ExpenseEntity> remoteExpenses,
    List<ExpenseEntity> cachedExpenses,
  ) {
    final merged = <String, ExpenseEntity>{
      for (final expense in remoteExpenses) expense.id: expense,
    };

    for (final expense in cachedExpenses) {
      if (expense.isPendingSync && !merged.containsKey(expense.id)) {
        merged[expense.id] = expense;
      }
    }

    return merged.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  @override
  Future<Either<Failure, List<ExpenseEntity>>> getExpenses({
    DateTime? startDate,
    DateTime? endDate,
    String? categoryId,
    String? createdBy,
    String? paidBy,
    bool? isGroupExpense,
    ReimbursementStatus? reimbursementStatus, // T048
    int? limit,
    int? offset,
  }) async {
    if (!_canUseRemote) {
      final cachedExpenses = _applyLocalFilters(
        await _loadCachedExpenses(),
        startDate: startDate,
        endDate: endDate,
        categoryId: categoryId,
        createdBy: createdBy,
        paidBy: paidBy,
        isGroupExpense: isGroupExpense,
        reimbursementStatus: reimbursementStatus,
      );
      return Right(
        _applyLocalFilters(
          cachedExpenses,
          startDate: startDate,
          endDate: endDate,
          categoryId: categoryId,
          createdBy: createdBy,
          paidBy: paidBy,
          isGroupExpense: isGroupExpense,
          reimbursementStatus: reimbursementStatus,
          limit: limit,
          offset: offset,
        ),
      );
    }

    try {
      final cachedExpenses = await _loadCachedExpenses();
      final expenses = await remoteDataSource.getExpenses(
        startDate: startDate,
        endDate: endDate,
        categoryId: categoryId,
        createdBy: createdBy,
        paidBy: paidBy,
        isGroupExpense: isGroupExpense,
        reimbursementStatus: reimbursementStatus, // T048
        limit: limit,
        offset: offset,
      );
      final entities = expenses
          .map((e) => e.toEntity().copyWith(syncStatus: 'completed'))
          .toList();
      final mergedExpenses = _mergeWithPendingCachedExpenses(entities, cachedExpenses);
      await _cacheExpenses(mergedExpenses);
      return Right(mergedExpenses);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on GroupException catch (e) {
      return Left(GroupFailure(e.message));
    } on ServerException catch (e) {
      if (_isLikelyNetworkFailure(e)) {
        final cachedExpenses = await _loadCachedExpenses();
        return Right(
          _applyLocalFilters(
            cachedExpenses,
            startDate: startDate,
            endDate: endDate,
            categoryId: categoryId,
            createdBy: createdBy,
            paidBy: paidBy,
            isGroupExpense: isGroupExpense,
            reimbursementStatus: reimbursementStatus,
            limit: limit,
            offset: offset,
          ),
        );
      }
      return Left(ServerFailure(e.message));
    } catch (e) {
      if (_isLikelyNetworkFailure(e)) {
        final cachedExpenses = await _loadCachedExpenses();
        return Right(
          _applyLocalFilters(
            cachedExpenses,
            startDate: startDate,
            endDate: endDate,
            categoryId: categoryId,
            createdBy: createdBy,
            paidBy: paidBy,
            isGroupExpense: isGroupExpense,
            reimbursementStatus: reimbursementStatus,
            limit: limit,
            offset: offset,
          ),
        );
      }
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ExpenseEntity>> getExpense({
    required String expenseId,
  }) async {
    if (!_canUseRemote) {
      final cachedExpenses = await _loadCachedExpenses();
      final cachedExpense = cachedExpenses.where((expense) => expense.id == expenseId).toList();
      if (cachedExpense.isNotEmpty) {
        return Right(cachedExpense.first);
      }
    }

    try {
      final expense = await remoteDataSource.getExpense(expenseId: expenseId);
      final entity = expense.toEntity().copyWith(syncStatus: 'completed');
      await _cacheExpenses([entity]);
      return Right(entity);
    } on ServerException catch (e) {
      if (_isLikelyNetworkFailure(e)) {
        final cachedExpenses = await _loadCachedExpenses();
        final cachedExpense = cachedExpenses.where((expense) => expense.id == expenseId).toList();
        if (cachedExpense.isNotEmpty) {
          return Right(cachedExpense.first);
        }
      }
      return Left(ServerFailure(e.message));
    } catch (e) {
      if (_isLikelyNetworkFailure(e)) {
        final cachedExpenses = await _loadCachedExpenses();
        final cachedExpense = cachedExpenses.where((expense) => expense.id == expenseId).toList();
        if (cachedExpense.isNotEmpty) {
          return Right(cachedExpense.first);
        }
      }
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ExpenseEntity>> createExpense({
    required double amount,
    required DateTime date,
    required String categoryId,
    String? paymentMethodId, // Defaults to "Contanti" if null
    String? merchant,
    String? notes,
    Uint8List? receiptImage,
    bool isGroupExpense = true,
    ReimbursementStatus reimbursementStatus = ReimbursementStatus.none, // T048
    String? createdBy, // T014
    String? paidBy, // For admin creating expense for specific member
    String? lastModifiedBy, // T014
  }) async {
    final user = currentUser;
    if (user == null || user.groupId == null) {
      return const Left(AuthFailure('Nessun utente autenticato'));
    }

    if (!_canUseRemote) {
      try {
        final offlineExpense = await offlineLocalDataSource.createOfflineExpense(
          userId: user.id,
          amount: amount,
          date: date,
          categoryId: categoryId,
          merchant: merchant,
          notes: notes,
          isGroupExpense: isGroupExpense,
        );

        final pendingExpense = ExpenseEntity(
          id: offlineExpense.id,
          groupId: user.groupId!,
          createdBy: createdBy ?? user.id,
          amount: amount,
          date: date,
          categoryId: categoryId,
          paymentMethodId: paymentMethodId ?? '',
          paymentMethodName: null,
          isGroupExpense: isGroupExpense,
          merchant: merchant,
          notes: notes,
          createdByName: user.displayName,
          paidBy: paidBy ?? user.id,
          paidByName: null,
          createdAt: offlineExpense.localCreatedAt,
          updatedAt: offlineExpense.localUpdatedAt,
          reimbursementStatus: reimbursementStatus,
          lastModifiedBy: lastModifiedBy ?? createdBy ?? user.id,
          syncStatus: 'pending',
        );

        await localCacheDataSource.upsertExpense(user.id, pendingExpense);
        return Right(pendingExpense);
      } catch (e) {
        return Left(ServerFailure(e.toString()));
      }
    }

    try {
      // Create the expense first
      var expense = await remoteDataSource.createExpense(
        amount: amount,
        date: date,
        categoryId: categoryId,
        paymentMethodId: paymentMethodId,
        merchant: merchant,
        notes: notes,
        isGroupExpense: isGroupExpense,
        reimbursementStatus: reimbursementStatus, // T048
        createdBy: createdBy, // T014
        paidBy: paidBy, // For admin creating expense for specific member
        lastModifiedBy: lastModifiedBy, // T014
      );

      // Upload receipt if provided
      if (receiptImage != null) {
        final receiptPath = await remoteDataSource.uploadReceiptImage(
          expenseId: expense.id,
          imageData: receiptImage,
        );
        expense = expense.copyWith(receiptUrl: receiptPath);
      }

      final entity = expense.toEntity().copyWith(syncStatus: 'completed');
      await localCacheDataSource.upsertExpense(user.id, entity);
      return Right(entity);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on GroupException catch (e) {
      return Left(GroupFailure(e.message));
    } on ServerException catch (e) {
      if (_isLikelyNetworkFailure(e)) {
        try {
          final offlineExpense = await offlineLocalDataSource.createOfflineExpense(
            userId: user.id,
            amount: amount,
            date: date,
            categoryId: categoryId,
            merchant: merchant,
            notes: notes,
            isGroupExpense: isGroupExpense,
          );

          final pendingExpense = ExpenseEntity(
            id: offlineExpense.id,
            groupId: user.groupId!,
            createdBy: createdBy ?? user.id,
            amount: amount,
            date: date,
            categoryId: categoryId,
            paymentMethodId: paymentMethodId ?? '',
            paymentMethodName: null,
            isGroupExpense: isGroupExpense,
            merchant: merchant,
            notes: notes,
            createdByName: user.displayName,
            paidBy: paidBy ?? user.id,
            paidByName: null,
            createdAt: offlineExpense.localCreatedAt,
            updatedAt: offlineExpense.localUpdatedAt,
            reimbursementStatus: reimbursementStatus,
            lastModifiedBy: lastModifiedBy ?? createdBy ?? user.id,
            syncStatus: 'pending',
          );

          await localCacheDataSource.upsertExpense(user.id, pendingExpense);
          return Right(pendingExpense);
        } catch (cacheError) {
          return Left(ServerFailure(cacheError.toString()));
        }
      }
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ExpenseEntity>> updateExpense({
    required String expenseId,
    double? amount,
    DateTime? date,
    String? categoryId,
    String? paymentMethodId,
    String? merchant,
    String? notes,
    ReimbursementStatus? reimbursementStatus, // T048
  }) async {
    try {
      final expense = await remoteDataSource.updateExpense(
        expenseId: expenseId,
        amount: amount,
        date: date,
        categoryId: categoryId,
        paymentMethodId: paymentMethodId,
        merchant: merchant,
        notes: notes,
        reimbursementStatus: reimbursementStatus, // T048
      );
      return Right(expense.toEntity());
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ExpenseEntity>> updateExpenseWithTimestamp({
    required String expenseId,
    required DateTime originalUpdatedAt,
    required String lastModifiedBy,
    double? amount,
    DateTime? date,
    String? categoryId,
    String? paymentMethodId,
    String? merchant,
    String? notes,
    ReimbursementStatus? reimbursementStatus,
  }) async {
    try {
      final expense = await remoteDataSource.updateExpenseWithTimestamp(
        expenseId: expenseId,
        originalUpdatedAt: originalUpdatedAt,
        lastModifiedBy: lastModifiedBy,
        amount: amount,
        date: date,
        categoryId: categoryId,
        paymentMethodId: paymentMethodId,
        merchant: merchant,
        notes: notes,
        reimbursementStatus: reimbursementStatus,
      );
      return Right(expense.toEntity());
    } on ConflictException catch (e) {
      return Left(ConflictFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteExpense({
    required String expenseId,
  }) async {
    try {
      await remoteDataSource.deleteExpense(expenseId: expenseId);
      if (currentUser != null) {
        await localCacheDataSource.removeExpense(currentUser!.id, expenseId);
      }
      return const Right(unit);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ExpenseEntity>> updateExpenseClassification({
    required String expenseId,
    required bool isGroupExpense,
  }) async {
    try {
      final expense = await remoteDataSource.updateExpenseClassification(
        expenseId: expenseId,
        isGroupExpense: isGroupExpense,
      );
      return Right(expense.toEntity());
    } on PermissionException catch (e) {
      return Left(PermissionFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, String>> uploadReceiptImage({
    required String expenseId,
    required Uint8List imageData,
  }) async {
    try {
      final path = await remoteDataSource.uploadReceiptImage(
        expenseId: expenseId,
        imageData: imageData,
      );
      return Right(path);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, String>> getReceiptUrl({
    required String receiptPath,
  }) async {
    try {
      final url = await remoteDataSource.getReceiptUrl(receiptPath: receiptPath);
      return Right(url);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ExpensesSummary>> getExpensesSummary({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final expenses = await remoteDataSource.getExpenses(
        startDate: startDate,
        endDate: endDate,
      );

      // Calculate totals
      double totalAmount = 0;
      final byCategory = <String, double>{};
      final byMember = <String, _MemberAccumulator>{};

      for (final expense in expenses) {
        totalAmount += expense.amount;

        // By category
        final categoryKey = expense.categoryName ?? 'N/A';
        byCategory[categoryKey] = (byCategory[categoryKey] ?? 0) + expense.amount;

        // By member - use paidBy to attribute expense to correct member
        // This ensures expenses created by admin for other members are counted correctly
        final memberKey = expense.paidBy ?? expense.createdBy;
        final memberName = expense.paidByName ?? expense.createdByName ?? 'Utente';

        if (!byMember.containsKey(memberKey)) {
          byMember[memberKey] = _MemberAccumulator(
            displayName: memberName,
          );
        }
        byMember[memberKey]!.totalAmount += expense.amount;
        byMember[memberKey]!.expenseCount++;
      }

      return Right(ExpensesSummary(
        totalAmount: totalAmount,
        expenseCount: expenses.length,
        byCategory: byCategory,
        byMember: byMember.map((key, value) => MapEntry(
          key,
          MemberExpenses(
            userId: key,
            displayName: value.displayName,
            totalAmount: value.totalAmount,
            expenseCount: value.expenseCount,
          ),
        )),
      ));
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on GroupException catch (e) {
      return Left(GroupFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}

class _MemberAccumulator {
  _MemberAccumulator({required this.displayName});

  final String displayName;
  double totalAmount = 0;
  int expenseCount = 0;
}
