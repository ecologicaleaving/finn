import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/enums/reimbursement_status.dart';
import '../../../../core/enums/transaction_type.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../shared/services/connectivity_service.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../offline/data/datasources/offline_expense_local_datasource.dart';
import '../../domain/entities/expense_entity.dart';
import '../../domain/repositories/expense_repository.dart';
import '../../domain/utils/expense_ordering.dart';
import '../datasources/expense_local_cache_datasource.dart';
import '../datasources/expense_remote_datasource.dart';

/// Implementation of [ExpenseRepository] using remote data source.
class ExpenseRepositoryImpl implements ExpenseRepository {
  ExpenseRepositoryImpl({
    required this.remoteDataSource,
    required this.localCacheDataSource,
    required this.offlineLocalDataSource,
    required this.currentUser,
    required NetworkStatus? Function() networkStatusGetter,
  }) : _networkStatusGetter = networkStatusGetter;

  final ExpenseRemoteDataSource remoteDataSource;
  final ExpenseLocalCacheDataSource localCacheDataSource;
  final OfflineExpenseLocalDataSource offlineLocalDataSource;
  final UserEntity? currentUser;
  final NetworkStatus? Function() _networkStatusGetter;

  bool get _canUseRemote =>
      currentUser != null &&
      currentUser!.groupId != null &&
      _networkStatusGetter() == NetworkStatus.online;

  /// Writes go to the server unless the device is known to be offline.
  ///
  /// The status is `null`/`unknown` until the connectivity check completes;
  /// treating that as offline saved expenses locally while the device was
  /// online. Network errors still fall back to the offline queue.
  bool get _shouldTryRemoteWrite =>
      _networkStatusGetter() != NetworkStatus.offline;

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

  bool _matchesFilters(
    ExpenseEntity expense, {
    DateTime? startDate,
    DateTime? endDate,
    String? categoryId,
    String? createdBy,
    String? paidBy,
    bool? isGroupExpense,
    ReimbursementStatus? reimbursementStatus,
  }) {
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
  }

  /// Serves a page from the local cache (offline / network failure), with the
  /// same pagination contract as the online path: `offset`/`limit` count only
  /// synced expenses, and the pending ones that match the filters appear once,
  /// in the page with offset 0.
  List<ExpenseEntity> _pageFromCache(
    List<ExpenseEntity> cached, {
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
    final matching = cached
        .where((e) => _matchesFilters(
              e,
              startDate: startDate,
              endDate: endDate,
              categoryId: categoryId,
              createdBy: createdBy,
              paidBy: paidBy,
              isGroupExpense: isGroupExpense,
              reimbursementStatus: reimbursementStatus,
            ))
        .toList();
    final pending = matching.where((e) => e.isPendingSync).toList();
    final synced = matching.where((e) => !e.isPendingSync).toList()
      ..sort(compareExpensesNewestFirst);

    final safeOffset = offset ?? 0;
    final skipped = safeOffset >= synced.length
        ? const <ExpenseEntity>[]
        : synced.skip(safeOffset).toList();
    final page = limit == null ? skipped : skipped.take(limit).toList();

    if (safeOffset == 0) {
      return [...pending, ...page]..sort(compareExpensesNewestFirst);
    }
    return page;
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

  /// Adds the local pending expenses that match the filters to the remote
  /// page, but only for the first page (offset 0): later pages contain
  /// synced expenses only, so a pending expense is never repeated.
  List<ExpenseEntity> _mergeWithPendingCachedExpenses(
    List<ExpenseEntity> remoteExpenses,
    List<ExpenseEntity> cachedExpenses, {
    required int? offset,
    required bool Function(ExpenseEntity) matches,
  }) {
    final merged = <String, ExpenseEntity>{
      for (final expense in remoteExpenses) expense.id: expense,
    };

    if ((offset ?? 0) == 0) {
      for (final expense in cachedExpenses) {
        if (expense.isPendingSync &&
            matches(expense) &&
            !merged.containsKey(expense.id)) {
          merged[expense.id] = expense;
        }
      }
    }

    return merged.values.toList()..sort(compareExpensesNewestFirst);
  }

  /// Removes from the local cache the synced expenses that the server no
  /// longer has (deleted from another device), looking only at the window of
  /// the list covered by this remote page. Strictly conservative: anything
  /// not 'completed', with local work queued, outside the window or outside
  /// the filters is kept; any error is swallowed and nothing is removed.
  Future<void> _reconcileCache({
    required String userId,
    required List<ExpenseEntity> snapshot,
    required List<ExpenseEntity> remote,
    required bool Function(ExpenseEntity) matches,
    required int? limit,
    required int? offset,
  }) async {
    try {
      final safeOffset = offset ?? 0;
      if (safeOffset > 0 && remote.isEmpty) return;

      final sortedRemote = [...remote]..sort(compareExpensesNewestFirst);
      final first = safeOffset > 0 ? sortedRemote.first : null;
      final bool lowerOpen = limit == null || remote.length < limit;
      final last = lowerOpen ? null : sortedRemote.last;
      final remoteIds = remote.map((e) => e.id).toSet();

      final candidates = snapshot.where((e) {
        if (e.syncStatus != 'completed') return false;
        if (remoteIds.contains(e.id)) return false;
        if (!matches(e)) return false;
        if (first != null && compareExpensesNewestFirst(e, first) < 0) {
          return false;
        }
        if (last != null && compareExpensesNewestFirst(e, last) > 0) {
          return false;
        }
        return true;
      }).map((e) => e.id).toSet();
      if (candidates.isEmpty) return;

      final unsynced = await offlineLocalDataSource.getUnsyncedExpenseIds(userId);
      final toRemove = candidates.difference(unsynced);
      if (toRemove.isEmpty) return;

      await localCacheDataSource.removeSyncedExpenses(userId, toRemove);
    } catch (e) {
      debugPrint('ExpenseRepository: cache reconcile skipped: $e');
    }
  }

  /// Returns one page of expenses.
  ///
  /// Pagination contract: `offset` and `limit` count only synced expenses
  /// (those on the server). Local expenses not yet synced that match the
  /// filters appear exactly once, in the page with offset null or 0, merged
  /// in the same total order ([compareExpensesNewestFirst]).
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
    bool matches(ExpenseEntity e) => _matchesFilters(
          e,
          startDate: startDate,
          endDate: endDate,
          categoryId: categoryId,
          createdBy: createdBy,
          paidBy: paidBy,
          isGroupExpense: isGroupExpense,
          reimbursementStatus: reimbursementStatus,
        );

    Future<List<ExpenseEntity>> fromCache() async => _pageFromCache(
          await _loadCachedExpenses(),
          startDate: startDate,
          endDate: endDate,
          categoryId: categoryId,
          createdBy: createdBy,
          paidBy: paidBy,
          isGroupExpense: isGroupExpense,
          reimbursementStatus: reimbursementStatus,
          limit: limit,
          offset: offset,
        );

    if (!_canUseRemote) {
      return Right(await fromCache());
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
      final mergedExpenses = _mergeWithPendingCachedExpenses(
        entities,
        cachedExpenses,
        offset: offset,
        matches: matches,
      );
      final userId = currentUser?.id;
      if (userId != null) {
        await _reconcileCache(
          userId: userId,
          snapshot: cachedExpenses,
          remote: entities,
          matches: matches,
          limit: limit,
          offset: offset,
        );
      }
      await _cacheExpenses(mergedExpenses);
      return Right(mergedExpenses);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on GroupException catch (e) {
      return Left(GroupFailure(e.message));
    } on ServerException catch (e) {
      if (_isLikelyNetworkFailure(e)) {
        return Right(await fromCache());
      }
      return Left(ServerFailure(e.message));
    } catch (e) {
      if (_isLikelyNetworkFailure(e)) {
        return Right(await fromCache());
      }
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<ExpenseEntity?> _findCachedExpense(String expenseId) async {
    final cachedExpenses = await _loadCachedExpenses();
    for (final expense in cachedExpenses) {
      if (expense.id == expenseId) return expense;
    }
    return null;
  }

  Future<void> _cacheUpdatedExpense(ExpenseEntity expense) async {
    final userId = currentUser?.id;
    if (userId == null) return;
    // The server write already succeeded: a cache failure must not turn it
    // into an error for the caller.
    try {
      await localCacheDataSource.upsertExpense(
        userId,
        expense.copyWith(syncStatus: 'completed'),
      );
    } catch (cacheError) {
      debugPrint('ExpenseRepository: cache update failed: $cacheError');
    }
  }

  @override
  Future<Either<Failure, ExpenseEntity>> getExpense({
    required String expenseId,
  }) async {
    if (!_canUseRemote) {
      final cachedExpense = await _findCachedExpense(expenseId);
      if (cachedExpense != null) {
        return Right(cachedExpense);
      }
    }

    try {
      final expense = await remoteDataSource.getExpense(expenseId: expenseId);
      final entity = expense.toEntity().copyWith(syncStatus: 'completed');
      await _cacheExpenses([entity]);
      return Right(entity);
    } catch (e) {
      // Fall back to the local copy on any failure: besides network errors,
      // an expense saved offline and not yet uploaded is not on the server.
      final cachedExpense = await _findCachedExpense(expenseId);
      if (cachedExpense != null) {
        return Right(cachedExpense);
      }
      return Left(ServerFailure(e is ServerException ? e.message : e.toString()));
    }
  }

  /// Stores an expense locally and queues it for upload.
  ///
  /// All the fields chosen by the user (payment method, payer, reimbursement
  /// status, income/expense) are put in the sync payload so the server copy
  /// matches what the user entered.
  Future<ExpenseEntity> _createPendingExpense({
    required UserEntity user,
    required double amount,
    required DateTime date,
    required String categoryId,
    String? paymentMethodId,
    String? merchant,
    String? notes,
    required bool isGroupExpense,
    required ReimbursementStatus reimbursementStatus,
    String? createdBy,
    String? paidBy,
    String? lastModifiedBy,
    required TransactionType transactionType,
  }) async {
    final effectiveCreatedBy = createdBy ?? user.id;
    final effectivePaidBy = paidBy ?? effectiveCreatedBy;
    final effectiveLastModifiedBy = lastModifiedBy ?? effectiveCreatedBy;

    final offlineExpense = await offlineLocalDataSource.createOfflineExpense(
      userId: user.id,
      amount: amount,
      date: date,
      categoryId: categoryId,
      merchant: merchant,
      notes: notes,
      isGroupExpense: isGroupExpense,
      extraPayload: {
        'payment_method_id': paymentMethodId,
        'created_by': effectiveCreatedBy,
        'paid_by': effectivePaidBy,
        'last_modified_by': effectiveLastModifiedBy,
        'reimbursement_status': reimbursementStatus.value,
        'transaction_type': transactionType.value,
      },
    );

    final pendingExpense = ExpenseEntity(
      id: offlineExpense.id,
      groupId: user.groupId!,
      createdBy: effectiveCreatedBy,
      amount: amount,
      date: date,
      categoryId: categoryId,
      paymentMethodId: paymentMethodId ?? '',
      paymentMethodName: null,
      isGroupExpense: isGroupExpense,
      merchant: merchant,
      notes: notes,
      createdByName: user.displayName,
      paidBy: effectivePaidBy,
      paidByName: null,
      createdAt: offlineExpense.localCreatedAt,
      updatedAt: offlineExpense.localUpdatedAt,
      reimbursementStatus: reimbursementStatus,
      lastModifiedBy: effectiveLastModifiedBy,
      transactionType: transactionType,
      syncStatus: 'pending',
    );

    await localCacheDataSource.upsertExpense(user.id, pendingExpense);
    return pendingExpense;
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
    TransactionType transactionType = TransactionType.expense,
  }) async {
    final user = currentUser;
    if (user == null || user.groupId == null) {
      return const Left(AuthFailure('Nessun utente autenticato'));
    }

    if (!_shouldTryRemoteWrite) {
      try {
        return Right(await _createPendingExpense(
          user: user,
          amount: amount,
          date: date,
          categoryId: categoryId,
          paymentMethodId: paymentMethodId,
          merchant: merchant,
          notes: notes,
          isGroupExpense: isGroupExpense,
          reimbursementStatus: reimbursementStatus,
          createdBy: createdBy,
          paidBy: paidBy,
          lastModifiedBy: lastModifiedBy,
          transactionType: transactionType,
        ));
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
        transactionType: transactionType,
      );

      // Upload receipt if provided.
      //
      // The expense already exists on the server at this point: a failed
      // upload (network or otherwise) must NOT fall through to the offline
      // fallback below, otherwise a second copy of the expense would be
      // created (issue #48). Return the created expense without receipt.
      if (receiptImage != null) {
        try {
          final receiptPath = await remoteDataSource.uploadReceiptImage(
            expenseId: expense.id,
            imageData: receiptImage,
          );
          expense = expense.copyWith(receiptUrl: receiptPath);
        } catch (uploadError) {
          debugPrint(
            'ExpenseRepository: receipt upload failed for expense '
            '${expense.id}, keeping expense without receipt: $uploadError',
          );
        }
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
          return Right(await _createPendingExpense(
          user: user,
          amount: amount,
          date: date,
          categoryId: categoryId,
          paymentMethodId: paymentMethodId,
          merchant: merchant,
          notes: notes,
          isGroupExpense: isGroupExpense,
          reimbursementStatus: reimbursementStatus,
          createdBy: createdBy,
          paidBy: paidBy,
          lastModifiedBy: lastModifiedBy,
          transactionType: transactionType,
        ));
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
      final entity = expense.toEntity();
      await _cacheUpdatedExpense(entity);
      return Right(entity);
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
    bool? isGroupExpense,
    String? paidBy,
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
        isGroupExpense: isGroupExpense,
        paidBy: paidBy,
      );
      final entity = expense.toEntity();
      await _cacheUpdatedExpense(entity);
      return Right(entity);
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
    final user = currentUser;

    // An expense saved offline and never synced (its 'create' is still in the
    // sync queue) does not exist on the server: discard the offline row and
    // its queue items, otherwise the next sync would recreate it (issue #48).
    // Anything already synced falls through to the remote delete.
    if (user != null) {
      try {
        final discarded = await offlineLocalDataSource.discardUnsyncedExpense(
          expenseId: expenseId,
          userId: user.id,
        );
        if (discarded) {
          await localCacheDataSource.removeExpense(user.id, expenseId);
          return const Right(unit);
        }
      } catch (e) {
        return Left(ServerFailure(e.toString()));
      }
    }

    try {
      await remoteDataSource.deleteExpense(expenseId: expenseId);
      if (user != null) {
        await localCacheDataSource.removeExpense(user.id, expenseId);
        // Drop leftover offline data of a synced expense (e.g. a queued
        // offline 'update') so the sync does not replay it. Best effort:
        // the server delete already succeeded.
        try {
          await offlineLocalDataSource.removeLocalExpenseData(
            expenseId: expenseId,
            userId: user.id,
          );
        } catch (e) {
          debugPrint('deleteExpense: local offline cleanup failed: $e');
        }
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
      final entity = expense.toEntity();
      await _cacheUpdatedExpense(entity);
      return Right(entity);
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
