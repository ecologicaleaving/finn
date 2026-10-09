import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/database/daos/recurring_expenses_dao.dart';
import '../../../offline/data/local/offline_database.dart';
import '../datasources/recurring_expense_remote_datasource.dart';
import '../models/recurring_expense_entity.dart';

/// Outcome of a template sync run.
class RecurringTemplateSyncResult {
  const RecurringTemplateSyncResult({
    this.pushed = 0,
    this.pulled = 0,
    this.inserted = 0,
    this.tableMissing = false,
  });

  /// Templates uploaded to the server.
  final int pushed;

  /// Local templates updated from the server.
  final int pulled;

  /// Templates present only on the server, inserted locally.
  final int inserted;

  /// The remote table does not exist yet (migration not applied): no-op.
  final bool tableMissing;
}

/// Syncs recurring templates between Drift and Supabase (issue #69).
///
/// State based, merge by id:
/// - local only -> uploaded with the same id;
/// - server only (own, not deleted) -> inserted locally;
/// - both -> local content wins when it has pending changes (queue entries of
///   type 'recurring_expense'), otherwise the server wins; nextDueDate and
///   lastInstanceCreatedAt always take the most recent value; a tombstone
///   (deleted_at) propagates to the other side as a soft delete.
///
/// It NEVER deletes a local row (templates, expenses or sync queue entries of
/// type 'expense'): only inserts and updates.
class RecurringTemplateSyncService {
  RecurringTemplateSyncService({
    required this.dao,
    required this.remote,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final RecurringExpensesDao dao;
  final RecurringTemplateSyncRemote remote;
  final DateTime Function() _clock;

  Future<RecurringTemplateSyncResult> sync(String userId) async {
    final syncStart = _clock();

    final List<Map<String, dynamic>> remoteRows;
    try {
      remoteRows = await remote.fetchOwnTemplatesForSync(userId);
    } on RemoteTableMissing {
      return const RecurringTemplateSyncResult(tableMissing: true);
    }

    final remoteById = {for (final r in remoteRows) r['id'] as String: r};
    final locals = await dao.getAllForSync(userId);
    final localById = {for (final l in locals) l.id: l};
    final queueItems = await dao.getTemplateQueueItems(userId);
    final queueIds = queueItems.map((q) => q.entityId).toSet();

    var pushed = 0;
    var pulled = 0;
    var inserted = 0;

    String? fallbackGroupId;
    var fallbackGroupLoaded = false;
    Future<String?> groupFallback() async {
      if (!fallbackGroupLoaded) {
        fallbackGroupLoaded = true;
        try {
          fallbackGroupId = await remote.fetchUserGroupId(userId);
        } catch (_) {
          fallbackGroupId = null;
        }
      }
      return fallbackGroupId;
    }

    // 1) Local templates (merge or upload).
    for (final local in locals) {
      try {
        final remoteRow = remoteById[local.id];
        final hasPending = queueIds.contains(local.id);

        if (remoteRow == null) {
          final row = _toRow(local, local.groupId ?? await groupFallback());
          await remote.upsertTemplateRow(row);
          pushed++;
          await dao.deleteTemplateQueueItems(local.id, syncStart);
          continue;
        }

        final remoteEntity = RecurringExpenseEntity.fromJson(remoteRow);
        final remoteDeletedAt = _parseDate(remoteRow['deleted_at']);
        final merged = _merge(
          local: local,
          remote: remoteEntity,
          remoteDeletedAt: remoteDeletedAt,
          localWins: hasPending,
        );

        if (merged != local) {
          await dao.upsertFromRemote(merged.toCompanion(false));
          pulled++;
        }

        final mergedRow = _toRow(merged, merged.groupId ?? await groupFallback());
        if (!_sameRemote(mergedRow, remoteRow)) {
          await remote.upsertTemplateRow(mergedRow);
          pushed++;
        }
        if (hasPending) {
          await dao.deleteTemplateQueueItems(local.id, syncStart);
        }
      } on RemoteTableMissing {
        return const RecurringTemplateSyncResult(tableMissing: true);
      } catch (e) {
        // One failing template must not stop the others; its queue entries
        // stay in place and it is retried at the next sync.
        debugPrint('RecurringTemplateSync: template ${local.id} failed: $e');
      }
    }

    // 2) Queue entries of templates without a local row (old hard deletes).
    final tombstoned = <String>{};
    final orphanIds = queueIds.difference(localById.keys.toSet());
    for (final id in orphanIds) {
      try {
        final remoteRow = remoteById[id];
        final hadDelete = queueItems
            .any((q) => q.entityId == id && q.operation == 'delete');
        if (remoteRow != null && hadDelete) {
          if (_parseDate(remoteRow['deleted_at']) == null) {
            final row = Map<String, dynamic>.from(remoteRow)
              ..['deleted_at'] = syncStart.toUtc().toIso8601String()
              ..['is_paused'] = true;
            row.remove('updated_at');
            await remote.upsertTemplateRow(row);
            pushed++;
          }
          tombstoned.add(id);
        }
        await dao.deleteTemplateQueueItems(id, syncStart);
      } on RemoteTableMissing {
        return const RecurringTemplateSyncResult(tableMissing: true);
      } catch (e) {
        debugPrint('RecurringTemplateSync: orphan $id failed: $e');
      }
    }

    // 3) Own, non-deleted templates present only on the server.
    for (final entry in remoteById.entries) {
      if (localById.containsKey(entry.key) || tombstoned.contains(entry.key)) {
        continue;
      }
      try {
        if (_parseDate(entry.value['deleted_at']) != null) continue;
        if (entry.value['user_id'] != userId) continue;
        final entity = RecurringExpenseEntity.fromJson(entry.value);
        await dao.upsertFromRemote(entity.toCompanion());
        inserted++;
      } catch (e) {
        debugPrint('RecurringTemplateSync: insert ${entry.key} failed: $e');
      }
    }

    return RecurringTemplateSyncResult(
      pushed: pushed,
      pulled: pulled,
      inserted: inserted,
    );
  }

  // ---------------------------------------------------------------------------

  RecurringExpenseData _merge({
    required RecurringExpenseData local,
    required RecurringExpenseEntity remote,
    required DateTime? remoteDeletedAt,
    required bool localWins,
  }) {
    final base = localWins
        ? local
        : local.copyWith(
            groupId: Value(remote.groupId ?? local.groupId),
            templateExpenseId: Value(remote.templateExpenseId),
            amount: remote.amount,
            categoryId: remote.categoryId,
            categoryName: remote.categoryName,
            merchant: Value(remote.merchant),
            notes: Value(remote.notes),
            isGroupExpense: remote.isGroupExpense,
            frequency: remote.frequency,
            anchorDate: remote.anchorDate,
            isPaused: remote.isPaused,
            budgetReservationEnabled: remote.budgetReservationEnabled,
            defaultReimbursementStatus: remote.defaultReimbursementStatus,
            paymentMethodId: Value(remote.paymentMethodId),
            paymentMethodName: Value(remote.paymentMethodName),
            updatedAt: remote.updatedAt,
          );

    final deletedAt = local.deletedAt ?? remoteDeletedAt;
    return base.copyWith(
      lastInstanceCreatedAt: Value(
        _later(local.lastInstanceCreatedAt, remote.lastInstanceCreatedAt),
      ),
      nextDueDate: Value(_later(local.nextDueDate, remote.nextDueDate)),
      groupId: Value(base.groupId ?? remote.groupId),
      deletedAt: Value(deletedAt),
      isPaused: deletedAt != null ? true : base.isPaused,
    );
  }

  static DateTime? _later(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return b.isAfter(a) ? b : a;
  }

  static DateTime? _parseDate(Object? v) =>
      v is String ? DateTime.parse(v) : null;

  Map<String, dynamic> _toRow(RecurringExpenseData d, String? groupId) {
    String? iso(DateTime? v) => v?.toUtc().toIso8601String();
    return {
      'id': d.id,
      'user_id': d.userId,
      'group_id': groupId,
      'template_expense_id': d.templateExpenseId,
      'amount': d.amount,
      'category_id': d.categoryId,
      'category_name': d.categoryName,
      'merchant': d.merchant,
      'notes': d.notes,
      'is_group_expense': d.isGroupExpense,
      'frequency': d.frequency.toStorageString(),
      'anchor_date': iso(d.anchorDate),
      'is_paused': d.isPaused,
      'last_instance_created_at': iso(d.lastInstanceCreatedAt),
      'next_due_date': iso(d.nextDueDate),
      'budget_reservation_enabled': d.budgetReservationEnabled,
      'default_reimbursement_status': d.defaultReimbursementStatus.value,
      'payment_method_id': d.paymentMethodId,
      'payment_method_name': d.paymentMethodName,
      'deleted_at': iso(d.deletedAt),
      'created_at': iso(d.createdAt),
    };
  }

  static const _comparedKeys = [
    'user_id',
    'group_id',
    'template_expense_id',
    'amount',
    'category_id',
    'category_name',
    'merchant',
    'notes',
    'is_group_expense',
    'frequency',
    'anchor_date',
    'is_paused',
    'last_instance_created_at',
    'next_due_date',
    'budget_reservation_enabled',
    'default_reimbursement_status',
    'payment_method_id',
    'payment_method_name',
    'deleted_at',
  ];

  static Object? _norm(String key, Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String && (key.endsWith('_date') || key.endsWith('_at'))) {
      return DateTime.parse(v).toUtc().millisecondsSinceEpoch ~/ 1000;
    }
    return v;
  }

  bool _sameRemote(Map<String, dynamic> a, Map<String, dynamic> b) {
    for (final k in _comparedKeys) {
      if (_norm(k, a[k]) != _norm(k, b[k])) return false;
    }
    return true;
  }
}
