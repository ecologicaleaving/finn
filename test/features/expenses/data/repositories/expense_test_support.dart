import 'package:family_expense_tracker/core/enums/reimbursement_status.dart';
import 'package:family_expense_tracker/features/auth/domain/entities/user_entity.dart';
import 'package:family_expense_tracker/features/expenses/data/datasources/expense_local_cache_datasource.dart';
import 'package:family_expense_tracker/features/expenses/data/datasources/expense_remote_datasource.dart';
import 'package:family_expense_tracker/features/expenses/data/models/expense_model.dart';
import 'package:family_expense_tracker/features/expenses/domain/entities/expense_entity.dart';
import 'package:family_expense_tracker/features/expenses/domain/utils/expense_ordering.dart';
import 'package:family_expense_tracker/features/offline/data/datasources/offline_expense_local_datasource.dart';

const testUserId = 'user-1';

const testUser = UserEntity(
  id: testUserId,
  email: 'test@example.com',
  displayName: 'Test User',
  groupId: 'group-1',
);

ExpenseEntity makeExpense(
  String id, {
  DateTime? date,
  DateTime? createdAt,
  bool isGroupExpense = true,
  String categoryId = 'cat-1',
  String? syncStatus = 'completed',
}) =>
    ExpenseEntity(
      id: id,
      groupId: 'group-1',
      createdBy: testUserId,
      amount: 10,
      date: date ?? DateTime(2026, 9, 1),
      categoryId: categoryId,
      paymentMethodId: 'cash',
      isGroupExpense: isGroupExpense,
      paidBy: testUserId,
      createdAt: createdAt ?? date ?? DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
      reimbursementStatus: ReimbursementStatus.none,
      syncStatus: syncStatus,
    );

/// Remote fake backed by a list: honours the group filter, the total order,
/// limit and offset like the real query.
class FakeServer implements ExpenseRemoteDataSource {
  FakeServer(this.rows);

  List<ExpenseEntity> rows;
  Object? error;
  int calls = 0;

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
  }) async {
    calls++;
    if (error != null) throw error!;
    var list = rows
        .where((e) => isGroupExpense == null || e.isGroupExpense == isGroupExpense)
        .where((e) => categoryId == null || e.categoryId == categoryId)
        .toList()
      ..sort(compareExpensesNewestFirst);
    list = list.skip(offset ?? 0).toList();
    if (limit != null) list = list.take(limit).toList();
    return list.map(ExpenseModel.fromEntity).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCache implements ExpenseLocalCacheDataSource {
  FakeCache([Iterable<ExpenseEntity> initial = const []]) {
    items.addAll(initial);
  }

  final List<ExpenseEntity> items = [];

  List<String> get ids => items.map((e) => e.id).toList();

  @override
  Future<List<ExpenseEntity>> getCachedExpenses(String userId) async =>
      List.of(items);

  @override
  Future<void> cacheExpenses(String userId, List<ExpenseEntity> expenses) async {
    for (final e in expenses) {
      items.removeWhere((x) => x.id == e.id);
      items.add(e);
    }
  }

  @override
  Future<void> upsertExpense(String userId, ExpenseEntity expense) =>
      cacheExpenses(userId, [expense]);

  @override
  Future<void> updateExpenseSyncStatus(
      String userId, String expenseId, String? syncStatus) async {
    final i = items.indexWhere((e) => e.id == expenseId);
    if (i != -1) items[i] = items[i].copyWith(syncStatus: syncStatus);
  }

  @override
  Future<void> removeExpense(String userId, String expenseId) async {
    items.removeWhere((e) => e.id == expenseId);
  }

  @override
  Future<int> removeSyncedExpenses(String userId, Set<String> ids) async {
    final before = items.length;
    items.removeWhere((e) => ids.contains(e.id) && e.syncStatus == 'completed');
    return before - items.length;
  }
}

class FakeOffline implements OfflineExpenseLocalDataSource {
  Set<String> unsynced = {};
  bool throwOnUnsynced = false;

  @override
  Future<Set<String>> getUnsyncedExpenseIds(String userId) async {
    if (throwOnUnsynced) throw StateError('db down');
    return unsynced;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
