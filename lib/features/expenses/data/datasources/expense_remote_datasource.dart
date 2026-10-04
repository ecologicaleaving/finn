import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/enums/reimbursement_status.dart';
import '../../../../core/enums/transaction_type.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/utils/date_only.dart';
import '../../../../core/utils/receipt_file_type.dart';
import '../models/expense_model.dart';

/// Remote data source for expense operations using Supabase.
abstract class ExpenseRemoteDataSource {
  /// Get all expenses for the current user's group.
  Future<List<ExpenseModel>> getExpenses({
    DateTime? startDate,
    DateTime? endDate,
    String? categoryId,
    String? createdBy,
    String? paidBy,
    bool? isGroupExpense,
    ReimbursementStatus? reimbursementStatus, // T048
    int? limit,
    int? offset,
  });

  /// Get a single expense by ID.
  Future<ExpenseModel> getExpense({required String expenseId});

  /// Create a new expense.
  ///
  /// T014: For admin creating expenses on behalf of members:
  /// - createdBy: User ID of who created the expense (defaults to current user if null)
  /// - paidBy: User ID who paid for the expense (defaults to createdBy if null)
  /// - lastModifiedBy: User ID of who last modified (for audit trail when admin creates)
  Future<ExpenseModel> createExpense({
    required double amount,
    required DateTime date,
    required String categoryId,
    String? paymentMethodId, // Defaults to "Contanti" if null
    String? merchant,
    String? notes,
    bool isGroupExpense = true,
    ReimbursementStatus reimbursementStatus = ReimbursementStatus.none, // T048
    String? createdBy, // T014
    String? paidBy, // For admin creating expense for specific member
    String? lastModifiedBy, // T014
    TransactionType transactionType = TransactionType.expense,
  });

  /// Update an existing expense.
  Future<ExpenseModel> updateExpense({
    required String expenseId,
    double? amount,
    DateTime? date,
    String? categoryId,
    String? paymentMethodId,
    String? merchant,
    String? notes,
    ReimbursementStatus? reimbursementStatus, // T048
  });

  /// Update an existing expense with optimistic locking (Feature 001-admin-expenses-cash-fix).
  ///
  /// Uses the updated_at timestamp for optimistic locking to prevent concurrent edit conflicts.
  /// Throws ConflictException if the expense was modified by another user since [originalUpdatedAt].
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
    bool? isGroupExpense,
    String? paidBy,
  });

  /// Delete an expense.
  Future<void> deleteExpense({required String expenseId});

  /// Update expense classification (group or personal).
  Future<ExpenseModel> updateExpenseClassification({
    required String expenseId,
    required bool isGroupExpense,
  });

  /// Upload a receipt image.
  Future<String> uploadReceiptImage({
    required String expenseId,
    required Uint8List imageData,
  });

  /// Get signed URL for a receipt.
  Future<String> getReceiptUrl({required String receiptPath});

  /// Download the raw bytes of a receipt.
  Future<Uint8List> downloadReceipt({required String receiptPath});
}

/// Implementation of [ExpenseRemoteDataSource] using Supabase.
class ExpenseRemoteDataSourceImpl implements ExpenseRemoteDataSource {
  ExpenseRemoteDataSourceImpl({required this.supabaseClient});

  final SupabaseClient supabaseClient;

  /// Ordering of the expense list query: (column, ascending). Mirrors
  /// `compareExpensesNewestFirst` in the domain layer.
  @visibleForTesting
  static const List<(String, bool)> expenseListOrdering = [
    ('date', false),
    ('created_at', false),
    ('id', false),
  ];

  /// Builds the reimbursement columns for a write (issue #47).
  ///
  /// The DB constraint `check_reimbursed_at_consistency` requires
  /// `reimbursed_at` to be NOT NULL when status is `reimbursed` and NULL
  /// otherwise, so both columns must always be written together.
  static Map<String, dynamic> reimbursementFields(
    ReimbursementStatus status, {
    DateTime? now,
  }) {
    return <String, dynamic>{
      'reimbursement_status': status.value,
      'reimbursed_at': status == ReimbursementStatus.reimbursed
          ? (now ?? DateTime.now()).toUtc().toIso8601String()
          : null,
    };
  }

  /// Builds the update payload for the simple (non-lookup) expense fields.
  ///
  /// Payment method fields and `last_modified_by` are added by the callers.
  /// When [reimbursementStatus] is null neither `reimbursement_status` nor
  /// `reimbursed_at` is included, so the existing values stay untouched.
  static Map<String, dynamic> buildUpdatePayload({
    double? amount,
    DateTime? date,
    String? categoryId,
    String? merchant,
    String? notes,
    ReimbursementStatus? reimbursementStatus,
    DateTime? now,
  }) {
    final updates = <String, dynamic>{};
    if (amount != null) updates['amount'] = amount;
    if (date != null) updates['date'] = toServerDate(date);
    if (categoryId != null) updates['category_id'] = categoryId;
    if (merchant != null) updates['merchant'] = merchant;
    if (notes != null) updates['notes'] = notes;
    if (reimbursementStatus != null) {
      updates.addAll(reimbursementFields(reimbursementStatus, now: now));
    }
    return updates;
  }

  String get _currentUserId {
    final userId = supabaseClient.auth.currentUser?.id;
    if (userId == null) {
      throw const AppAuthException('Nessun utente autenticato', 'not_authenticated');
    }
    return userId;
  }

  Future<String?> get _currentUserGroupId async {
    final userId = _currentUserId;
    final response = await supabaseClient
        .from('profiles')
        .select('group_id')
        .eq('id', userId)
        .single();
    return response['group_id'] as String?;
  }

  @override
  Future<List<ExpenseModel>> getExpenses({
    DateTime? startDate,
    DateTime? endDate,
    String? categoryId,
    String? createdBy,
    String? paidBy,
    bool? isGroupExpense,
    ReimbursementStatus? reimbursementStatus, // T048
    int? limit,
    int? offset,
  }) async {
    try {
      final groupId = await _currentUserGroupId;
      if (groupId == null) {
        throw const GroupException('Non fai parte di nessun gruppo', 'not_in_group');
      }

      // Build the filter query with JOIN to get category name
      // Use * to select all existing fields (avoids errors if columns don't exist)
      var filterQuery = supabaseClient
          .from('expenses')
          .select('*, category_name:expense_categories(name)')
          .eq('group_id', groupId);

      if (startDate != null) {
        filterQuery = filterQuery.gte('date', startDate.toIso8601String().split('T')[0]);
      }
      if (endDate != null) {
        filterQuery = filterQuery.lte('date', endDate.toIso8601String().split('T')[0]);
      }
      if (categoryId != null) {
        filterQuery = filterQuery.eq('category_id', categoryId);
      }
      if (createdBy != null) {
        filterQuery = filterQuery.eq('created_by', createdBy);
      }
      if (paidBy != null) {
        filterQuery = filterQuery.eq('paid_by', paidBy);
      }
      if (isGroupExpense != null) {
        filterQuery = filterQuery.eq('is_group_expense', isGroupExpense);
      }
      if (reimbursementStatus != null) { // T048
        filterQuery = filterQuery.eq('reimbursement_status', reimbursementStatus.value);
      }

      // Apply ordering and pagination
      // The order is total (see compareExpensesNewestFirst), so range()
      // pagination is deterministic even with equal dates.
      var orderedQuery = filterQuery.order(
        ExpenseRemoteDataSourceImpl.expenseListOrdering.first.$1,
        ascending: ExpenseRemoteDataSourceImpl.expenseListOrdering.first.$2,
      );
      for (final (column, ascending)
          in ExpenseRemoteDataSourceImpl.expenseListOrdering.skip(1)) {
        orderedQuery = orderedQuery.order(column, ascending: ascending);
      }

      if (offset != null && limit != null) {
        orderedQuery = orderedQuery.range(offset, offset + limit - 1);
      } else if (limit != null) {
        orderedQuery = orderedQuery.limit(limit);
      }

      final response = await orderedQuery;
      return (response as List).map((json) {
        // Extract category_name from nested object if present
        if (json['category_name'] != null && json['category_name'] is Map) {
          json['category_name'] = json['category_name']['name'];
        }
        return ExpenseModel.fromJson(json);
      }).toList();
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      if (e is AppAuthException || e is GroupException) rethrow;
      throw ServerException(e.toString());
    }
  }

  @override
  Future<ExpenseModel> getExpense({required String expenseId}) async {
    try {
      final response = await supabaseClient
          .from('expenses')
          .select('*, category_name:expense_categories(name)')
          .eq('id', expenseId)
          .single();

      // Extract category_name from nested object if present
      if (response['category_name'] != null && response['category_name'] is Map) {
        response['category_name'] = response['category_name']['name'];
      }

      return ExpenseModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<ExpenseModel> createExpense({
    required double amount,
    required DateTime date,
    required String categoryId,
    String? paymentMethodId, // Defaults to "Contanti" if null
    String? merchant,
    String? notes,
    bool isGroupExpense = true,
    ReimbursementStatus reimbursementStatus = ReimbursementStatus.none, // T048
    String? createdBy, // T014
    String? paidBy, // For admin creating expense for specific member
    String? lastModifiedBy, // T014
    TransactionType transactionType = TransactionType.expense,
  }) async {
    try {
      final currentUserId = _currentUserId;
      final groupId = await _currentUserGroupId;

      if (groupId == null) {
        throw const GroupException('Non fai parte di nessun gruppo', 'not_in_group');
      }

      // T014: Use provided createdBy or default to current user
      final effectiveCreatedBy = createdBy ?? currentUserId;

      // Use paidBy if provided, otherwise use effectiveCreatedBy
      final effectivePaidBy = paidBy ?? effectiveCreatedBy;

      debugPrint('🔍 CREATE EXPENSE: effectiveCreatedBy=$effectiveCreatedBy, currentUserId=$currentUserId');

      // Get creator's display name
      debugPrint('🔍 CREATE EXPENSE: Fetching profile for user $effectiveCreatedBy');
      final creatorProfileResponse = await supabaseClient
          .from('profiles')
          .select('display_name')
          .eq('id', effectiveCreatedBy)
          .single();
      final creatorDisplayName = creatorProfileResponse['display_name'] as String?;
      debugPrint('🔍 CREATE EXPENSE: Creator profile found, displayName=$creatorDisplayName');

      // Get paid_by user's display name (may be different from creator)
      String? paidByDisplayName = creatorDisplayName;
      if (effectivePaidBy != effectiveCreatedBy) {
        debugPrint('🔍 CREATE EXPENSE: Fetching profile for paid_by user $effectivePaidBy');
        final paidByProfileResponse = await supabaseClient
            .from('profiles')
            .select('display_name')
            .eq('id', effectivePaidBy)
            .single();
        paidByDisplayName = paidByProfileResponse['display_name'] as String?;
        debugPrint('🔍 CREATE EXPENSE: PaidBy profile found, displayName=$paidByDisplayName');
      }

      // Get payment method ID if not provided (default to "Contanti")
      String finalPaymentMethodId = paymentMethodId ?? '';
      if (paymentMethodId == null) {
        final defaultPaymentMethod = await supabaseClient
            .from('payment_methods')
            .select('id')
            .eq('name', 'Contanti')
            .eq('is_default', true)
            .single();
        finalPaymentMethodId = defaultPaymentMethod['id'] as String;
      }

      // Get payment method name for denormalization
      final paymentMethodResponse = await supabaseClient
          .from('payment_methods')
          .select('name')
          .eq('id', finalPaymentMethodId)
          .single();
      final paymentMethodName = paymentMethodResponse['name'] as String;

      // DEBUG: Log the amount being saved
      debugPrint('🔍 SAVE EXPENSE: Saving to DB amount=$amount (type: ${amount.runtimeType})');
      debugPrint('🔍 SAVE EXPENSE: is_group_expense=$isGroupExpense, group_id=$groupId');

      final response = await supabaseClient
          .from('expenses')
          .insert({
            'group_id': groupId,
            'created_by': effectiveCreatedBy, // Who created/inserted the expense
            'created_by_name': creatorDisplayName ?? 'Utente',
            'paid_by': effectivePaidBy, // Who paid for the expense (may be different)
            'paid_by_name': paidByDisplayName ?? 'Utente',
            'amount': amount,
            'date': toServerDate(date),
            'category_id': categoryId,
            'payment_method_id': finalPaymentMethodId,
            'payment_method_name': paymentMethodName,
            'merchant': merchant,
            'notes': notes,
            'is_group_expense': isGroupExpense,
            ...reimbursementFields(reimbursementStatus), // T048, #47
            'last_modified_by': lastModifiedBy ?? effectiveCreatedBy, // T014: Set last_modified_by
            // Only include transaction_type for income (backward compatible: column may not exist yet)
            if (transactionType != TransactionType.expense)
              'transaction_type': transactionType.value,
          })
          .select('*, category_name:expense_categories(name)')
          .single();

      // DEBUG: Log the response from database
      debugPrint('🔍 SAVE EXPENSE: INSERT SUCCESS! Expense ID=${response['id']}');
      debugPrint('🔍 SAVE EXPENSE: Database returned amount=${response['amount']} (type: ${response['amount'].runtimeType})');

      // Extract category_name from nested object if present
      if (response['category_name'] != null && response['category_name'] is Map) {
        response['category_name'] = response['category_name']['name'];
      }

      final expenseModel = ExpenseModel.fromJson(response);
      debugPrint('🔍 SAVE EXPENSE: ExpenseModel.amount=${expenseModel.amount} (type: ${expenseModel.amount.runtimeType})');

      return expenseModel;
    } on PostgrestException catch (e) {
      debugPrint('❌ CREATE EXPENSE: PostgrestException - ${e.message} (code: ${e.code})');
      throw ServerException(e.message, e.code);
    } catch (e) {
      debugPrint('❌ CREATE EXPENSE: Exception - ${e.toString()}');
      if (e is AppAuthException || e is GroupException) rethrow;
      throw ServerException(e.toString());
    }
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
    ReimbursementStatus? reimbursementStatus, // T048
  }) async {
    try {
      final updates = buildUpdatePayload(
        amount: amount,
        date: date,
        categoryId: categoryId,
        merchant: merchant,
        notes: notes,
        reimbursementStatus: reimbursementStatus, // T048, #47
      );

      if (paymentMethodId != null) {
        // Get payment method name for denormalization
        final paymentMethodResponse = await supabaseClient
            .from('payment_methods')
            .select('name')
            .eq('id', paymentMethodId)
            .single();
        final paymentMethodName = paymentMethodResponse['name'] as String;
        updates['payment_method_id'] = paymentMethodId;
        updates['payment_method_name'] = paymentMethodName;
      }

      if (updates.isEmpty) {
        return await getExpense(expenseId: expenseId);
      }

      final response = await supabaseClient
          .from('expenses')
          .update(updates)
          .eq('id', expenseId)
          .select('*, category_name:expense_categories(name)')
          .single();

      // Extract category_name from nested object if present
      if (response['category_name'] != null && response['category_name'] is Map) {
        response['category_name'] = response['category_name']['name'];
      }

      return ExpenseModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  /// Builds the column map sent by [updateExpenseWithTimestamp].
  ///
  /// Only non-null fields are included; `last_modified_by` is always present.
  /// Kept pure so the payload can be unit-tested without Supabase.
  @visibleForTesting
  static Map<String, dynamic> buildTimestampUpdatePayload({
    required String lastModifiedBy,
    double? amount,
    DateTime? date,
    String? categoryId,
    String? paymentMethodId,
    String? paymentMethodName,
    String? merchant,
    String? notes,
    ReimbursementStatus? reimbursementStatus,
    bool? isGroupExpense,
    String? paidBy,
    String? paidByName,
    DateTime? now,
  }) {
    final updates = <String, dynamic>{
      // Add last_modified_by for audit trail
      'last_modified_by': lastModifiedBy,
    };

    if (amount != null) updates['amount'] = amount;
    if (date != null) updates['date'] = toServerDate(date);
    if (categoryId != null) updates['category_id'] = categoryId;
    if (paymentMethodId != null) {
      updates['payment_method_id'] = paymentMethodId;
      if (paymentMethodName != null) {
        updates['payment_method_name'] = paymentMethodName;
      }
    }
    if (merchant != null) updates['merchant'] = merchant;
    if (notes != null) updates['notes'] = notes;
    if (reimbursementStatus != null) {
      // #47: reimbursed_at must follow the status (check constraint)
      updates.addAll(reimbursementFields(reimbursementStatus, now: now));
    }
    if (isGroupExpense != null) updates['is_group_expense'] = isGroupExpense;
    if (paidBy != null) {
      updates['paid_by'] = paidBy;
      updates['paid_by_name'] = paidByName ?? 'Utente';
    }

    return updates;
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
    bool? isGroupExpense,
    String? paidBy,
  }) async {
    try {
      String? paymentMethodName;
      if (paymentMethodId != null) {
        // Get payment method name for denormalization
        final paymentMethodResponse = await supabaseClient
            .from('payment_methods')
            .select('name')
            .eq('id', paymentMethodId)
            .single();
        paymentMethodName = paymentMethodResponse['name'] as String;
      }

      String? paidByName;
      if (paidBy != null) {
        // Get paid_by user's display name for denormalization
        final paidByProfileResponse = await supabaseClient
            .from('profiles')
            .select('display_name')
            .eq('id', paidBy)
            .maybeSingle();
        paidByName = paidByProfileResponse?['display_name'] as String?;
      }

      final updates = buildTimestampUpdatePayload(
        lastModifiedBy: lastModifiedBy,
        amount: amount,
        date: date,
        categoryId: categoryId,
        paymentMethodId: paymentMethodId,
        paymentMethodName: paymentMethodName,
        merchant: merchant,
        notes: notes,
        reimbursementStatus: reimbursementStatus,
        isGroupExpense: isGroupExpense,
        paidBy: paidBy,
        paidByName: paidByName,
      );

      // Optimistic locking: only update if updated_at matches the original timestamp
      final response = await supabaseClient
          .from('expenses')
          .update(updates)
          .eq('id', expenseId)
          .eq('updated_at', originalUpdatedAt.toIso8601String())
          .select('*, category_name:expense_categories(name)');

      // Check if update affected any rows (empty list means conflict)
      if (response.isEmpty) {
        throw ConflictException.expenseModified;
      }

      final responseData = response.first;

      // Extract category_name from nested object if present
      if (responseData['category_name'] != null && responseData['category_name'] is Map) {
        responseData['category_name'] = responseData['category_name']['name'];
      }

      return ExpenseModel.fromJson(responseData);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      if (e is ConflictException) rethrow;
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> deleteExpense({required String expenseId}) async {
    try {
      await supabaseClient
          .from('expenses')
          .delete()
          .eq('id', expenseId);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<ExpenseModel> updateExpenseClassification({
    required String expenseId,
    required bool isGroupExpense,
  }) async {
    try {
      final response = await supabaseClient
          .from('expenses')
          .update({'is_group_expense': isGroupExpense})
          .eq('id', expenseId)
          .select('*, category_name:expense_categories(name)')
          .single();

      // Extract category_name from nested object if present
      if (response['category_name'] != null && response['category_name'] is Map) {
        response['category_name'] = response['category_name']['name'];
      }

      return ExpenseModel.fromJson(response);
    } on PostgrestException catch (e) {
      // RLS will prevent unauthorized updates
      if (e.code == '42501' || e.code == 'PGRST301') {
        throw const PermissionException(
          'You can only change classification of your own expenses',
        );
      }
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<String> uploadReceiptImage({
    required String expenseId,
    required Uint8List imageData,
  }) async {
    try {
      final userId = _currentUserId;
      final type = ReceiptFileType.detect(imageData);
      final path = ReceiptFileType.storagePath(userId, expenseId, imageData);

      await supabaseClient.storage
          .from('receipts')
          .uploadBinary(
            path,
            imageData,
            fileOptions: FileOptions(
              contentType: type.contentType,
              upsert: true,
            ),
          );

      // Update expense with receipt path
      await supabaseClient
          .from('expenses')
          .update({'receipt_url': path})
          .eq('id', expenseId);

      return path;
    } on StorageException catch (e) {
      throw ServerException(e.message, e.statusCode);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<String> getReceiptUrl({required String receiptPath}) async {
    try {
      final signedUrl = await supabaseClient.storage
          .from('receipts')
          .createSignedUrl(receiptPath, 3600); // 1 hour expiry

      return signedUrl;
    } on StorageException catch (e) {
      throw ServerException(e.message, e.statusCode);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<Uint8List> downloadReceipt({required String receiptPath}) async {
    try {
      return await supabaseClient.storage.from('receipts').download(receiptPath);
    } on StorageException catch (e) {
      throw ServerException(e.message, e.statusCode);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }
}
