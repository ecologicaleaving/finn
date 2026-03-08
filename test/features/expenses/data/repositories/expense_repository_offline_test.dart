import 'dart:typed_data';

import 'package:family_expense_tracker/core/enums/reimbursement_status.dart';
import 'package:family_expense_tracker/core/errors/exceptions.dart';
import 'package:family_expense_tracker/features/auth/domain/entities/user_entity.dart';
import 'package:family_expense_tracker/features/expenses/data/datasources/expense_local_cache_datasource.dart';
import 'package:family_expense_tracker/features/expenses/data/datasources/expense_remote_datasource.dart';
import 'package:family_expense_tracker/features/expenses/data/models/expense_model.dart';
import 'package:family_expense_tracker/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:family_expense_tracker/features/expenses/domain/entities/expense_entity.dart';
import 'package:family_expense_tracker/features/offline/data/datasources/offline_expense_local_datasource.dart';
import 'package:family_expense_tracker/features/offline/data/local/offline_database.dart';
import 'package:family_expense_tracker/features/offline/domain/entities/offline_expense_entity.dart';
import 'package:family_expense_tracker/shared/services/connectivity_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeExpenseRemoteDataSource implements ExpenseRemoteDataSource {
  @override
  Future<ExpenseModel> createExpense({
    required double amount,
    required DateTime date,
    required String categoryId,
    String? paymentMethodId,
    String? merchant,
    String? notes,
    bool isGroupExpense = true,
    ReimbursementStatus reimbursementStatus = ReimbursementStatus.none,
    String? createdBy,
    String? paidBy,
    String? lastModifiedBy,
  }) {
    throw ServerException('SocketException: offline');
  }

  @override
  Future<void> deleteExpense({required String expenseId}) async {}

  @override
  Future<ExpenseModel> getExpense({required String expenseId}) {
    throw UnimplementedError();
  }

  @override
  Future<List<ExpenseModel>> getExpenses({
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
    throw UnimplementedError();
  }

  @override
  Future<String> getReceiptUrl({required String receiptPath}) {
    throw UnimplementedError();
  }

  @override
  Future<String> uploadReceiptImage({
    required String expenseId,
    required Uint8List imageData,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ExpenseModel> updateExpense({
    required String expenseId,
    double? amount,
    DateTime? date,
    String? categoryId,
    String? paymentMethodId,
    String? merchant,
    String? notes,
    ReimbursementStatus? reimbursementStatus,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ExpenseModel> updateExpenseClassification({
    required String expenseId,
    required bool isGroupExpense,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ExpenseModel> updateExpenseWithTimestamp({
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
  }) {
    throw UnimplementedError();
  }
}

class _FakeExpenseLocalCacheDataSource implements ExpenseLocalCacheDataSource {
  final List<ExpenseEntity> cachedExpenses = [];

  @override
  Future<void> cacheExpenses(String userId, List<ExpenseEntity> expenses) async {
    cachedExpenses
      ..removeWhere((existing) => expenses.any((expense) => expense.id == existing.id))
      ..addAll(expenses);
  }

  @override
  Future<List<ExpenseEntity>> getCachedExpenses(String userId) async {
    return List<ExpenseEntity>.from(cachedExpenses);
  }

  @override
  Future<void> removeExpense(String userId, String expenseId) async {
    cachedExpenses.removeWhere((expense) => expense.id == expenseId);
  }

  @override
  Future<void> updateExpenseSyncStatus(
    String userId,
    String expenseId,
    String? syncStatus,
  ) async {
    final index = cachedExpenses.indexWhere((expense) => expense.id == expenseId);
    if (index == -1) return;
    cachedExpenses[index] = cachedExpenses[index].copyWith(syncStatus: syncStatus);
  }

  @override
  Future<void> upsertExpense(String userId, ExpenseEntity expense) async {
    final index = cachedExpenses.indexWhere((existing) => existing.id == expense.id);
    if (index == -1) {
      cachedExpenses.add(expense);
      return;
    }
    cachedExpenses[index] = expense;
  }
}

class _FakeOfflineExpenseLocalDataSource implements OfflineExpenseLocalDataSource {
  OfflineExpenseEntity? createdExpense;

  @override
  Future<void> addToSyncQueue({
    required String userId,
    required String operation,
    required String entityType,
    required String entityId,
    required Map<String, dynamic> payload,
    int priority = 0,
  }) async {}

  @override
  Future<OfflineExpenseEntity> createOfflineExpense({
    required String userId,
    required double amount,
    required DateTime date,
    required String categoryId,
    String? merchant,
    String? notes,
    bool isGroupExpense = true,
  }) async {
    createdExpense = OfflineExpenseEntity(
      id: 'offline-expense-1',
      userId: userId,
      amount: amount,
      date: date,
      categoryId: categoryId,
      merchant: merchant,
      notes: notes,
      isGroupExpense: isGroupExpense,
      syncStatus: 'pending',
      retryCount: 0,
      localCreatedAt: DateTime(2026, 3, 8, 10),
      localUpdatedAt: DateTime(2026, 3, 8, 10),
    );
    return createdExpense!;
  }

  @override
  Future<void> deleteCompletedSyncItems(List<int> itemIds) async {}

  @override
  Future<void> deleteOfflineExpense(String expenseId) async {}

  @override
  Future<List<OfflineExpenseEntity>> getAllOfflineExpenses(String userId) async => const [];

  @override
  Future<List<OfflineExpenseEntity>> getOfflineExpensesByStatus(String userId, String status) async => const [];

  @override
  Future<List<OfflineExpenseEntity>> getPendingExpenses(String userId) async => const [];

  @override
  Future<int> getPendingSyncCount(String userId) async => 1;

  @override
  Future<List<SyncQueueItem>> getPendingSyncItems(String userId, {int limit = 10}) async => const [];

  @override
  Future<void> updateSyncQueueItem(SyncQueueItemsCompanion companion) async {}

  @override
  Future<void> updateSyncStatus(String expenseId, String status, {String? errorMessage}) async {}
}

void main() {
  test('spesa aggiunta offline finisce in pending sync', () async {
    final cache = _FakeExpenseLocalCacheDataSource();
    final offlineDataSource = _FakeOfflineExpenseLocalDataSource();
    final repository = ExpenseRepositoryImpl(
      remoteDataSource: _FakeExpenseRemoteDataSource(),
      localCacheDataSource: cache,
      offlineLocalDataSource: offlineDataSource,
      currentUser: const UserEntity(
        id: 'user-1',
        email: 'offline@example.com',
        displayName: 'Offline User',
        groupId: 'group-1',
      ),
      networkStatus: NetworkStatus.offline,
    );

    final result = await repository.createExpense(
      amount: 24.9,
      date: DateTime(2026, 3, 8),
      categoryId: 'cat-1',
      paymentMethodId: 'cash',
      notes: 'Spesa offline',
    );

    expect(result.isRight(), isTrue);

    final expense = result.getOrElse(
      () => throw StateError('Expected a pending expense'),
    );

    expect(expense.syncStatus, 'pending');
    expect(cache.cachedExpenses.single.syncStatus, 'pending');
    expect(offlineDataSource.createdExpense?.id, 'offline-expense-1');
  });
}
