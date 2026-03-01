import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/enums/recurrence_frequency.dart';
import '../../../../core/enums/reimbursement_status.dart';
import '../../../../core/errors/exceptions.dart';
import '../models/recurring_expense_entity.dart';

/// Remote data source for recurring expense operations using Supabase
///
/// Feature 013-recurring-expenses - User Story 1 (T030)
///
/// Provides:
/// - CRUD operations for recurring expense templates
/// - Realtime subscription for multi-device sync
/// - RLS-based multi-tenant security
abstract class RecurringExpenseRemoteDataSource {
  /// Get all recurring expenses for the current user
  Future<List<RecurringExpenseEntity>> getRecurringExpenses({
    required String userId,
    bool? isPaused,
    bool? budgetReservationEnabled,
  });

  /// Get a single recurring expense by ID
  Future<RecurringExpenseEntity> getRecurringExpense({
    required String id,
  });

  /// Create a new recurring expense template
  Future<RecurringExpenseEntity> createRecurringExpense({
    required String id,
    required String userId,
    String? groupId,
    required double amount,
    required String categoryId,
    required RecurrenceFrequency frequency,
    required DateTime anchorDate,
    String? merchant,
    String? notes,
    bool isGroupExpense = true,
    bool budgetReservationEnabled = false,
    ReimbursementStatus defaultReimbursementStatus = ReimbursementStatus.none,
    String? paymentMethodId,
  });

  /// Update an existing recurring expense template
  Future<RecurringExpenseEntity> updateRecurringExpense({
    required String id,
    double? amount,
    String? categoryId,
    RecurrenceFrequency? frequency,
    DateTime? anchorDate,
    String? merchant,
    String? notes,
    bool? budgetReservationEnabled,
    ReimbursementStatus? defaultReimbursementStatus,
    String? paymentMethodId,
  });

  /// Pause a recurring expense template (stop instance generation)
  Future<RecurringExpenseEntity> pauseRecurringExpense({
    required String id,
  });

  /// Resume a paused recurring expense template
  Future<RecurringExpenseEntity> resumeRecurringExpense({
    required String id,
  });

  /// Delete a recurring expense template
  Future<void> deleteRecurringExpense({
    required String id,
  });

  /// Watch recurring expenses with Realtime subscription (T030)
  ///
  /// Returns a stream that emits the latest list of recurring expenses
  /// whenever changes occur in the Supabase table.
  ///
  /// This enables multi-device sync - changes made on one device
  /// are automatically reflected on all other devices.
  Stream<List<RecurringExpenseEntity>> watchRecurringExpenses({
    required String userId,
  });
}

/// Implementation of [RecurringExpenseRemoteDataSource] using Supabase
class RecurringExpenseRemoteDataSourceImpl
    implements RecurringExpenseRemoteDataSource {
  RecurringExpenseRemoteDataSourceImpl({required this.supabaseClient});

  final SupabaseClient supabaseClient;

  String get _currentUserId {
    final userId = supabaseClient.auth.currentUser?.id;
    if (userId == null) {
      throw const AppAuthException(
        'Nessun utente autenticato',
        'not_authenticated',
      );
    }
    return userId;
  }

  @override
  Future<List<RecurringExpenseEntity>> getRecurringExpenses({
    required String userId,
    bool? isPaused,
    bool? budgetReservationEnabled,
  }) async {
    try {
      var query = supabaseClient
          .from('recurring_expenses')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      // Apply filters if provided
      if (isPaused != null) {
        query = query.eq('is_paused', isPaused);
      }
      if (budgetReservationEnabled != null) {
        query = query.eq('budget_reservation_enabled', budgetReservationEnabled);
      }

      final response = await query;

      return (response as List)
          .map((json) => RecurringExpenseEntity.fromJson(json))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException(
        'Errore nel recupero delle spese ricorrenti: ${e.toString()}',
        'recurring_expenses_fetch_error',
      );
    }
  }

  @override
  Future<RecurringExpenseEntity> getRecurringExpense({
    required String id,
  }) async {
    try {
      final response = await supabaseClient
          .from('recurring_expenses')
          .select()
          .eq('id', id)
          .single();

      return RecurringExpenseEntity.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException(
        'Errore nel recupero della spesa ricorrente: ${e.toString()}',
        'recurring_expense_fetch_error',
      );
    }
  }

  @override
  Future<RecurringExpenseEntity> createRecurringExpense({
    required String id,
    required String userId,
    String? groupId,
    required double amount,
    required String categoryId,
    required RecurrenceFrequency frequency,
    required DateTime anchorDate,
    String? merchant,
    String? notes,
    bool isGroupExpense = true,
    bool budgetReservationEnabled = false,
    ReimbursementStatus defaultReimbursementStatus = ReimbursementStatus.none,
    String? paymentMethodId,
  }) async {
    try {
      final now = DateTime.now();
      final data = {
        'id': id,
        'user_id': userId,
        'group_id': groupId,
        'amount': amount,
        'category_id': categoryId,
        'frequency': frequency.name,
        'anchor_date': anchorDate.toIso8601String(),
        'merchant': merchant,
        'notes': notes,
        'is_group_expense': isGroupExpense,
        'budget_reservation_enabled': budgetReservationEnabled,
        'default_reimbursement_status': defaultReimbursementStatus.name,
        'payment_method_id': paymentMethodId,
        'is_paused': false,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final response = await supabaseClient
          .from('recurring_expenses')
          .insert(data)
          .select()
          .single();

      return RecurringExpenseEntity.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException(
        'Errore nella creazione della spesa ricorrente: ${e.toString()}',
        'recurring_expense_create_error',
      );
    }
  }

  @override
  Future<RecurringExpenseEntity> updateRecurringExpense({
    required String id,
    double? amount,
    String? categoryId,
    RecurrenceFrequency? frequency,
    DateTime? anchorDate,
    String? merchant,
    String? notes,
    bool? budgetReservationEnabled,
    ReimbursementStatus? defaultReimbursementStatus,
    String? paymentMethodId,
  }) async {
    try {
      final data = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (amount != null) data['amount'] = amount;
      if (categoryId != null) data['category_id'] = categoryId;
      if (frequency != null) data['frequency'] = frequency.name;
      if (anchorDate != null) {
        data['anchor_date'] = anchorDate.toIso8601String();
      }
      if (merchant != null) data['merchant'] = merchant;
      if (notes != null) data['notes'] = notes;
      if (budgetReservationEnabled != null) {
        data['budget_reservation_enabled'] = budgetReservationEnabled;
      }
      if (defaultReimbursementStatus != null) {
        data['default_reimbursement_status'] = defaultReimbursementStatus.name;
      }
      if (paymentMethodId != null) data['payment_method_id'] = paymentMethodId;

      final response = await supabaseClient
          .from('recurring_expenses')
          .update(data)
          .eq('id', id)
          .select()
          .single();

      return RecurringExpenseEntity.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException(
        'Errore nell\'aggiornamento della spesa ricorrente: ${e.toString()}',
        'recurring_expense_update_error',
      );
    }
  }

  @override
  Future<RecurringExpenseEntity> pauseRecurringExpense({
    required String id,
  }) async {
    try {
      final response = await supabaseClient
          .from('recurring_expenses')
          .update({
            'is_paused': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id)
          .select()
          .single();

      return RecurringExpenseEntity.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException(
        'Errore nella sospensione della spesa ricorrente: ${e.toString()}',
        'recurring_expense_pause_error',
      );
    }
  }

  @override
  Future<RecurringExpenseEntity> resumeRecurringExpense({
    required String id,
  }) async {
    try {
      final response = await supabaseClient
          .from('recurring_expenses')
          .update({
            'is_paused': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id)
          .select()
          .single();

      return RecurringExpenseEntity.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException(
        'Errore nella riattivazione della spesa ricorrente: ${e.toString()}',
        'recurring_expense_resume_error',
      );
    }
  }

  @override
  Future<void> deleteRecurringExpense({
    required String id,
  }) async {
    try {
      await supabaseClient.from('recurring_expenses').delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException(
        'Errore nell\'eliminazione della spesa ricorrente: ${e.toString()}',
        'recurring_expense_delete_error',
      );
    }
  }

  @override
  Stream<List<RecurringExpenseEntity>> watchRecurringExpenses({
    required String userId,
  }) {
    try {
      // T030: Supabase Realtime subscription
      // This stream automatically emits whenever the recurring_expenses table changes
      return supabaseClient
          .from('recurring_expenses')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .map((data) {
            return data
                .map((json) => RecurringExpenseEntity.fromJson(json))
                .toList();
          });
    } catch (e) {
      throw ServerException(
        'Errore nella sottoscrizione alle spese ricorrenti: ${e.toString()}',
        'recurring_expense_watch_error',
      );
    }
  }
}
