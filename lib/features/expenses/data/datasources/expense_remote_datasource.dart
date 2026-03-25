import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/enums/reimbursement_status.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../offline/data/datasources/expense_cache_datasource.dart';
import '../../../offline/data/datasources/offline_expense_local_datasource.dart';
import '../../../offline/domain/entities/offline_expense_entity.dart';
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
    String? reimbursableToLabel, // Issue #19
    String? reimbursableToUserId, // Issue #19
    double? reimbursableAmount, // Issue #19
    String? reimbursementNote, // Issue #19
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
    String? reimbursableToLabel, // Issue #19
    String? reimbursableToUserId, // Issue #19
    double? reimbursableAmount, // Issue #19
    String? reimbursementNote, // Issue #19
    String? reimbursementConfirmedBy, // Issue #19
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
  });

  /// Get expenses where the current user is the designated debtor (Issue #19).
  Future<List<ExpenseModel>> getMyDebts();

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
}

/// Implementation of [ExpenseRemoteDataSource] using Supabase.
class ExpenseRemoteDataSourceImpl implements ExpenseRemoteDataSource {
  ExpenseRemoteDataSourceImpl({
    required this.supabaseClient,
    this.offlineLocalDataSource,
    this.expenseCacheDataSource,
  });

  final SupabaseClient supabaseClient;

  /// Optional offline datasource for pending expenses created offline (T8)
  final OfflineExpenseLocalDataSource? offlineLocalDataSource;

  /// Cache datasource for read-through caching of online expenses (issue #30 fix)
  final ExpenseCacheDataSource? expenseCacheDataSource;

  String get _currentUserId {
    final userId = supabaseClient.auth.currentUser?.id;
    if (userId == null) {
      throw const AppAuthException('Nessun utente autenticato', 'not_authenticated');
    }
    return userId;
  }

  // T5: _currentUserGroupId with 10s timeout
  Future<String?> get _currentUserGroupId async {
    final userId = _currentUserId;
    final response = await supabaseClient
        .from('profiles')
        .select('group_id')
        .eq('id', userId)
        .single()
        .timeout(const Duration(seconds: 10));
    return response['group_id'] as String?;
  }

  /// Returns true for network-level errors that justify cache fallback.
  /// Application errors (auth, DB schema, RLS) must be re-thrown.
  bool _isNetworkError(Object e) {
    if (e is TimeoutException) return true;
    if (e is SocketException) return true;
    if (e is HttpException) return true;
    // PostgrestException with network-like codes (connection refused, etc.)
    // We do NOT catch generic PostgrestException — those are app errors (RLS, schema, etc.)
    return false;
  }

  // Fix issue #30: getExpenses — 10s timeout + write-through cache + specific catch
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
    String? groupId;

    try {
      groupId = await _currentUserGroupId;
      if (groupId == null) {
        throw const GroupException('Non fai parte di nessun gruppo', 'not_in_group');
      }

      // Build the filter query with JOIN to get category name
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
      if (reimbursementStatus != null) {
        filterQuery = filterQuery.eq('reimbursement_status', reimbursementStatus.value);
      }

      // Apply ordering and pagination
      var orderedQuery = filterQuery.order('date', ascending: false);

      if (offset != null && limit != null) {
        orderedQuery = orderedQuery.range(offset, offset + limit - 1);
      } else if (limit != null) {
        orderedQuery = orderedQuery.limit(limit);
      }

      // 10s timeout on Supabase query
      final response = await orderedQuery.timeout(const Duration(seconds: 10));
      final expenses = (response as List).map((json) {
        if (json['category_name'] != null && json['category_name'] is Map) {
          json['category_name'] = json['category_name']['name'];
        }
        return ExpenseModel.fromJson(json);
      }).toList();

      // ✅ WRITE-THROUGH CACHE: save to Drift after every successful online fetch
      // Only cache unfiltered (full group) fetches to keep cache coherent
      final isUnfiltered = startDate == null &&
          endDate == null &&
          categoryId == null &&
          createdBy == null &&
          paidBy == null &&
          reimbursementStatus == null &&
          offset == null;
      if (isUnfiltered && expenseCacheDataSource != null) {
        try {
          await expenseCacheDataSource!.cacheExpenses(groupId, expenses);
        } catch (cacheErr) {
          debugPrint('[CACHE] Failed to cache expenses: $cacheErr');
        }
      }

      return expenses;
    } catch (e) {
      // Re-throw application errors — they must bubble up to the UI
      if (e is AppAuthException) rethrow;
      if (e is GroupException) rethrow;

      // Only fall back to cache on genuine network/timeout errors
      if (!_isNetworkError(e)) rethrow;

      debugPrint('[OFFLINE] getExpenses network error, falling back to cache: $e');

      // Try read-through cache (online expenses saved when connected)
      if (expenseCacheDataSource != null && groupId != null) {
        try {
          final cached = await expenseCacheDataSource!.getCachedExpenses(
            groupId,
            startDate: startDate,
            endDate: endDate,
            categoryId: categoryId,
            createdBy: createdBy,
            limit: limit,
            offset: offset,
          );
          if (cached.isNotEmpty) {
            debugPrint('[OFFLINE] Returning ${cached.length} cached expenses');
            return cached;
          }
        } catch (cacheErr) {
          debugPrint('[OFFLINE] Cache read also failed: $cacheErr');
        }
      }

      // Last resort: pending offline expenses created while offline
      final userId = supabaseClient.auth.currentUser?.id;
      if (userId != null && offlineLocalDataSource != null) {
        try {
          final offlineExpenses =
              await offlineLocalDataSource!.getAllOfflineExpenses(userId);
          return _mapOfflineExpensesToModels(offlineExpenses);
        } catch (_) {}
      }

      return [];
    }
  }

  /// Convert offline expenses to ExpenseModel list for UI compatibility
  List<ExpenseModel> _mapOfflineExpensesToModels(
      List<OfflineExpenseEntity> offline) {
    final userId = supabaseClient.auth.currentUser?.id ?? '';
    return offline.map((e) {
      return ExpenseModel(
        id: e.id,
        groupId: '', // unknown offline
        createdBy: userId,
        amount: e.amount,
        date: e.date,
        categoryId: e.categoryId,
        paymentMethodId: '',
        merchant: e.merchant,
        notes: e.notes,
        isGroupExpense: e.isGroupExpense,
        reimbursementStatus: ReimbursementStatus.none,
        createdAt: e.localCreatedAt,
        updatedAt: e.localUpdatedAt,
      );
    }).toList();
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
    String? reimbursableToLabel, // Issue #19
    String? reimbursableToUserId, // Issue #19
    double? reimbursableAmount, // Issue #19
    String? reimbursementNote, // Issue #19
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

      // T8: Parallelize profile lookups to avoid sequential timeouts
      debugPrint('🔍 CREATE EXPENSE: Fetching profiles in parallel');
      final profileFutures = <Future<Map<String, dynamic>?>>[];

      Future<Map<String, dynamic>?> fetchProfile(String uid) async {
        try {
          return await supabaseClient
              .from('profiles')
              .select('display_name')
              .eq('id', uid)
              .single()
              .timeout(const Duration(seconds: 5));
        } catch (_) {
          return null;
        }
      }

      final creatorProfileFuture = fetchProfile(effectiveCreatedBy);
      final paidByProfileFuture = effectivePaidBy != effectiveCreatedBy
          ? fetchProfile(effectivePaidBy)
          : Future.value(null);

      final profileResults =
          await Future.wait([creatorProfileFuture, paidByProfileFuture]);
      final creatorDisplayName =
          profileResults[0]?['display_name'] as String? ?? 'Utente';
      debugPrint('🔍 CREATE EXPENSE: Creator profile resolved: $creatorDisplayName');

      final paidByDisplayName = effectivePaidBy != effectiveCreatedBy
          ? (profileResults[1]?['display_name'] as String? ?? 'Utente')
          : creatorDisplayName;
      debugPrint('🔍 CREATE EXPENSE: PaidBy profile resolved: $paidByDisplayName');

      // Get payment method ID if not provided (default to "Contanti")
      String finalPaymentMethodId = paymentMethodId ?? '';
      if (paymentMethodId == null) {
        final defaultPaymentMethod = await supabaseClient
            .from('payment_methods')
            .select('id')
            .eq('name', 'Contanti')
            .eq('is_default', true)
            .single()
            .timeout(const Duration(seconds: 5));
        finalPaymentMethodId = defaultPaymentMethod['id'] as String;
      }

      // Get payment method name for denormalization
      final paymentMethodResponse = await supabaseClient
          .from('payment_methods')
          .select('name')
          .eq('id', finalPaymentMethodId)
          .single()
          .timeout(const Duration(seconds: 5));
      final paymentMethodName = paymentMethodResponse['name'] as String;

      // Normalize date to UTC date only (no time component)
      final normalizedDate = DateTime.utc(date.year, date.month, date.day);

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
            'date': normalizedDate.toIso8601String().split('T')[0],
            'category_id': categoryId,
            'payment_method_id': finalPaymentMethodId,
            'payment_method_name': paymentMethodName,
            'merchant': merchant,
            'notes': notes,
            'is_group_expense': isGroupExpense,
            'reimbursement_status': reimbursementStatus.value, // T048
            'last_modified_by': lastModifiedBy ?? effectiveCreatedBy, // T014: Set last_modified_by
            if (reimbursableToLabel != null) 'reimbursable_to_label': reimbursableToLabel,
            if (reimbursableToUserId != null) 'reimbursable_to_user_id': reimbursableToUserId,
            if (reimbursableAmount != null) 'reimbursable_amount': reimbursableAmount,
            if (reimbursementNote != null) 'reimbursement_note': reimbursementNote,
          })
          .select('*, category_name:expense_categories(name)')
          .single()
          .timeout(const Duration(seconds: 5)); // T8

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
      // T8: write-through — if server write fails, save offline
      final offline = offlineLocalDataSource;
      if (offline != null) {
        final userId = supabaseClient.auth.currentUser?.id;
        if (userId != null) {
          try {
            final offlineEntity = await offline.createOfflineExpense(
              userId: userId,
              amount: amount,
              date: date,
              categoryId: categoryId,
              merchant: merchant,
              notes: notes,
              isGroupExpense: isGroupExpense,
            );
            debugPrint('[OFFLINE] Expense saved locally, id=${offlineEntity.id}');
            return _offlineEntityToModel(offlineEntity, userId);
          } catch (offlineErr) {
            debugPrint('❌ CREATE EXPENSE offline fallback failed: $offlineErr');
          }
        }
      }
      throw ServerException(e.message, e.code);
    } catch (e) {
      debugPrint('❌ CREATE EXPENSE: Exception - ${e.toString()}');
      if (e is AppAuthException || e is GroupException) rethrow;
      // T8: write-through — if server write fails, save offline
      final offline = offlineLocalDataSource;
      if (offline != null) {
        final userId = supabaseClient.auth.currentUser?.id;
        if (userId != null) {
          try {
            final offlineEntity = await offline.createOfflineExpense(
              userId: userId,
              amount: amount,
              date: date,
              categoryId: categoryId,
              merchant: merchant,
              notes: notes,
              isGroupExpense: isGroupExpense,
            );
            debugPrint('[OFFLINE] Expense saved locally, id=${offlineEntity.id}');
            return _offlineEntityToModel(offlineEntity, userId);
          } catch (offlineErr) {
            debugPrint('❌ CREATE EXPENSE offline fallback failed: $offlineErr');
          }
        }
      }
      throw ServerException(e.toString());
    }
  }

  /// Convert offline entity to ExpenseModel for UI compatibility
  ExpenseModel _offlineEntityToModel(
      OfflineExpenseEntity entity, String userId) {
    return ExpenseModel(
      id: entity.id,
      groupId: '',
      createdBy: userId,
      amount: entity.amount,
      date: entity.date,
      categoryId: entity.categoryId,
      paymentMethodId: '',
      merchant: entity.merchant,
      notes: entity.notes,
      isGroupExpense: entity.isGroupExpense,
      reimbursementStatus: ReimbursementStatus.none,
      createdAt: entity.localCreatedAt,
      updatedAt: entity.localUpdatedAt,
    );
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
    String? reimbursableToLabel, // Issue #19
    String? reimbursableToUserId, // Issue #19
    double? reimbursableAmount, // Issue #19
    String? reimbursementNote, // Issue #19
    String? reimbursementConfirmedBy, // Issue #19
  }) async {
    try {
      final updates = <String, dynamic>{};

      if (amount != null) updates['amount'] = amount;
      if (date != null) updates['date'] = date.toIso8601String().split('T')[0];
      if (categoryId != null) updates['category_id'] = categoryId;
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
      if (merchant != null) updates['merchant'] = merchant;
      if (notes != null) updates['notes'] = notes;
      if (reimbursementStatus != null) updates['reimbursement_status'] = reimbursementStatus.value; // T048
      if (reimbursableToLabel != null) updates['reimbursable_to_label'] = reimbursableToLabel;
      if (reimbursableToUserId != null) updates['reimbursable_to_user_id'] = reimbursableToUserId;
      if (reimbursableAmount != null) updates['reimbursable_amount'] = reimbursableAmount;
      if (reimbursementNote != null) updates['reimbursement_note'] = reimbursementNote;
      if (reimbursementConfirmedBy != null) updates['reimbursement_confirmed_by'] = reimbursementConfirmedBy;

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
  }) async {
    try {
      final updates = <String, dynamic>{};

      // Add last_modified_by for audit trail
      updates['last_modified_by'] = lastModifiedBy;

      if (amount != null) updates['amount'] = amount;
      if (date != null) updates['date'] = date.toIso8601String().split('T')[0];
      if (categoryId != null) updates['category_id'] = categoryId;
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
      if (merchant != null) updates['merchant'] = merchant;
      if (notes != null) updates['notes'] = notes;
      if (reimbursementStatus != null) updates['reimbursement_status'] = reimbursementStatus.value;

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
  Future<List<ExpenseModel>> getMyDebts() async {
    try {
      final currentUserId = _currentUserId;

      final response = await supabaseClient
          .from('expenses')
          .select('*, category_name:expense_categories(name)')
          .eq('reimbursable_to_user_id', currentUserId)
          .eq('reimbursement_status', 'reimbursable')
          .order('date', ascending: false);

      return (response as List).map((json) {
        if (json['category_name'] != null && json['category_name'] is Map) {
          json['category_name'] = json['category_name']['name'];
        }
        return ExpenseModel.fromJson(json);
      }).toList();
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      if (e is AppAuthException) rethrow;
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
      final path = '$userId/$expenseId.jpg';

      await supabaseClient.storage
          .from('receipts')
          .uploadBinary(
            path,
            imageData,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
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
}
