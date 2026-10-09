import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../../features/expenses/domain/services/recurrence_calculator.dart';
import '../../features/offline/data/local/offline_database.dart';

/// Generates the expense instances of recurring templates, locally.
///
/// Issue #69. Pure local logic (no network), usable both from the
/// foreground app and from the background isolate:
/// - every due occurrence (date <= today, template not paused/deleted)
///   becomes ONE row in `offline_expenses` plus ONE 'create'/'expense'
///   entry in `sync_queue_items`, in a single transaction;
/// - the instance id is deterministic (uuid v5 of `templateId|yyyy-MM-dd`),
///   so repeated or concurrent runs can never create duplicates, neither
///   locally nor on the server (a 23505 is treated as already synced);
/// - nothing is ever deleted: no expense, no queue entry.
class RecurringInstanceGenerator {
  RecurringInstanceGenerator._();

  /// Constant namespace for the deterministic instance ids. Never change it:
  /// it would make already generated instances regenerate.
  static const String instanceNamespace = '6f1d5c0e-69a1-4b7e-9d3a-2f4c8e1b7a55';

  /// SharedPreferences flag: first activation already done (decision D1).
  static const String activationFlagKey = 'recurring_activation_v1';

  /// Deterministic id of the instance of [templateId] scheduled on [dayKey]
  /// (yyyy-MM-dd).
  static String instanceId(String templateId, String dayKey) {
    return const Uuid().v5(instanceNamespace, '$templateId|$dayKey');
  }

  /// Day key (yyyy-MM-dd) of [d] in the app's local timezone.
  static String dayKeyOf(DateTime d) {
    final t = tz.TZDateTime.from(d, tz.local);
    String pad(int v, int w) => v.toString().padLeft(w, '0');
    return '${pad(t.year, 4)}-${pad(t.month, 2)}-${pad(t.day, 2)}';
  }

  /// Generates every due instance. Returns the number of instances created.
  ///
  /// [prefs] is used for the one-time activation flag; when null it is
  /// obtained from SharedPreferences (errors there skip the activation step
  /// but never the generation).
  static Future<int> generate(
    OfflineDatabase db,
    DateTime now, {
    int maxPerTemplate = 31,
    SharedPreferences? prefs,
  }) async {
    final nowTz = tz.TZDateTime.from(now, tz.local);
    final startOfToday = tz.TZDateTime(tz.local, nowTz.year, nowTz.month, nowTz.day);
    final endOfToday = tz.TZDateTime(tz.local, nowTz.year, nowTz.month, nowTz.day + 1)
        .subtract(const Duration(microseconds: 1));

    await _activateOnce(db, now, startOfToday, prefs);

    final templates = await (db.select(db.recurringExpenses)
          ..where((t) =>
              t.isPaused.equals(false) &
              t.deletedAt.isNull() &
              t.nextDueDate.isNotNull()))
        .get();

    var created = 0;
    for (final template in templates) {
      try {
        created += await _generateForTemplate(
          db,
          template,
          now,
          endOfToday,
          maxPerTemplate,
        );
      } catch (_) {
        // One template failing must not stop the others; it is retried on
        // the next run (the deterministic ids make the retry safe).
        continue;
      }
    }
    return created;
  }

  static Future<int> _generateForTemplate(
    OfflineDatabase db,
    RecurringExpenseData template,
    DateTime now,
    tz.TZDateTime endOfToday,
    int maxPerTemplate,
  ) async {
    var occurrence = template.nextDueDate;
    var created = 0;
    var count = 0;

    while (occurrence != null &&
        !occurrence.isAfter(endOfToday) &&
        count < maxPerTemplate) {
      count++;
      final next = RecurrenceCalculator.calculateNextDueDate(
        anchorDate: template.anchorDate,
        frequency: template.frequency,
        lastCreated: occurrence,
      );
      // Safety: the schedule must always move forward.
      if (next == null || !next.isAfter(occurrence)) break;

      final scheduled = occurrence;
      final inserted = await db.transaction(() async {
        return _createInstance(db, template, scheduled, next, now);
      });
      if (inserted) created++;
      occurrence = next;
    }
    return created;
  }

  /// Creates one instance (row + queue entry + mapping) and advances the
  /// template, all inside the caller's transaction. Returns whether a new
  /// expense row was created.
  static Future<bool> _createInstance(
    OfflineDatabase db,
    RecurringExpenseData template,
    DateTime scheduled,
    DateTime next,
    DateTime now,
  ) async {
    final dayKey = dayKeyOf(scheduled);
    final id = instanceId(template.id, dayKey);
    final day = DateTime.parse(dayKey); // local midnight of the scheduled day

    final existing = await (db.select(db.offlineExpenses)
          ..where((e) => e.id.equals(id)))
        .getSingleOrNull();

    var inserted = false;
    if (existing == null) {
      await db.into(db.offlineExpenses).insert(
            OfflineExpensesCompanion.insert(
              id: id,
              userId: template.userId,
              amount: template.amount,
              date: day,
              categoryId: template.categoryId,
              merchant: Value(template.merchant),
              notes: Value(template.notes),
              isGroupExpense: Value(template.isGroupExpense),
              reimbursementStatus: Value(template.defaultReimbursementStatus.value),
              recurringExpenseId: Value(template.id),
              isRecurringInstance: const Value(true),
              syncStatus: 'pending',
              localCreatedAt: now,
              localUpdatedAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      inserted = true;

      final queued = await (db.select(db.syncQueueItems)
            ..where((q) =>
                q.entityType.equals('expense') &
                q.entityId.equals(id) &
                q.operation.equals('create'))
            ..limit(1))
          .getSingleOrNull();
      if (queued == null) {
        await db.into(db.syncQueueItems).insert(
              SyncQueueItemsCompanion.insert(
                userId: template.userId,
                operation: 'create',
                entityType: 'expense',
                entityId: id,
                payload: jsonEncode({
                  'id': id,
                  'amount': template.amount,
                  'date': dayKey,
                  'category_id': template.categoryId,
                  'merchant': template.merchant,
                  'notes': template.notes,
                  'is_group_expense': template.isGroupExpense,
                  'reimbursement_status': template.defaultReimbursementStatus.value,
                  'payment_method_id': template.paymentMethodId,
                  'created_by': template.userId,
                  'created_at': now.toIso8601String(),
                  'recurring_expense_id': template.id,
                  'is_recurring_instance': true,
                }),
                syncStatus: 'pending',
                createdAt: now,
              ),
            );
      }
    }

    final mapped = await (db.select(db.recurringExpenseInstances)
          ..where((m) => m.expenseId.equals(id))
          ..limit(1))
        .getSingleOrNull();
    if (mapped == null) {
      await db.into(db.recurringExpenseInstances).insert(
            RecurringExpenseInstancesCompanion.insert(
              recurringExpenseId: template.id,
              expenseId: id,
              scheduledDate: scheduled,
              createdAt: now,
            ),
          );
    }

    await _advanceTemplate(
      db,
      template,
      lastInstanceCreatedAt: scheduled,
      nextDueDate: next,
      now: now,
    );
    return inserted;
  }

  /// Moves the schedule of [template] forward and queues an 'update' so the
  /// advancement reaches the server.
  static Future<void> _advanceTemplate(
    OfflineDatabase db,
    RecurringExpenseData template, {
    DateTime? lastInstanceCreatedAt,
    required DateTime nextDueDate,
    required DateTime now,
  }) async {
    await (db.update(db.recurringExpenses)
          ..where((t) => t.id.equals(template.id)))
        .write(
      RecurringExpensesCompanion(
        lastInstanceCreatedAt: lastInstanceCreatedAt != null
            ? Value(lastInstanceCreatedAt)
            : const Value.absent(),
        nextDueDate: Value(nextDueDate),
        updatedAt: Value(now),
      ),
    );
    await db.into(db.syncQueueItems).insert(
          SyncQueueItemsCompanion.insert(
            userId: template.userId,
            operation: 'update',
            entityType: 'recurring_expense',
            entityId: template.id,
            payload: jsonEncode({'id': template.id}),
            syncStatus: 'pending',
            createdAt: now,
          ),
        );
  }

  /// First activation (decision D1): templates already existing do NOT
  /// recover the past, so they never duplicate expenses that were entered by
  /// hand while the feature was not working. Their nextDueDate moves to the
  /// first occurrence from today on, without generating anything.
  static Future<void> _activateOnce(
    OfflineDatabase db,
    DateTime now,
    tz.TZDateTime startOfToday,
    SharedPreferences? prefs,
  ) async {
    SharedPreferences? p = prefs;
    try {
      p ??= await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    if (p.getBool(activationFlagKey) == true) return;

    final templates = await (db.select(db.recurringExpenses)
          ..where((t) =>
              t.isPaused.equals(false) &
              t.deletedAt.isNull() &
              t.nextDueDate.isNotNull()))
        .get();

    for (final template in templates) {
      final due = template.nextDueDate;
      if (due == null || !due.isBefore(startOfToday)) continue;

      DateTime? cursor = due;
      var guard = 0;
      while (cursor != null && cursor.isBefore(startOfToday) && guard < 20000) {
        guard++;
        final next = RecurrenceCalculator.calculateNextDueDate(
          anchorDate: template.anchorDate,
          frequency: template.frequency,
          lastCreated: cursor,
        );
        if (next == null || !next.isAfter(cursor)) {
          cursor = null;
          break;
        }
        cursor = next;
      }
      if (cursor == null) continue;
      final target = cursor;
      await db.transaction(() async {
        await _advanceTemplate(db, template, nextDueDate: target, now: now);
      });
    }
    await p.setBool(activationFlagKey, true);
  }
}
