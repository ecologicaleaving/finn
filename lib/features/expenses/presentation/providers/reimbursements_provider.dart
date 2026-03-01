import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/enums/reimbursement_status.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/expense_entity.dart';
import '../../domain/repositories/expense_repository.dart';
import 'expense_provider.dart';

/// Reimbursements list state
class ReimbursementsListState {
  const ReimbursementsListState({
    this.reimbursableExpenses = const [],
    this.reimbursedExpenses = const [],
    this.isLoading = false,
    this.errorMessage,
    this.filter = ReimbursementFilter.all,
  });

  final List<ExpenseEntity> reimbursableExpenses;
  final List<ExpenseEntity> reimbursedExpenses;
  final bool isLoading;
  final String? errorMessage;
  final ReimbursementFilter filter;

  bool get hasError => errorMessage != null;
  bool get isEmpty =>
      reimbursableExpenses.isEmpty && reimbursedExpenses.isEmpty;

  /// Get total pending reimbursements amount in cents
  int get totalPendingAmount {
    return reimbursableExpenses.fold<int>(
      0,
      (sum, expense) => sum + (expense.amount * 100).round(),
    );
  }

  /// Get total reimbursed amount in cents
  int get totalReimbursedAmount {
    return reimbursedExpenses.fold<int>(
      0,
      (sum, expense) => sum + (expense.amount * 100).round(),
    );
  }

  /// Get filtered expenses based on current filter
  List<ExpenseEntity> get filteredExpenses {
    switch (filter) {
      case ReimbursementFilter.reimbursable:
        return reimbursableExpenses;
      case ReimbursementFilter.reimbursed:
        return reimbursedExpenses;
      case ReimbursementFilter.all:
        return [...reimbursableExpenses, ...reimbursedExpenses]
          ..sort((a, b) => b.date.compareTo(a.date));
    }
  }

  ReimbursementsListState copyWith({
    List<ExpenseEntity>? reimbursableExpenses,
    List<ExpenseEntity>? reimbursedExpenses,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    ReimbursementFilter? filter,
  }) {
    return ReimbursementsListState(
      reimbursableExpenses: reimbursableExpenses ?? this.reimbursableExpenses,
      reimbursedExpenses: reimbursedExpenses ?? this.reimbursedExpenses,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      filter: filter ?? this.filter,
    );
  }
}

/// Filter enum for reimbursements
enum ReimbursementFilter {
  all,
  reimbursable,
  reimbursed,
}

/// Reimbursements list notifier
///
/// Feature 013-recurring-expenses - User Story 4 (T051)
///
/// Manages the list of expenses with reimbursement status,
/// providing filtering and summary calculations.
class ReimbursementsListNotifier
    extends StateNotifier<ReimbursementsListState> {
  ReimbursementsListNotifier(this._expenseRepository)
      : super(const ReimbursementsListState());

  final ExpenseRepository _expenseRepository;

  /// Load all reimbursement-related expenses
  Future<void> loadReimbursements({bool refresh = false}) async {
    if (state.isLoading && !refresh) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Get all expenses with reimbursement status
      final result = await _expenseRepository.getExpenses();

      result.fold(
        (failure) {
          state = state.copyWith(
            isLoading: false,
            errorMessage: failure.message,
          );
        },
        (expenses) {
          // Split into reimbursable and reimbursed
          final reimbursable = expenses
              .where((e) =>
                  e.reimbursementStatus == ReimbursementStatus.reimbursable)
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));

          final reimbursed = expenses
              .where((e) =>
                  e.reimbursementStatus == ReimbursementStatus.reimbursed)
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));

          state = state.copyWith(
            reimbursableExpenses: reimbursable,
            reimbursedExpenses: reimbursed,
            isLoading: false,
          );
        },
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Errore nel caricamento dei rimborsi: ${e.toString()}',
      );
    }
  }

  /// Set filter
  void setFilter(ReimbursementFilter filter) {
    state = state.copyWith(filter: filter);
  }

  /// Mark expense as reimbursed
  Future<bool> markAsReimbursed(String expenseId) async {
    final expenseFormNotifier = _expenseRepository;

    final result = await expenseFormNotifier.updateExpense(
      expenseId: expenseId,
      reimbursementStatus: ReimbursementStatus.reimbursed,
    );

    return result.fold(
      (failure) {
        state = state.copyWith(errorMessage: failure.message);
        return false;
      },
      (updatedExpense) {
        // Move expense from reimbursable to reimbursed list
        final updatedReimbursable = state.reimbursableExpenses
            .where((e) => e.id != expenseId)
            .toList();
        final updatedReimbursed = <ExpenseEntity>[
          updatedExpense,
          ...state.reimbursedExpenses
        ]..sort((a, b) => b.date.compareTo(a.date));

        state = state.copyWith(
          reimbursableExpenses: updatedReimbursable,
          reimbursedExpenses: updatedReimbursed,
        );
        return true;
      },
    );
  }

  /// Refresh list
  Future<void> refresh() async {
    await loadReimbursements(refresh: true);
  }
}

/// Provider for reimbursements list
///
/// Feature 013-recurring-expenses - User Story 4 (T051)
final reimbursementsListProvider = StateNotifierProvider<
    ReimbursementsListNotifier, ReimbursementsListState>((ref) {
  // Refresh when auth changes
  ref.watch(authProvider);
  return ReimbursementsListNotifier(ref.watch(expenseRepositoryProvider));
});
