// Provider: Orphaned Expenses Provider
// Feature: Italian Categories and Budget Management (004)
// Task: T071-T072

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/expense_entity.dart';
import '../../../groups/presentation/providers/group_provider.dart';

/// State for orphaned expenses
class OrphanedExpensesState {
  const OrphanedExpensesState({
    this.expenses = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final List<ExpenseEntity> expenses;
  final bool isLoading;
  final String? errorMessage;

  OrphanedExpensesState copyWith({
    List<ExpenseEntity>? expenses,
    bool? isLoading,
    String? errorMessage,
  }) {
    return OrphanedExpensesState(
      expenses: expenses ?? this.expenses,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

/// Notifier for orphaned expenses
class OrphanedExpensesNotifier extends StateNotifier<OrphanedExpensesState> {
  OrphanedExpensesNotifier(
    this._supabaseClient,
    this._groupId,
  ) : super(const OrphanedExpensesState()) {
    loadOrphanedExpenses();
  }

  final SupabaseClient _supabaseClient;
  final String _groupId;

  /// Load orphaned expenses (where category_id is NULL)
  Future<void> loadOrphanedExpenses() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final response = await _supabaseClient
          .from('expenses')
          .select('*')
          .eq('group_id', _groupId)
          .isFilter('category_id', null)
          .order('date', ascending: false);

      final expenses = (response as List)
          .map((json) => _expenseFromJson(json as Map<String, dynamic>))
          .toList();

      state = state.copyWith(
        expenses: expenses,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Errore nel caricamento delle spese: $e',
      );
    }
  }

  /// Batch reassign expenses to a new category using RPC
  Future<bool> batchReassignToCategory({
    required List<String> expenseIds,
    required String newCategoryId,
  }) async {
    try {
      final count = await _supabaseClient.rpc(
        'batch_reassign_orphaned_expenses',
        params: {
          'p_expense_ids': expenseIds,
          'p_new_category_id': newCategoryId,
        },
      );

      // Reload expenses after successful reassignment
      if (count != null && count > 0) {
        await loadOrphanedExpenses();
        return true;
      }

      return false;
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Errore nell\'assegnare le categorie: $e',
      );
      return false;
    }
  }

  /// Helper to convert JSON to ExpenseEntity
  ExpenseEntity _expenseFromJson(Map<String, dynamic> json) {
    return ExpenseEntity(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      createdBy: json['created_by'] as String? ?? '',
      amount: (json['amount'] as num).toDouble() / 100, // Convert from cents
      date: DateTime.parse(json['date'] as String),
      categoryId: json['category_id'] as String? ?? '', // Orphaned will be NULL
      categoryName: json['category_name'] as String?,
      paymentMethodId: json['payment_method_id'] as String? ?? '', // Default to empty string
      paymentMethodName: json['payment_method_name'] as String?,
      isGroupExpense: json['is_group_expense'] as bool? ?? true,
      merchant: json['merchant'] as String?,
      notes: json['notes'] as String?,
      receiptUrl: json['receipt_url'] as String?,
      createdByName: json['created_by_name'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }
}

/// Provider for orphaned expenses
final orphanedExpensesProvider = StateNotifierProvider.family<
    OrphanedExpensesNotifier,
    OrphanedExpensesState,
    String>(
  (ref, groupId) {
    final supabaseClient = Supabase.instance.client;
    return OrphanedExpensesNotifier(supabaseClient, groupId);
  },
);

/// Convenience provider for current group's orphaned expenses
final currentGroupOrphanedExpensesProvider =
    Provider<OrphanedExpensesState>((ref) {
  final groupId = ref.watch(currentGroupIdProvider);
  return ref.watch(orphanedExpensesProvider(groupId));
});
