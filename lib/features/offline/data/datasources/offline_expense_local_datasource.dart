import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../local/offline_database.dart';
import '../models/offline_expense_model.dart';
import '../models/sync_queue_item_model.dart';
import '../../domain/entities/offline_expense_entity.dart';

/// Local data source for offline expenses using Drift database
///
/// Responsibilities:
/// - CRUD operations on offline expenses
/// - Sync queue management
/// - User isolation (all queries filtered by user_id)
abstract class OfflineExpenseLocalDataSource {
  /// Create a new offline expense
  Future<OfflineExpenseEntity> createOfflineExpense({
    required String userId,
    required double amount,
    required DateTime date,
    required String categoryId,
    String? merchant,
    String? notes,
    bool isGroupExpense = true,
    String? reimbursableToLabel,
    String? reimbursableToUserId,
    double? reimbursableAmount,
    String? reimbursementNote,
  });

  /// Get all offline expenses for current user
  Future<List<OfflineExpenseEntity>> getAllOfflineExpenses(String userId);

  /// Get offline expenses by sync status
  Future<List<OfflineExpenseEntity>> getOfflineExpensesByStatus(
    String userId,
    String status,
  );

  /// Get pending expenses (pending + failed that can retry)
  Future<List<OfflineExpenseEntity>> getPendingExpenses(String userId);

  /// Update sync status of an expense
  Future<void> updateSyncStatus(
    String expenseId,
    String status, {
    String? errorMessage,
  });

  /// Delete offline expense after successful sync
  Future<void> deleteOfflineExpense(String expenseId);

  /// Add operation to sync queue
  Future<void> addToSyncQueue({
    required String userId,
    required String operation,
    required String entityType,
    required String entityId,
    required Map<String, dynamic> payload,
    int priority = 0,
  });

  /// Get pending sync queue items (max batch size)
  Future<List<SyncQueueItem>> getPendingSyncItems(
    String userId, {
    int limit = 10,
  });

  /// Update sync queue item status
  Future<void> updateSyncQueueItem(SyncQueueItemsCompanion companion);

  /// Delete completed sync queue items
  Future<void> deleteCompletedSyncItems(List<int> itemIds);

  /// Get count of pending sync items
  Future<int> getPendingSyncCount(String userId);
}

class OfflineExpenseLocalDataSourceImpl
    implements OfflineExpenseLocalDataSource {
  final OfflineDatabase _db;
  final Uuid _uuid;

  OfflineExpenseLocalDataSourceImpl({
    required OfflineDatabase database,
    Uuid? uuid,
  })  : _db = database,
        _uuid = uuid ?? const Uuid();

  @override
  Future<OfflineExpenseEntity> createOfflineExpense({
    required String userId,
    required double amount,
    required DateTime date,
    required String categoryId,
    String? merchant,
    String? notes,
    bool isGroupExpense = true,
    String? reimbursableToLabel,
    String? reimbursableToUserId,
    double? reimbursableAmount,
    String? reimbursementNote,
  }) async {
    final expenseId = _uuid.v4();
    final now = DateTime.now();

    // Create offline expense record
    final companion = OfflineExpensesCompanion.insert(
      id: expenseId,
      userId: userId,
      amount: amount,
      date: date,
      categoryId: categoryId,
      merchant: Value(merchant),
      notes: Value(notes),
      isGroupExpense: Value(isGroupExpense),
      syncStatus: 'pending',
      localCreatedAt: now,
      localUpdatedAt: now,
      reimbursableToLabel: Value(reimbursableToLabel),
      reimbursableToUserId: Value(reimbursableToUserId),
      reimbursableAmount: Value(reimbursableAmount),
      reimbursementNote: Value(reimbursementNote),
    );

    await _db.into(_db.offlineExpenses).insert(companion);

    // Add to sync queue
    final payload = {
      'id': expenseId,
      'amount': amount,
      'date': date.toIso8601String(),
      'category_id': categoryId,
      'merchant': merchant,
      'notes': notes,
      'is_group_expense': isGroupExpense,
      'created_at': now.toIso8601String(),
      if (reimbursableToLabel != null) 'reimbursable_to_label': reimbursableToLabel,
      if (reimbursableToUserId != null) 'reimbursable_to_user_id': reimbursableToUserId,
      if (reimbursableAmount != null) 'reimbursable_amount': reimbursableAmount,
      if (reimbursementNote != null) 'reimbursement_note': reimbursementNote,
    };

    await addToSyncQueue(
      userId: userId,
      operation: 'create',
      entityType: 'expense',
      entityId: expenseId,
      payload: payload,
    );

    // Return created entity
    final created = await (_db.select(_db.offlineExpenses)
          ..where((tbl) => tbl.id.equals(expenseId)))
        .getSingle();

    return OfflineExpenseModel(created).toEntity();
  }

  @override
  Future<List<OfflineExpenseEntity>> getAllOfflineExpenses(
    String userId,
  ) async {
    final expenses = await (_db.select(_db.offlineExpenses)
          ..where((tbl) => tbl.userId.equals(userId))
          ..orderBy([
            (tbl) => OrderingTerm.desc(tbl.localCreatedAt),
          ]))
        .get();

    return expenses.map((e) => OfflineExpenseModel(e).toEntity()).toList();
  }

  @override
  Future<List<OfflineExpenseEntity>> getOfflineExpensesByStatus(
    String userId,
    String status,
  ) async {
    final expenses = await (_db.select(_db.offlineExpenses)
          ..where((tbl) =>
              tbl.userId.equals(userId) & tbl.syncStatus.equals(status))
          ..orderBy([
            (tbl) => OrderingTerm.desc(tbl.localCreatedAt),
          ]))
        .get();

    return expenses.map((e) => OfflineExpenseModel(e).toEntity()).toList();
  }

  @override
  Future<List<OfflineExpenseEntity>> getPendingExpenses(String userId) async {
    final expenses = await (_db.select(_db.offlineExpenses)
          ..where((tbl) =>
              tbl.userId.equals(userId) &
              (tbl.syncStatus.equals('pending') |
                  tbl.syncStatus.equals('failed')))
          ..orderBy([
            (tbl) => OrderingTerm.asc(tbl.localCreatedAt),
          ]))
        .get();

    return expenses.map((e) => OfflineExpenseModel(e).toEntity()).toList();
  }

  @override
  Future<void> updateSyncStatus(
    String expenseId,
    String status, {
    String? errorMessage,
  }) async {
    await (_db.update(_db.offlineExpenses)
          ..where((tbl) => tbl.id.equals(expenseId)))
        .write(
      OfflineExpensesCompanion(
        syncStatus: Value(status),
        syncErrorMessage: Value(errorMessage),
        lastSyncAttemptAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> deleteOfflineExpense(String expenseId) async {
    // Get user ID first to ensure proper isolation
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    await (_db.delete(_db.offlineExpenses)
          ..where((tbl) => tbl.id.equals(expenseId) & tbl.userId.equals(userId)))
        .go();
  }

  @override
  Future<void> addToSyncQueue({
    required String userId,
    required String operation,
    required String entityType,
    required String entityId,
    required Map<String, dynamic> payload,
    int priority = 0,
  }) async {
    final companion = SyncQueueItemModel.create(
      userId: userId,
      operation: operation,
      entityType: entityType,
      entityId: entityId,
      payload: jsonEncode(payload),
      priority: priority,
    );

    await _db.into(_db.syncQueueItems).insert(companion);
  }

  @override
  Future<List<SyncQueueItem>> getPendingSyncItems(
    String userId, {
    int limit = 10,
  }) async {
    return await (_db.select(_db.syncQueueItems)
          ..where((tbl) =>
              tbl.userId.equals(userId) &
              (tbl.syncStatus.equals('pending') |
                  tbl.syncStatus.equals('failed')))
          ..orderBy([
            (tbl) => OrderingTerm.desc(tbl.priority),
            (tbl) => OrderingTerm.asc(tbl.createdAt),
          ])
          ..limit(limit))
        .get();
  }

  @override
  Future<void> updateSyncQueueItem(SyncQueueItemsCompanion companion) async {
    await (_db.update(_db.syncQueueItems)
          ..where((tbl) => tbl.id.equals(companion.id.value)))
        .write(companion);
  }

  @override
  Future<void> deleteCompletedSyncItems(List<int> itemIds) async {
    await (_db.delete(_db.syncQueueItems)
          ..where((tbl) => tbl.id.isIn(itemIds)))
        .go();
  }

  @override
  Future<int> getPendingSyncCount(String userId) async {
    final query = _db.selectOnly(_db.syncQueueItems)
      ..addColumns([_db.syncQueueItems.id.count()])
      ..where(_db.syncQueueItems.userId.equals(userId) &
          (_db.syncQueueItems.syncStatus.equals('pending') |
              _db.syncQueueItems.syncStatus.equals('failed')));

    final result = await query.getSingle();
    return result.read(_db.syncQueueItems.id.count()) ?? 0;
  }

  // ========================================================================
  // USER STORY 2: Edit Offline Expenses Before Sync
  // ========================================================================

  /// T069: Update offline expense
  Future<OfflineExpenseEntity> updateOfflineExpense({
    required String expenseId,
    required String userId,
    double? amount,
    DateTime? date,
    String? categoryId,
    String? merchant,
    String? notes,
    bool? isGroupExpense,
    String? reimbursableToLabel,
    String? reimbursableToUserId,
    double? reimbursableAmount,
    String? reimbursementNote,
  }) async {
    final now = DateTime.now();

    // Build update companion
    final companion = OfflineExpensesCompanion(
      amount: amount != null ? Value(amount) : const Value.absent(),
      date: date != null ? Value(date) : const Value.absent(),
      categoryId: categoryId != null ? Value(categoryId) : const Value.absent(),
      merchant: merchant != null ? Value(merchant) : const Value.absent(),
      notes: notes != null ? Value(notes) : const Value.absent(),
      isGroupExpense: isGroupExpense != null ? Value(isGroupExpense) : const Value.absent(),
      localUpdatedAt: Value(now),
      syncStatus: const Value('pending'), // Reset to pending
      reimbursableToLabel: reimbursableToLabel != null ? Value(reimbursableToLabel) : const Value.absent(),
      reimbursableToUserId: reimbursableToUserId != null ? Value(reimbursableToUserId) : const Value.absent(),
      reimbursableAmount: reimbursableAmount != null ? Value(reimbursableAmount) : const Value.absent(),
      reimbursementNote: reimbursementNote != null ? Value(reimbursementNote) : const Value.absent(),
    );

    // Update offline expense
    await (_db.update(_db.offlineExpenses)
          ..where((tbl) => tbl.id.equals(expenseId) & tbl.userId.equals(userId)))
        .write(companion);

    // Get updated expense
    final updated = await (_db.select(_db.offlineExpenses)
          ..where((tbl) => tbl.id.equals(expenseId)))
        .getSingle();

    // T071: Update sync queue to 'update' operation (replace previous queue items for same expense)
    await _updateSyncQueue(
      userId: userId,
      expenseId: expenseId,
      operation: 'update',
      payload: {
        'id': expenseId,
        'amount': updated.amount,
        'date': updated.date.toIso8601String(),
        'category_id': updated.categoryId,
        'merchant': updated.merchant,
        'notes': updated.notes,
        'is_group_expense': updated.isGroupExpense,
        'client_updated_at': now.toIso8601String(),
        if (updated.reimbursableToLabel != null) 'reimbursable_to_label': updated.reimbursableToLabel,
        if (updated.reimbursableToUserId != null) 'reimbursable_to_user_id': updated.reimbursableToUserId,
        if (updated.reimbursableAmount != null) 'reimbursable_amount': updated.reimbursableAmount,
        if (updated.reimbursementNote != null) 'reimbursement_note': updated.reimbursementNote,
      },
    );

    return OfflineExpenseModel(updated).toEntity();
  }

  /// T070: Delete offline expense (with user isolation)
  Future<void> deleteOfflineExpenseWithUserId({
    required String expenseId,
    required String userId,
  }) async {
    // Delete from offline expenses table
    await (_db.delete(_db.offlineExpenses)
          ..where((tbl) => tbl.id.equals(expenseId) & tbl.userId.equals(userId)))
        .go();

    // T071: Update sync queue to 'delete' operation (replace previous queue items)
    await _updateSyncQueue(
      userId: userId,
      expenseId: expenseId,
      operation: 'delete',
      payload: {
        'id': expenseId,
      },
    );
  }

  /// T071: Helper to update sync queue (ensures only final operation is queued)
  Future<void> _updateSyncQueue({
    required String userId,
    required String expenseId,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    // Delete all previous queue items for this expense
    await (_db.delete(_db.syncQueueItems)
          ..where((tbl) =>
              tbl.userId.equals(userId) &
              tbl.entityId.equals(expenseId) &
              tbl.entityType.equals('expense')))
        .go();

    // Add new queue item
    await addToSyncQueue(
      userId: userId,
      operation: operation,
      entityType: 'expense',
      entityId: expenseId,
      payload: payload,
    );
  }

  // ========================================================================
  // USER STORY 4: Conflict Resolution
  // ========================================================================

  /// T095: Record sync conflict for manual resolution
  Future<void> recordConflict({
    required String userId,
    required String expenseId,
    required String conflictType,
    required Map<String, dynamic> localVersion,
    required Map<String, dynamic> serverVersion,
    String? resolutionAction,
  }) async {
    final companion = SyncConflictsCompanion.insert(
      userId: userId,
      expenseId: expenseId,
      conflictType: conflictType,
      localVersionData: jsonEncode(localVersion),
      serverVersionData: jsonEncode(serverVersion),
      detectedAt: DateTime.now(),
      resolutionAction: Value(resolutionAction),
    );

    await _db.into(_db.syncConflicts).insert(companion);
  }

  /// T096: Get unresolved conflicts for user
  Future<List<SyncConflict>> getUnresolvedConflicts(String userId) async {
    return await (_db.select(_db.syncConflicts)
          ..where((tbl) => tbl.userId.equals(userId))
          ..orderBy([
            (tbl) => OrderingTerm.desc(tbl.detectedAt),
          ]))
        .get();
  }

  /// T097: Resolve conflict with chosen strategy
  Future<void> resolveConflict({
    required int conflictId,
    required String resolutionAction,
  }) async {
    final companion = SyncConflictsCompanion(
      id: Value(conflictId),
      resolvedAt: Value(DateTime.now()),
      resolutionAction: Value(resolutionAction),
    );

    await (_db.update(_db.syncConflicts)
          ..where((tbl) => tbl.id.equals(conflictId)))
        .write(companion);
  }

  /// T098: Get conflict by expense ID
  Future<SyncConflict?> getConflictByExpenseId(String expenseId) async {
    return await (_db.select(_db.syncConflicts)
          ..where((tbl) => tbl.expenseId.equals(expenseId))
          ..limit(1))
        .getSingleOrNull();
  }
}
