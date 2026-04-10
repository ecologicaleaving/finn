import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../../domain/entities/expense_entity.dart';
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
}

class HiveExpenseLocalCacheDataSource implements ExpenseLocalCacheDataSource {
  HiveExpenseLocalCacheDataSource({Box<String>? box})
      : _box = box ?? Hive.box<String>('expense_cache');

  final Box<String> _box;

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
  Future<void> cacheExpenses(String userId, List<ExpenseEntity> expenses) async {
    final existing = await getCachedExpenses(userId);
    final merged = <String, ExpenseEntity>{
      for (final expense in existing) expense.id: expense,
    };

    for (final expense in expenses) {
      merged[expense.id] = expense;
    }

    await _persist(userId, merged.values.toList());
  }

  @override
  Future<void> upsertExpense(String userId, ExpenseEntity expense) async {
    final existing = await getCachedExpenses(userId);
    final merged = <String, ExpenseEntity>{
      for (final item in existing) item.id: item,
      expense.id: expense,
    };
    await _persist(userId, merged.values.toList());
  }

  @override
  Future<void> updateExpenseSyncStatus(
    String userId,
    String expenseId,
    String? syncStatus,
  ) async {
    final existing = await getCachedExpenses(userId);
    final updated = existing
        .map(
          (expense) => expense.id == expenseId
              ? expense.copyWith(syncStatus: syncStatus)
              : expense,
        )
        .toList();
    await _persist(userId, updated);
  }

  @override
  Future<void> removeExpense(String userId, String expenseId) async {
    final existing = await getCachedExpenses(userId);
    await _persist(
      userId,
      existing.where((expense) => expense.id != expenseId).toList(),
    );
  }

  Future<void> _persist(String userId, List<ExpenseEntity> expenses) async {
    expenses.sort((a, b) => b.date.compareTo(a.date));
    final encoded = jsonEncode(
      expenses.map((expense) => ExpenseModel.fromEntity(expense).toJson()).toList(),
    );
    await _box.put(_userKey(userId), encoded);
  }
}
