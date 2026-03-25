import 'package:drift/drift.dart';

import '../../../../core/enums/reimbursement_status.dart';
import '../../../expenses/data/models/expense_model.dart';
import '../local/offline_database.dart';

/// Local data source for caching expenses fetched from Supabase.
/// Provides read-through cache for offline access.
abstract class ExpenseCacheDataSource {
  /// Cache a list of expenses for a group (replaces previous cache for same group).
  Future<void> cacheExpenses(String groupId, List<ExpenseModel> expenses);

  /// Get cached expenses for a group, optionally filtered.
  Future<List<ExpenseModel>> getCachedExpenses(
    String groupId, {
    DateTime? startDate,
    DateTime? endDate,
    String? categoryId,
    String? createdBy,
    int? limit,
    int? offset,
  });

  /// Clear cached expenses for a group.
  Future<void> clearCache(String groupId);

  /// Clear all cached expenses.
  Future<void> clearAllCache();
}

class ExpenseCacheDataSourceImpl implements ExpenseCacheDataSource {
  ExpenseCacheDataSourceImpl({required OfflineDatabase database}) : _db = database;

  final OfflineDatabase _db;

  @override
  Future<void> cacheExpenses(String groupId, List<ExpenseModel> expenses) async {
    // Replace cache for this group
    await (_db.delete(_db.cachedExpenses)
          ..where((tbl) => tbl.groupId.equals(groupId)))
        .go();

    final now = DateTime.now();
    for (final expense in expenses) {
      final companion = CachedExpensesCompanion.insert(
        id: expense.id,
        groupId: expense.groupId.isEmpty ? groupId : expense.groupId,
        createdBy: expense.createdBy,
        amount: expense.amount,
        date: expense.date,
        categoryId: expense.categoryId,
        categoryName: Value(expense.categoryName),
        paymentMethodId: Value(expense.paymentMethodId),
        paymentMethodName: Value(expense.paymentMethodName),
        merchant: Value(expense.merchant),
        notes: Value(expense.notes),
        isGroupExpense: Value(expense.isGroupExpense),
        paidBy: Value(expense.paidBy),
        paidByName: Value(expense.paidByName),
        createdByName: Value(expense.createdByName),
        reimbursementStatus: Value(expense.reimbursementStatus.value),
        reimbursedAt: Value(expense.reimbursedAt),
        lastModifiedBy: Value(expense.lastModifiedBy),
        reimbursableToLabel: Value(expense.reimbursableToLabel),
        reimbursableToUserId: Value(expense.reimbursableToUserId),
        reimbursableAmount: Value(expense.reimbursableAmount),
        reimbursementNote: Value(expense.reimbursementNote),
        reimbursementConfirmedBy: Value(expense.reimbursementConfirmedBy),
        receiptUrl: Value(expense.receiptUrl),
        createdAt: Value(expense.createdAt),
        updatedAt: Value(expense.updatedAt),
        cachedAt: now,
      );
      await _db.into(_db.cachedExpenses).insert(
            companion,
            mode: InsertMode.insertOrReplace,
          );
    }
  }

  @override
  Future<List<ExpenseModel>> getCachedExpenses(
    String groupId, {
    DateTime? startDate,
    DateTime? endDate,
    String? categoryId,
    String? createdBy,
    int? limit,
    int? offset,
  }) async {
    var query = _db.select(_db.cachedExpenses)
      ..where((tbl) => tbl.groupId.equals(groupId));

    if (startDate != null) {
      query = query..where((tbl) => tbl.date.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query = query..where((tbl) => tbl.date.isSmallerOrEqualValue(endDate));
    }
    if (categoryId != null) {
      query = query..where((tbl) => tbl.categoryId.equals(categoryId));
    }
    if (createdBy != null) {
      query = query..where((tbl) => tbl.createdBy.equals(createdBy));
    }

    query = query..orderBy([(tbl) => OrderingTerm.desc(tbl.date)]);

    if (offset != null && limit != null) {
      query = query..limit(limit, offset: offset);
    } else if (limit != null) {
      query = query..limit(limit);
    }

    final rows = await query.get();
    return rows.map(_rowToModel).toList();
  }

  @override
  Future<void> clearCache(String groupId) async {
    await (_db.delete(_db.cachedExpenses)
          ..where((tbl) => tbl.groupId.equals(groupId)))
        .go();
  }

  @override
  Future<void> clearAllCache() async {
    await _db.delete(_db.cachedExpenses).go();
  }

  ExpenseModel _rowToModel(CachedExpense row) {
    return ExpenseModel(
      id: row.id,
      groupId: row.groupId,
      createdBy: row.createdBy,
      amount: row.amount,
      date: row.date,
      categoryId: row.categoryId,
      categoryName: row.categoryName,
      paymentMethodId: row.paymentMethodId ?? '',
      paymentMethodName: row.paymentMethodName,
      merchant: row.merchant,
      notes: row.notes,
      isGroupExpense: row.isGroupExpense,
      paidBy: row.paidBy,
      paidByName: row.paidByName,
      createdByName: row.createdByName,
      reimbursementStatus: ReimbursementStatus.fromString(row.reimbursementStatus),
      reimbursedAt: row.reimbursedAt,
      lastModifiedBy: row.lastModifiedBy,
      reimbursableToLabel: row.reimbursableToLabel,
      reimbursableToUserId: row.reimbursableToUserId,
      reimbursableAmount: row.reimbursableAmount,
      reimbursementNote: row.reimbursementNote,
      reimbursementConfirmedBy: row.reimbursementConfirmedBy,
      receiptUrl: row.receiptUrl,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}
