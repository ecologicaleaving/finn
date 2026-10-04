import 'dart:typed_data';

import 'package:family_expense_tracker/core/enums/reimbursement_status.dart';
import 'package:family_expense_tracker/core/enums/transaction_type.dart';
import 'package:family_expense_tracker/core/errors/exceptions.dart';
import 'package:family_expense_tracker/features/auth/domain/entities/user_entity.dart';
import 'package:family_expense_tracker/features/expenses/data/datasources/expense_local_cache_datasource.dart';
import 'package:family_expense_tracker/features/expenses/data/datasources/expense_remote_datasource.dart';
import 'package:family_expense_tracker/features/expenses/data/models/expense_model.dart';
import 'package:family_expense_tracker/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:family_expense_tracker/features/expenses/domain/entities/expense_entity.dart';
import 'package:family_expense_tracker/features/offline/data/datasources/offline_expense_local_datasource.dart';
import 'package:family_expense_tracker/features/offline/domain/entities/offline_expense_entity.dart';
import 'package:family_expense_tracker/shared/services/connectivity_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _user = UserEntity(
  id: 'user-1',
  email: 'test@example.com',
  displayName: 'Test User',
  groupId: 'group-1',
);

class _FakeRemote implements ExpenseRemoteDataSource {
  Object? createError;
  Object? uploadError;
  int createCalls = 0;
  int uploadCalls = 0;
  final List<String> deletedIds = [];

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
    TransactionType transactionType = TransactionType.expense,
  }) async {
    createCalls++;
    if (createError != null) throw createError!;
    return ExpenseModel(
      id: 'srv-1',
      groupId: 'group-1',
      createdBy: 'user-1',
      amount: amount,
      date: date,
      categoryId: categoryId,
      paymentMethodId: paymentMethodId ?? 'cash',
      isGroupExpense: isGroupExpense,
      paidBy: paidBy ?? 'user-1',
    );
  }

  @override
  Future<String> uploadReceiptImage({
    required String expenseId,
    required Uint8List imageData,
  }) async {
    uploadCalls++;
    if (uploadError != null) throw uploadError!;
    return 'receipts/$expenseId.jpg';
  }

  @override
  Future<void> deleteExpense({required String expenseId}) async {
    deletedIds.add(expenseId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCache implements ExpenseLocalCacheDataSource {
  final List<ExpenseEntity> cachedExpenses = [];

  @override
  Future<List<ExpenseEntity>> getCachedExpenses(String userId) async =>
      List<ExpenseEntity>.from(cachedExpenses);

  @override
  Future<void> removeExpense(String userId, String expenseId) async {
    cachedExpenses.removeWhere((expense) => expense.id == expenseId);
  }

  @override
  Future<void> upsertExpense(String userId, ExpenseEntity expense) async {
    final index = cachedExpenses.indexWhere((e) => e.id == expense.id);
    if (index == -1) {
      cachedExpenses.add(expense);
    } else {
      cachedExpenses[index] = expense;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOffline implements OfflineExpenseLocalDataSource {
  _FakeOffline({this.discardResult = false});

  final bool discardResult;
  final List<String> discardCalls = [];
  int createOfflineCalls = 0;

  @override
  Future<bool> discardUnsyncedExpense({
    required String expenseId,
    required String userId,
  }) async {
    discardCalls.add('$expenseId/$userId');
    return discardResult;
  }

  final List<String> removeLocalCalls = [];

  @override
  Future<void> removeLocalExpenseData({
    required String expenseId,
    required String userId,
  }) async {
    removeLocalCalls.add('$expenseId/$userId');
  }

  @override
  Future<OfflineExpenseEntity> createOfflineExpense({
    required String userId,
    required double amount,
    required DateTime date,
    required String categoryId,
    String? merchant,
    String? notes,
    bool isGroupExpense = true,
    Map<String, dynamic>? extraPayload,
    Uint8List? receiptBytes,
  }) async {
    createOfflineCalls++;
    return OfflineExpenseEntity(
      id: 'offline-$createOfflineCalls',
      userId: userId,
      amount: amount,
      date: date,
      categoryId: categoryId,
      merchant: merchant,
      notes: notes,
      isGroupExpense: isGroupExpense,
      syncStatus: 'pending',
      retryCount: 0,
      localCreatedAt: DateTime(2026, 9, 26),
      localUpdatedAt: DateTime(2026, 9, 26),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ExpenseEntity _pendingExpense(String id) => ExpenseEntity(
      id: id,
      groupId: 'group-1',
      createdBy: 'user-1',
      amount: 12,
      date: DateTime(2026, 9, 25),
      categoryId: 'cat-1',
      paymentMethodId: 'cash',
      paidBy: 'user-1',
      syncStatus: 'pending',
    );

ExpenseRepositoryImpl _repo({
  required _FakeRemote remote,
  required _FakeCache cache,
  required _FakeOffline offline,
  NetworkStatus network = NetworkStatus.online,
}) {
  return ExpenseRepositoryImpl(
    remoteDataSource: remote,
    localCacheDataSource: cache,
    offlineLocalDataSource: offline,
    currentUser: _user,
    networkStatusGetter: () => network,
  );
}

void main() {
  group('deleteExpense of an unsynced offline expense (AC5)', () {
    for (final network in [NetworkStatus.online, NetworkStatus.offline]) {
      test('discards offline row + queue item without calling remote ($network)',
          () async {
        final remote = _FakeRemote();
        final cache = _FakeCache()..cachedExpenses.add(_pendingExpense('X'));
        final offline = _FakeOffline(discardResult: true);

        final result = await _repo(
          remote: remote,
          cache: cache,
          offline: offline,
          network: network,
        ).deleteExpense(expenseId: 'X');

        expect(result.isRight(), isTrue);
        expect(offline.discardCalls, ['X/user-1']);
        expect(remote.deletedIds, isEmpty);
        expect(cache.cachedExpenses, isEmpty);
        expect(offline.removeLocalCalls, isEmpty);
      });
    }

    test('synced expense (nothing to discard) is deleted on the server',
        () async {
      final remote = _FakeRemote();
      final cache = _FakeCache()
        ..cachedExpenses.add(_pendingExpense('S').copyWith(syncStatus: 'completed'));
      final offline = _FakeOffline(discardResult: false);

      final result = await _repo(remote: remote, cache: cache, offline: offline)
          .deleteExpense(expenseId: 'S');

      expect(result.isRight(), isTrue);
      expect(offline.discardCalls, ['S/user-1']);
      expect(remote.deletedIds, ['S']);
      expect(cache.cachedExpenses, isEmpty);
      expect(offline.removeLocalCalls, ['S/user-1']);
    });
  });

  group('createExpense with receipt upload failure (AC6)', () {
    test('network error on upload returns the created expense, no offline copy',
        () async {
      final remote = _FakeRemote()
        ..uploadError = ServerException('SocketException: Failed host lookup');
      final cache = _FakeCache();
      final offline = _FakeOffline();

      final result = await _repo(remote: remote, cache: cache, offline: offline)
          .createExpense(
        amount: 30,
        date: DateTime(2026, 9, 26),
        categoryId: 'cat-1',
        paymentMethodId: 'cash',
        receiptImage: Uint8List.fromList([1, 2, 3]),
      );

      final expense = result.getOrElse(() => throw StateError('expected Right'));
      expect(expense.id, 'srv-1');
      expect(expense.receiptUrl, isNull);
      expect(expense.syncStatus, 'completed');
      expect(remote.createCalls, 1);
      expect(remote.uploadCalls, 1);
      expect(offline.createOfflineCalls, 0);
      expect(cache.cachedExpenses.map((e) => e.id).toList(), ['srv-1']);
    });

    test('non-network upload error also keeps the single created expense',
        () async {
      final remote = _FakeRemote()..uploadError = ServerException('413 too large');
      final cache = _FakeCache();
      final offline = _FakeOffline();

      final result = await _repo(remote: remote, cache: cache, offline: offline)
          .createExpense(
        amount: 30,
        date: DateTime(2026, 9, 26),
        categoryId: 'cat-1',
        paymentMethodId: 'cash',
        receiptImage: Uint8List.fromList([1, 2, 3]),
      );

      expect(result.isRight(), isTrue);
      expect(offline.createOfflineCalls, 0);
      expect(cache.cachedExpenses, hasLength(1));
    });

    test('successful upload stores the receipt path', () async {
      final remote = _FakeRemote();
      final cache = _FakeCache();
      final offline = _FakeOffline();

      final result = await _repo(remote: remote, cache: cache, offline: offline)
          .createExpense(
        amount: 30,
        date: DateTime(2026, 9, 26),
        categoryId: 'cat-1',
        paymentMethodId: 'cash',
        receiptImage: Uint8List.fromList([1, 2, 3]),
      );

      final expense = result.getOrElse(() => throw StateError('expected Right'));
      expect(expense.receiptUrl, 'receipts/srv-1.jpg');
    });

    test('network error on the insert still saves a single offline expense',
        () async {
      final remote = _FakeRemote()
        ..createError = ServerException('SocketException: Failed host lookup');
      final cache = _FakeCache();
      final offline = _FakeOffline();

      final result = await _repo(remote: remote, cache: cache, offline: offline)
          .createExpense(
        amount: 30,
        date: DateTime(2026, 9, 26),
        categoryId: 'cat-1',
        paymentMethodId: 'cash',
        receiptImage: Uint8List.fromList([1, 2, 3]),
      );

      final expense = result.getOrElse(() => throw StateError('expected Right'));
      expect(expense.syncStatus, 'pending');
      expect(remote.uploadCalls, 0);
      expect(offline.createOfflineCalls, 1);
      expect(cache.cachedExpenses, hasLength(1));
    });
  });
}
