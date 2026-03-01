import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/enums/reimbursement_status.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../widget/presentation/services/widget_update_service.dart';
import '../../data/datasources/expense_remote_datasource.dart';
import '../../data/repositories/expense_repository_impl.dart';
import '../../domain/entities/expense_entity.dart';
import '../../domain/repositories/expense_repository.dart';
import '../widgets/reimbursement_status_change_dialog.dart';

/// Provider for expense remote data source
final expenseRemoteDataSourceProvider = Provider<ExpenseRemoteDataSource>((ref) {
  return ExpenseRemoteDataSourceImpl(
    supabaseClient: Supabase.instance.client,
  );
});

/// Provider for expense repository
final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepositoryImpl(
    remoteDataSource: ref.watch(expenseRemoteDataSourceProvider),
  );
});

/// Expense list state status
enum ExpenseListStatus {
  initial,
  loading,
  loaded,
  error,
}

/// Expense list state class
class ExpenseListState {
  const ExpenseListState({
    this.status = ExpenseListStatus.initial,
    this.expenses = const [],
    this.hasMore = true,
    this.errorMessage,
    this.filterCategoryId,
    this.filterStartDate,
    this.filterEndDate,
    this.filterCreatedBy,
    this.filterReimbursementStatus, // T044
    this.filterIsGroupExpense,
  });

  final ExpenseListStatus status;
  final List<ExpenseEntity> expenses;
  final bool hasMore;
  final String? errorMessage;
  final String? filterCategoryId;
  final DateTime? filterStartDate;
  final DateTime? filterEndDate;
  final String? filterCreatedBy;
  final ReimbursementStatus? filterReimbursementStatus; // T044
  final bool? filterIsGroupExpense;

  ExpenseListState copyWith({
    ExpenseListStatus? status,
    List<ExpenseEntity>? expenses,
    bool? hasMore,
    String? errorMessage,
    String? filterCategoryId,
    DateTime? filterStartDate,
    DateTime? filterEndDate,
    String? filterCreatedBy,
    ReimbursementStatus? filterReimbursementStatus, // T044
    bool? filterIsGroupExpense,
  }) {
    return ExpenseListState(
      status: status ?? this.status,
      expenses: expenses ?? this.expenses,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: errorMessage,
      filterCategoryId: filterCategoryId ?? this.filterCategoryId,
      filterStartDate: filterStartDate ?? this.filterStartDate,
      filterEndDate: filterEndDate ?? this.filterEndDate,
      filterCreatedBy: filterCreatedBy ?? this.filterCreatedBy,
      filterReimbursementStatus: filterReimbursementStatus ?? this.filterReimbursementStatus, // T044
      filterIsGroupExpense: filterIsGroupExpense ?? this.filterIsGroupExpense,
    );
  }

  bool get isLoading => status == ExpenseListStatus.loading;
  bool get hasError => status == ExpenseListStatus.error;
  bool get isEmpty => expenses.isEmpty && status == ExpenseListStatus.loaded;
  bool get hasFilters =>
      filterCategoryId != null ||
      filterStartDate != null ||
      filterEndDate != null ||
      filterCreatedBy != null;
  // Note: filterIsGroupExpense is not included because it's always set by the tab
}

/// Expense list notifier
class ExpenseListNotifier extends StateNotifier<ExpenseListState> {
  ExpenseListNotifier(this._expenseRepository) : super(const ExpenseListState());

  final ExpenseRepository _expenseRepository;
  static const int _pageSize = 20;

  /// Load expenses
  Future<void> loadExpenses({bool refresh = false}) async {
    if (state.isLoading && !refresh) return;

    state = state.copyWith(
      status: ExpenseListStatus.loading,
      errorMessage: null,
      expenses: refresh ? [] : state.expenses,
    );

    final result = await _expenseRepository.getExpenses(
      startDate: state.filterStartDate,
      endDate: state.filterEndDate,
      categoryId: state.filterCategoryId,
      createdBy: state.filterCreatedBy,
      reimbursementStatus: state.filterReimbursementStatus, // T045, T046
      isGroupExpense: state.filterIsGroupExpense,
      limit: _pageSize,
      offset: refresh ? 0 : state.expenses.length,
    );

    result.fold(
      (failure) {
        state = state.copyWith(
          status: ExpenseListStatus.error,
          errorMessage: failure.message,
        );
      },
      (expenses) {
        state = state.copyWith(
          status: ExpenseListStatus.loaded,
          expenses: refresh ? expenses : [...state.expenses, ...expenses],
          hasMore: expenses.length >= _pageSize,
        );
      },
    );
  }

  /// Load more expenses (pagination)
  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoading) return;
    await loadExpenses();
  }

  /// Refresh expenses
  Future<void> refresh() async {
    await loadExpenses(refresh: true);
  }

  /// Set category filter
  void setFilterCategory(String? categoryId) {
    state = state.copyWith(filterCategoryId: categoryId);
    loadExpenses(refresh: true);
  }

  /// Set date range filter
  void setFilterDateRange(DateTime? start, DateTime? end) {
    state = state.copyWith(
      filterStartDate: start,
      filterEndDate: end,
    );
    loadExpenses(refresh: true);
  }

  /// Set created by filter
  void setFilterCreatedBy(String? userId) {
    state = state.copyWith(filterCreatedBy: userId);
    loadExpenses(refresh: true);
  }

  /// Set reimbursement status filter (T044, T045)
  void setFilterReimbursementStatus(ReimbursementStatus? status) {
    state = state.copyWith(filterReimbursementStatus: status);
    loadExpenses(refresh: true);
  }

  /// Set group expense filter
  void setFilterIsGroupExpense(bool? isGroupExpense) {
    state = state.copyWith(filterIsGroupExpense: isGroupExpense);
    loadExpenses(refresh: true);
  }

  /// Clear group expense filter to show all expenses
  void clearIsGroupExpenseFilter() {
    state = state.copyWith(filterIsGroupExpense: null);
    loadExpenses(refresh: true);
  }

  /// Clear all filters (except isGroupExpense which is set by the tab)
  void clearFilters() {
    final currentIsGroupExpense = state.filterIsGroupExpense;
    state = ExpenseListState(filterIsGroupExpense: currentIsGroupExpense);
    loadExpenses(refresh: true);
  }

  /// Add expense to list (after creation)
  void addExpense(ExpenseEntity expense) {
    state = state.copyWith(
      expenses: [expense, ...state.expenses],
    );
  }

  /// Update expense in list
  void updateExpenseInList(ExpenseEntity expense) {
    state = state.copyWith(
      expenses: state.expenses.map((e) => e.id == expense.id ? expense : e).toList(),
    );
  }

  /// Remove expense from list
  void removeExpenseFromList(String expenseId) {
    state = state.copyWith(
      expenses: state.expenses.where((e) => e.id != expenseId).toList(),
    );
  }

  /// Get expense by ID from current list
  /// Returns null if expense not found in loaded expenses
  ExpenseEntity? getExpenseById(String expenseId) {
    try {
      return state.expenses.firstWhere((e) => e.id == expenseId);
    } catch (_) {
      return null;
    }
  }

  /// Update reimbursement status of an expense (T038, T039)
  ///
  /// Handles confirmation dialog for reversions from reimbursed state
  /// Updates the expense locally and persists to repository
  Future<void> updateReimbursementStatus({
    required BuildContext context,
    required String expenseId,
    required ReimbursementStatus newStatus,
  }) async {
    final expense = getExpenseById(expenseId);
    if (expense == null) return;

    // Check if confirmation needed (T039)
    if (expense.requiresConfirmation(newStatus)) {
      final confirmed = await ReimbursementStatusChangeDialog.show(
        context,
        expenseName: expense.categoryName ?? 'Questa spesa',
        currentStatus: expense.reimbursementStatus,
        newStatus: newStatus,
      );

      if (confirmed != true) return; // User cancelled
    }

    // Validate transition
    if (!expense.canTransitionTo(newStatus)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Transizione di stato non valida'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    // Update expense using entity method
    final updatedExpense = expense.updateReimbursementStatus(newStatus);

    // Persist to repository
    final result = await _expenseRepository.updateExpense(
      expenseId: expenseId,
      reimbursementStatus: newStatus,
    );

    result.fold(
      (failure) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(failure.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      (_) {
        // Update local state
        updateExpenseInList(updatedExpense);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Stato rimborso aggiornato'),
            ),
          );
        }
      },
    );
  }
}

/// Provider for expense list state
final expenseListProvider =
    StateNotifierProvider<ExpenseListNotifier, ExpenseListState>((ref) {
  // Refresh when auth changes
  ref.watch(authProvider);
  return ExpenseListNotifier(ref.watch(expenseRepositoryProvider));
});

/// Expense form state
enum ExpenseFormStatus {
  initial,
  submitting,
  success,
  error,
}

/// Expense form state class
class ExpenseFormState {
  const ExpenseFormState({
    this.status = ExpenseFormStatus.initial,
    this.expense,
    this.errorMessage,
  });

  final ExpenseFormStatus status;
  final ExpenseEntity? expense;
  final String? errorMessage;

  ExpenseFormState copyWith({
    ExpenseFormStatus? status,
    ExpenseEntity? expense,
    String? errorMessage,
  }) {
    return ExpenseFormState(
      status: status ?? this.status,
      expense: expense ?? this.expense,
      errorMessage: errorMessage,
    );
  }

  bool get isSubmitting => status == ExpenseFormStatus.submitting;
  bool get isSuccess => status == ExpenseFormStatus.success;
  bool get hasError => status == ExpenseFormStatus.error;
}

/// Expense form notifier
class ExpenseFormNotifier extends StateNotifier<ExpenseFormState> {
  ExpenseFormNotifier(
    this._expenseRepository,
    this._widgetUpdateService,
  ) : super(const ExpenseFormState());

  final ExpenseRepository _expenseRepository;
  final WidgetUpdateService _widgetUpdateService;

  /// Create a new expense
  ///
  /// T014: For admin creating expenses on behalf of members:
  /// - createdBy: User ID of who created the expense (defaults to current user)
  /// - lastModifiedBy: User ID of who last modified (for audit trail when admin creates)
  Future<ExpenseEntity?> createExpense({
    required double amount,
    required DateTime date,
    required String categoryId,
    String? paymentMethodId, // Defaults to "Contanti" if null
    String? merchant,
    String? notes,
    Uint8List? receiptImage,
    bool isGroupExpense = true,
    ReimbursementStatus reimbursementStatus = ReimbursementStatus.none, // T035
    String? createdBy, // T014
    String? paidBy, // For admin creating expense for specific member
    String? lastModifiedBy, // T014
  }) async {
    state = state.copyWith(status: ExpenseFormStatus.submitting, errorMessage: null);

    final result = await _expenseRepository.createExpense(
      amount: amount,
      date: date,
      categoryId: categoryId,
      paymentMethodId: paymentMethodId,
      merchant: merchant,
      notes: notes,
      receiptImage: receiptImage,
      isGroupExpense: isGroupExpense,
      reimbursementStatus: reimbursementStatus, // T035
      createdBy: createdBy, // T014
      paidBy: paidBy, // Pass paid_by to repository
      lastModifiedBy: lastModifiedBy, // T014
    );

    return result.fold(
      (failure) {
        state = state.copyWith(
          status: ExpenseFormStatus.error,
          errorMessage: failure.message,
        );
        return null;
      },
      (expense) {
        state = state.copyWith(
          status: ExpenseFormStatus.success,
          expense: expense,
        );
        // Trigger widget update after successful expense creation
        _widgetUpdateService.triggerUpdate().catchError((error) {
          print('Failed to update widget: $error');
        });
        return expense;
      },
    );
  }

  /// Update an existing expense
  Future<ExpenseEntity?> updateExpense({
    required String expenseId,
    double? amount,
    DateTime? date,
    String? categoryId,
    String? paymentMethodId,
    String? merchant,
    String? notes,
    ReimbursementStatus? reimbursementStatus, // T036
  }) async {
    state = state.copyWith(status: ExpenseFormStatus.submitting, errorMessage: null);

    final result = await _expenseRepository.updateExpense(
      expenseId: expenseId,
      amount: amount,
      date: date,
      categoryId: categoryId,
      paymentMethodId: paymentMethodId,
      merchant: merchant,
      notes: notes,
      reimbursementStatus: reimbursementStatus, // T036
    );

    return result.fold(
      (failure) {
        state = state.copyWith(
          status: ExpenseFormStatus.error,
          errorMessage: failure.message,
        );
        return null;
      },
      (expense) {
        state = state.copyWith(
          status: ExpenseFormStatus.success,
          expense: expense,
        );
        // Trigger widget update after successful expense update
        _widgetUpdateService.triggerUpdate().catchError((error) {
          print('Failed to update widget: $error');
        });
        return expense;
      },
    );
  }

  /// Update an existing expense with optimistic locking (Feature 001-admin-expenses-cash-fix)
  ///
  /// Uses the updated_at timestamp for optimistic locking to prevent concurrent edit conflicts.
  /// Throws ConflictException (wrapped in ConflictFailure) if the expense was modified by another user.
  Future<ExpenseEntity?> updateExpenseWithLock({
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
    state = state.copyWith(status: ExpenseFormStatus.submitting, errorMessage: null);

    final result = await _expenseRepository.updateExpenseWithTimestamp(
      expenseId: expenseId,
      originalUpdatedAt: originalUpdatedAt,
      lastModifiedBy: lastModifiedBy,
      amount: amount,
      date: date,
      categoryId: categoryId,
      paymentMethodId: paymentMethodId,
      merchant: merchant,
      notes: notes,
      reimbursementStatus: reimbursementStatus,
    );

    return result.fold(
      (failure) {
        state = state.copyWith(
          status: ExpenseFormStatus.error,
          errorMessage: failure.message,
        );
        return null;
      },
      (expense) {
        state = state.copyWith(
          status: ExpenseFormStatus.success,
          expense: expense,
        );
        // Trigger widget update after successful expense update
        _widgetUpdateService.triggerUpdate().catchError((error) {
          print('Failed to update widget: $error');
        });
        return expense;
      },
    );
  }

  /// Update expense classification (group or personal)
  Future<ExpenseEntity?> updateExpenseClassification({
    required String expenseId,
    required bool isGroupExpense,
  }) async {
    state = state.copyWith(status: ExpenseFormStatus.submitting, errorMessage: null);

    final result = await _expenseRepository.updateExpenseClassification(
      expenseId: expenseId,
      isGroupExpense: isGroupExpense,
    );

    return result.fold(
      (failure) {
        state = state.copyWith(
          status: ExpenseFormStatus.error,
          errorMessage: failure.message,
        );
        return null;
      },
      (expense) {
        state = state.copyWith(
          status: ExpenseFormStatus.success,
          expense: expense,
        );
        // Trigger widget update after successful classification change
        _widgetUpdateService.triggerUpdate().catchError((error) {
          print('Failed to update widget: $error');
        });
        return expense;
      },
    );
  }

  /// Delete an expense
  Future<bool> deleteExpense({required String expenseId}) async {
    state = state.copyWith(status: ExpenseFormStatus.submitting, errorMessage: null);

    final result = await _expenseRepository.deleteExpense(expenseId: expenseId);

    return result.fold(
      (failure) {
        state = state.copyWith(
          status: ExpenseFormStatus.error,
          errorMessage: failure.message,
        );
        return false;
      },
      (_) {
        state = state.copyWith(status: ExpenseFormStatus.success);
        // Trigger widget update after successful expense deletion
        _widgetUpdateService.triggerUpdate().catchError((error) {
          print('Failed to update widget: $error');
        });
        return true;
      },
    );
  }

  /// Reset form state
  void reset() {
    state = const ExpenseFormState();
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}

/// Provider for expense form state
final expenseFormProvider =
    StateNotifierProvider<ExpenseFormNotifier, ExpenseFormState>((ref) {
  return ExpenseFormNotifier(
    ref.watch(expenseRepositoryProvider),
    ref.watch(widgetUpdateServiceProvider),
  );
});

/// Provider for a single expense
final expenseProvider = FutureProvider.family<ExpenseEntity?, String>((ref, expenseId) async {
  final repository = ref.watch(expenseRepositoryProvider);
  final result = await repository.getExpense(expenseId: expenseId);
  return result.fold((_) => null, (expense) => expense);
});

/// Provider for recent group expenses (last 10 expenses for the whole group)
final recentGroupExpensesProvider = FutureProvider<List<ExpenseEntity>>((ref) async {
  final repository = ref.watch(expenseRepositoryProvider);
  final result = await repository.getExpenses(
    isGroupExpense: true,
    limit: 10,
  );
  return result.fold(
    (_) => [],
    (expenses) => expenses,
  );
});

/// Provider for recent personal expenses (last 10 expenses paid by current user)
/// Uses paid_by filter to include expenses created by admin on behalf of user
final recentPersonalExpensesProvider = FutureProvider<List<ExpenseEntity>>((ref) async {
  final repository = ref.watch(expenseRepositoryProvider);
  final currentUser = Supabase.instance.client.auth.currentUser;

  if (currentUser == null) return [];

  final result = await repository.getExpenses(
    paidBy: currentUser.id,
    isGroupExpense: false,
    limit: 10,
  );
  return result.fold(
    (_) => [],
    (expenses) => expenses,
  );
});

/// Provider per spese filtrate per categoria e utente (tutte le spese pagate dall'utente)
/// Uses paid_by to include expenses created by admin on behalf of user
final expensesByCategoryProvider = FutureProvider.autoDispose
    .family<List<ExpenseEntity>, ({String userId, String categoryId})>((ref, params) async {
  final repository = ref.watch(expenseRepositoryProvider);
  final now = DateTime.now();
  final startOfMonth = DateTime(now.year, now.month, 1);
  final endOfMonth = DateTime(now.year, now.month + 1, 0);

  final result = await repository.getExpenses(
    paidBy: params.userId, // Use paid_by instead of created_by
    categoryId: params.categoryId,
    // Non filtriamo per isGroupExpense - mostriamo tutte le spese della categoria
    startDate: startOfMonth,
    endDate: endOfMonth,
  );

  return result.fold(
    (_) => [],
    (expenses) => expenses,
  );
});

/// Provider for selected member when admin creates expense on behalf of member (Feature 001-admin-expenses-cash-fix)
///
/// This provider holds the user ID of the member for whom the admin is creating/editing an expense.
/// - null means expense created by/for current user (default behavior)
/// - Non-null means admin is creating expense on behalf of selected member
final selectedMemberForExpenseProvider = StateProvider<String?>((ref) => null);
