import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/date_only.dart';
import '../../../../core/utils/receipt_file_type.dart';
import '../../data/local/offline_database.dart';

/// The receipt file saved offline no longer exists on the device.
class ReceiptFileMissing implements Exception {
  ReceiptFileMissing(this.path);
  final String path;

  @override
  String toString() => 'ReceiptFileMissing($path)';
}

/// The server rejected the receipt and will always do so (retry is useless).
class ReceiptUploadPermanentError implements Exception {
  ReceiptUploadPermanentError(this.message, this.statusCode);
  final String message;
  final int statusCode;

  @override
  String toString() => 'ReceiptUploadPermanentError($statusCode): $message';
}

/// Result of syncing a single item
class SyncItemResult {
  final String id;
  final bool success;
  final String? errorMessage;
  final String? errorCode;
  final Map<String, dynamic>? serverVersion; // For conflicts
  final DateTime? serverUpdatedAt;

  SyncItemResult({
    required this.id,
    required this.success,
    this.errorMessage,
    this.errorCode,
    this.serverVersion,
    this.serverUpdatedAt,
  });

  factory SyncItemResult.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as String;

    return SyncItemResult(
      id: json['id'] as String,
      success: status == 'success',
      errorMessage: json['error_message'] as String?,
      errorCode: json['error_code'] as String?,
      serverVersion: status == 'conflict'
          ? json['server_version'] as Map<String, dynamic>?
          : null,
      serverUpdatedAt: json['server_updated_at'] != null
          ? DateTime.parse(json['server_updated_at'] as String)
          : null,
    );
  }

  bool get isConflict => errorCode == null && serverVersion != null;
}

/// Result of syncing a batch of items
class BatchSyncResult {
  final Map<String, SyncItemResult> results;

  BatchSyncResult(this.results);

  int get successCount => results.values.where((r) => r.success).length;
  int get failureCount => results.values.where((r) => !r.success).length;
  int get conflictCount => results.values.where((r) => r.isConflict).length;

  bool get hasConflicts => conflictCount > 0;
  bool get allSuccess => failureCount == 0 && conflictCount == 0;
}

/// Service for batch sync operations with Supabase
///
/// Handles:
/// - Batch create expenses (direct inserts)
/// - Batch update expenses (with conflict detection)
/// - Batch delete expenses
class BatchSyncService {
  final SupabaseClient _supabase;

  BatchSyncService({required SupabaseClient supabase}) : _supabase = supabase;

  /// Create queued offline expenses on the server.
  ///
  /// Each expense is inserted with the same columns used by the online
  /// create path (created_by, *_name, payment method, ...). The
  /// `batch_create_expenses` RPC (migration 044) still writes the pre-007
  /// `user_id` column and omits NOT NULL columns such as `payment_method_id`,
  /// so every expense saved offline was rejected by the server and stayed
  /// only on the device.
  ///
  /// The offline UUID is kept as the server id, so a retry after a lost
  /// response hits a duplicate key and is treated as already synced.
  Future<Map<String, SyncItemResult>> batchCreateExpenses(
    List<SyncQueueItem> items,
  ) async {
    if (items.isEmpty) return {};

    final results = <String, SyncItemResult>{};

    final _CreateContext context;
    try {
      context = await _loadCreateContext();
    } catch (e) {
      for (final item in items) {
        results[item.entityId] = _failure(item.entityId, e);
      }
      return results;
    }

    for (final item in items) {
      results[item.entityId] = await _createExpense(item, context);
    }

    return results;
  }

  /// Uploads the receipt saved on the device for an expense that has already
  /// been created on the server, and links it (`receipts` bucket +
  /// `expenses.receipt_url`). Returns the storage path.
  ///
  /// Throws [ReceiptFileMissing] if the local file is gone,
  /// [ReceiptUploadPermanentError] if the server will never accept it (e.g.
  /// file too large, type rejected), any other error for transient failures
  /// (the caller retries on the next sync). Safe to retry: upsert.
  Future<String> uploadPendingReceipt({
    required String expenseId,
    required String localPath,
  }) async {
    final file = File(localPath);
    final Uint8List bytes;
    try {
      if (!await file.exists()) throw ReceiptFileMissing(localPath);
      bytes = await file.readAsBytes();
    } on ReceiptFileMissing {
      rethrow;
    } on FileSystemException {
      throw ReceiptFileMissing(localPath);
    }
    if (bytes.isEmpty) throw ReceiptFileMissing(localPath);

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('User not authenticated');
    }

    final type = ReceiptFileType.detect(bytes);
    final path = ReceiptFileType.storagePath(userId, expenseId, bytes);

    try {
      await _supabase.storage.from('receipts').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: type.contentType,
              upsert: true,
            ),
          );
    } on StorageException catch (e) {
      final status = int.tryParse(e.statusCode ?? '');
      const transient = {401, 403, 408, 429};
      if (status != null &&
          status >= 400 &&
          status < 500 &&
          !transient.contains(status)) {
        throw ReceiptUploadPermanentError(e.message, status);
      }
      rethrow;
    }

    await _supabase
        .from('expenses')
        .update({'receipt_url': path}).eq('id', expenseId);

    return path;
  }

  Future<_CreateContext> _loadCreateContext() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('User not authenticated');
    }

    final profile = await _supabase
        .from('profiles')
        .select('group_id')
        .eq('id', userId)
        .single();
    final groupId = profile['group_id'] as String?;
    if (groupId == null) {
      throw StateError('User not in a group');
    }

    return _CreateContext(userId: userId, groupId: groupId);
  }

  /// Builds the insert row for a queued expense (pure, testable).
  @visibleForTesting
  static Map<String, dynamic> buildCreateRow(
    Map<String, dynamic> payload, {
    required String id,
    required String groupId,
    required String createdBy,
    required String createdByName,
    required String paidBy,
    required String paidByName,
    required String? paymentMethodId,
    required String? paymentMethodName,
  }) {
    final transactionType = payload['transaction_type'] as String?;
    final createdAt = payload['created_at'] as String?;
    return {
      'id': id,
      'group_id': groupId,
      'created_by': createdBy,
      'created_by_name': createdByName,
      'paid_by': paidBy,
      'paid_by_name': paidByName,
      'amount': payload['amount'],
      // Date only, as entered on the device (no timezone shift)
      'date': serverDateFromPayload(payload['date'] as String),
      'category_id': payload['category_id'],
      'payment_method_id': paymentMethodId,
      'payment_method_name': paymentMethodName,
      'merchant': payload['merchant'],
      'notes': payload['notes'],
      'is_group_expense': payload['is_group_expense'] as bool? ?? true,
      'reimbursement_status':
          payload['reimbursement_status'] as String? ?? 'none',
      'last_modified_by': payload['last_modified_by'] as String? ?? createdBy,
      if (createdAt != null)
        'created_at': DateTime.parse(createdAt).toUtc().toIso8601String(),
      // Same as the online path: only sent for income
      if (transactionType != null && transactionType != 'expense')
        'transaction_type': transactionType,
      // Recurring instances (issue #69): only when present in the payload
      if (payload['recurring_expense_id'] != null)
        'recurring_expense_id': payload['recurring_expense_id'],
      if (payload['is_recurring_instance'] != null)
        'is_recurring_instance': payload['is_recurring_instance'],
    };
  }

  /// Columns added by migration 20261009_69 on `expenses`.
  static const recurringColumns = [
    'recurring_expense_id',
    'is_recurring_instance',
  ];

  /// Whether [e] is a PGRST204 ("column not found in the schema cache") that
  /// names one of the recurring columns: the migration is not applied yet.
  @visibleForTesting
  static bool isMissingRecurringColumn(PostgrestException e) {
    if (e.code != 'PGRST204') return false;
    final text = '${e.message} ${e.details ?? ''}';
    return recurringColumns.any(text.contains);
  }

  /// Copy of [row] without the recurring columns.
  @visibleForTesting
  static Map<String, dynamic> withoutRecurringColumns(
      Map<String, dynamic> row) {
    return Map<String, dynamic>.from(row)
      ..removeWhere((k, _) => recurringColumns.contains(k));
  }

  /// Copy of the update payload with 'date' normalized to yyyy-MM-dd.
  static Map<String, dynamic> _normalizeUpdateFields(dynamic payload) {
    final fields = Map<String, dynamic>.from(payload as Map);
    final d = fields['date'];
    if (d is String) fields['date'] = serverDateFromPayload(d);
    return fields;
  }

  Future<SyncItemResult> _createExpense(
    SyncQueueItem item,
    _CreateContext context,
  ) async {
    try {
      final payload = jsonDecode(item.payload) as Map<String, dynamic>;
      final id = payload['id'] as String? ?? item.entityId;
      final createdBy = payload['created_by'] as String? ?? context.userId;
      final paidBy = payload['paid_by'] as String? ?? createdBy;
      final paymentMethodId = payload['payment_method_id'] as String? ??
          await _defaultPaymentMethodId(context);

      final row = buildCreateRow(
        payload,
        id: id,
        groupId: context.groupId,
        createdBy: createdBy,
        createdByName: await _displayName(createdBy, context),
        paidBy: paidBy,
        paidByName: await _displayName(paidBy, context),
        paymentMethodId: paymentMethodId,
        paymentMethodName: await _paymentMethodName(paymentMethodId, context),
      );

      Map<String, dynamic> response;
      try {
        response = await _supabase
            .from('expenses')
            .insert(row)
            .select('id, updated_at')
            .single();
      } on PostgrestException catch (e) {
        // Migration 20261009_69 not applied yet: retry once without the
        // recurring columns, so the instance is synced anyway.
        if (!isMissingRecurringColumn(e)) rethrow;
        response = await _supabase
            .from('expenses')
            .insert(withoutRecurringColumns(row))
            .select('id, updated_at')
            .single();
      }

      return SyncItemResult(
        id: item.entityId,
        success: true,
        serverUpdatedAt: response['updated_at'] != null
            ? DateTime.parse(response['updated_at'] as String)
            : null,
      );
    } on PostgrestException catch (e) {
      // unique_violation: uploaded by an earlier attempt whose response was lost
      if (e.code == '23505') {
        return SyncItemResult(id: item.entityId, success: true);
      }
      return SyncItemResult(
        id: item.entityId,
        success: false,
        errorMessage: e.message,
        errorCode: e.code,
      );
    } catch (e) {
      return _failure(item.entityId, e);
    }
  }

  Future<String?> _defaultPaymentMethodId(_CreateContext context) async {
    if (context.defaultPaymentMethodLoaded) {
      return context.defaultPaymentMethodId;
    }
    final row = await _supabase
        .from('payment_methods')
        .select('id')
        .eq('name', 'Contanti')
        .eq('is_default', true)
        .limit(1)
        .maybeSingle();
    context.defaultPaymentMethodId = row?['id'] as String?;
    context.defaultPaymentMethodLoaded = true;
    return context.defaultPaymentMethodId;
  }

  Future<String?> _paymentMethodName(
    String? paymentMethodId,
    _CreateContext context,
  ) async {
    if (paymentMethodId == null) return null;
    if (context.paymentMethodNames.containsKey(paymentMethodId)) {
      return context.paymentMethodNames[paymentMethodId];
    }
    final row = await _supabase
        .from('payment_methods')
        .select('name')
        .eq('id', paymentMethodId)
        .maybeSingle();
    final name = row?['name'] as String?;
    context.paymentMethodNames[paymentMethodId] = name;
    return name;
  }

  Future<String> _displayName(String userId, _CreateContext context) async {
    final cached = context.displayNames[userId];
    if (cached != null) return cached;
    final row = await _supabase
        .from('profiles')
        .select('display_name')
        .eq('id', userId)
        .maybeSingle();
    final name = row?['display_name'] as String? ?? 'Utente';
    context.displayNames[userId] = name;
    return name;
  }

  SyncItemResult _failure(String id, Object error) {
    return SyncItemResult(
      id: id,
      success: false,
      errorMessage: 'Network error: ${error.toString()}',
    );
  }

  /// Batch update expenses via RPC (with conflict detection)
  Future<Map<String, SyncItemResult>> batchUpdateExpenses(
    List<SyncQueueItem> items,
  ) async {
    if (items.isEmpty) return {};

    try {
      // Build update payloads
      final updates = items.map((item) {
        final payload = jsonDecode(item.payload);
        return {
          'id': item.entityId,
          'client_updated_at': payload['local_updated_at'],
          'fields': _normalizeUpdateFields(payload),
        };
      }).toList();

      // Call Supabase RPC
      final response = await _supabase.rpc(
        'batch_update_expenses',
        params: {'p_updates': updates},
      ) as List;

      // Convert to results map
      final results = <String, SyncItemResult>{};
      for (final result in response) {
        final syncResult = SyncItemResult.fromJson(
          Map<String, dynamic>.from(result as Map),
        );
        results[syncResult.id] = syncResult;
      }

      return results;
    } on PostgrestException catch (e) {
      final results = <String, SyncItemResult>{};
      for (final item in items) {
        results[item.entityId] = SyncItemResult(
          id: item.entityId,
          success: false,
          errorMessage: e.message,
          errorCode: e.code,
        );
      }
      return results;
    } catch (e) {
      final results = <String, SyncItemResult>{};
      for (final item in items) {
        results[item.entityId] = SyncItemResult(
          id: item.entityId,
          success: false,
          errorMessage: 'Network error: ${e.toString()}',
        );
      }
      return results;
    }
  }

  /// Batch delete expenses via RPC
  Future<Map<String, SyncItemResult>> batchDeleteExpenses(
    List<SyncQueueItem> items,
  ) async {
    if (items.isEmpty) return {};

    try {
      // Extract expense IDs
      final expenseIds = items.map((item) => item.entityId).toList();

      // Call Supabase RPC
      final response = await _supabase.rpc(
        'batch_delete_expenses',
        params: {'p_expense_ids': expenseIds},
      ) as List;

      // Convert to results map
      final results = <String, SyncItemResult>{};
      for (final result in response) {
        final syncResult = SyncItemResult.fromJson(
          Map<String, dynamic>.from(result as Map),
        );
        results[syncResult.id] = syncResult;
      }

      return results;
    } on PostgrestException catch (e) {
      final results = <String, SyncItemResult>{};
      for (final item in items) {
        results[item.entityId] = SyncItemResult(
          id: item.entityId,
          success: false,
          errorMessage: e.message,
          errorCode: e.code,
        );
      }
      return results;
    } catch (e) {
      final results = <String, SyncItemResult>{};
      for (final item in items) {
        results[item.entityId] = SyncItemResult(
          id: item.entityId,
          success: false,
          errorMessage: 'Network error: ${e.toString()}',
        );
      }
      return results;
    }
  }

  /// Get expenses by IDs (for conflict resolution)
  Future<List<Map<String, dynamic>>> getExpensesByIds(
    List<String> expenseIds,
  ) async {
    if (expenseIds.isEmpty) return [];

    try {
      final response = await _supabase.rpc(
        'get_expenses_by_ids',
        params: {'p_expense_ids': expenseIds},
      ) as List;

      return response.cast<Map<String, dynamic>>();
    } catch (e) {
      // Return empty list on error
      return [];
    }
  }
}

/// Per-run lookups shared by the expenses of one create batch.
class _CreateContext {
  _CreateContext({required this.userId, required this.groupId});

  final String userId;
  final String groupId;
  final Map<String, String> displayNames = {};
  final Map<String, String?> paymentMethodNames = {};
  String? defaultPaymentMethodId;
  bool defaultPaymentMethodLoaded = false;
}
