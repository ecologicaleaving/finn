import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../../domain/entities/expense_entity.dart';
import '../../domain/utils/expense_ordering.dart';
import '../models/expense_model.dart';

abstract class ExpenseLocalCacheDataSource {
  Future<List<ExpenseEntity>> getCachedExpenses(String userId);
  Future<void> cacheExpenses(String userId, List<ExpenseEntity> expenses);
  Future<void> upsertExpense(String userId, ExpenseEntity expense);
  Future<void> updateExpenseSyncStatus(
    String userId,
    String expenseId,
    String? syncStatus,
  );
  Future<void> removeExpense(String userId, String expenseId);

  /// Removes from the cache the expenses in [ids] that, at the moment of the
  /// write, still have `syncStatus == 'completed'`. Anything else (pending,
  /// failed, syncing, conflict, unknown) is never removed.
  ///
  /// Returns the number of removed expenses.
  Future<int> removeSyncedExpenses(String userId, Set<String> ids);
}

class HiveExpenseLocalCacheDataSource implements ExpenseLocalCacheDataSource {
  HiveExpenseLocalCacheDataSource({Box<String>? box})
      : _box = box ?? Hive.box<String>('expense_cache');

  final Box<String> _box;

  // Every read-modify-write of the box goes through this chain, shared by all
  // instances, so two writers can never interleave and drop each other's
  // changes (e.g. a cache refresh overwriting a freshly saved pending expense).
  static Future<void> _writeChain = Future<void>.value();

  static Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _writeChain.then((_) => action());
    _writeChain = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  String _userKey(String userId) => 'expenses_$userId';

  @override
  Future<List<ExpenseEntity>> getCachedExpenses(String userId) async {
    final raw = _box.get(_userKey(userId));
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => ExpenseModel.fromJson(item as Map<String, dynamic>).toEntity())
        .toList();
  }

  @override
  Future<void> cacheExpenses(String userId, List<ExpenseEntity> expenses) =>
      _serialized(() async {
        final existing = await getCachedExpenses(userId);
        final merged = <String, ExpenseEntity>{
          for (final expense in existing) expense.id: expense,
        };

        for (final expense in expenses) {
          merged[expense.id] = expense;
        }

        await _persist(userId, merged.values.toList());
      });

  @override
  Future<void> upsertExpense(String userId, ExpenseEntity expense) =>
      _serialized(() async {
        final existing = await getCachedExpenses(userId);
        final merged = <String, ExpenseEntity>{
          for (final item in existing) item.id: item,
          expense.id: expense,
        };
        await _persist(userId, merged.values.toList());
      });

  @override
  Future<void> updateExpenseSyncStatus(
    String userId,
    String expenseId,
    String? syncStatus,
  ) =>
      _serialized(() async {
        final existing = await getCachedExpenses(userId);
        final updated = existing
            .map(
              (expense) => expense.id == expenseId
                  ? expense.copyWith(syncStatus: syncStatus)
                  : expense,
            )
            .toList();
        await _persist(userId, updated);
      });

  @override
  Future<void> removeExpense(String userId, String expenseId) =>
      _serialized(() async {
        final existing = await getCachedExpenses(userId);
        await _persist(
          userId,
          existing.where((expense) => expense.id != expenseId).toList(),
        );
      });

  @override
  Future<int> removeSyncedExpenses(String userId, Set<String> ids) {
    if (ids.isEmpty) return Future.value(0);
    return _serialized(() async {
      // Re-read inside the lock: only expenses that are 'completed' NOW are
      // removed, whatever their state was when the caller picked them.
      final existing = await getCachedExpenses(userId);
      final kept = existing
          .where((e) => !(ids.contains(e.id) && e.syncStatus == 'completed'))
          .toList();
      final removed = existing.length - kept.length;
      if (removed > 0) {
        await _persist(userId, kept);
      }
      return removed;
    });
  }

  Future<void> _persist(String userId, List<ExpenseEntity> expenses) async {
    expenses.sort(compareExpensesNewestFirst);
    final encoded = jsonEncode(
      expenses.map((expense) => ExpenseModel.fromEntity(expense).toJson()).toList(),
    );
    await _box.put(_userKey(userId), encoded);
  }
}
