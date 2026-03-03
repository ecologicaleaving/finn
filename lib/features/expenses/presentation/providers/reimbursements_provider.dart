import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/enums/reimbursement_status.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/expense_entity.dart';
import '../../domain/repositories/expense_repository.dart';
import 'expense_provider.dart';

/// Aggregated data for a single creditor (Issue #19)
class CreditorGroup {
  const CreditorGroup({
    required this.label,
    this.userId,
    required this.expenses,
  });

  /// Display label (member name or free text)
  final String label;

  /// Family member user ID (null for external creditors like "Lavoro")
  final String? userId;

  /// All pending reimbursable expenses for this creditor
  final List<ExpenseEntity> expenses;

  /// Total amount to reimburse (uses reimbursableAmount if set, otherwise full amount)
  double get totalAmount =>
      expenses.fold(0, (sum, e) => sum + e.effectiveReimbursableAmount);

  int get expenseCount => expenses.length;
}

/// Reimbursements list state
class ReimbursementsListState {
  const ReimbursementsListState({
    this.reimbursableExpenses = const [],
    this.reimbursedExpenses = const [],
    this.myDebts = const [],
    this.isLoading = false,
    this.errorMessage,
    this.filter = ReimbursementFilter.all,
  });

  final List<ExpenseEntity> reimbursableExpenses;
  final List<ExpenseEntity> reimbursedExpenses;

  /// Expenses where I am the designated debtor (Issue #19)
  final List<ExpenseEntity> myDebts;

  final bool isLoading;
  final String? errorMessage;
  final ReimbursementFilter filter;

  bool get hasError => errorMessage != null;
  bool get isEmpty =>
      reimbursableExpenses.isEmpty && reimbursedExpenses.isEmpty;

  /// Expenses grouped by creditor label (Issue #19)
  List<CreditorGroup> get creditorGroups {
    final Map<String, List<ExpenseEntity>> byLabel = {};
    for (final expense in reimbursableExpenses) {
      final label = expense.reimbursableToLabel;
      if (label != null && label.isNotEmpty) {
        byLabel.putIfAbsent(label, () => []).add(expense);
      }
    }
    return byLabel.entries.map((entry) {
      final first = entry.value.first;
      return CreditorGroup(
        label: entry.key,
        userId: first.reimbursableToUserId,
        expenses: entry.value,
      );
    }).toList()
      ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
  }

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
    List<ExpenseEntity>? myDebts,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    ReimbursementFilter? filter,
  }) {
    return ReimbursementsListState(
      reimbursableExpenses: reimbursableExpenses ?? this.reimbursableExpenses,
      reimbursedExpenses: reimbursedExpenses ?? this.reimbursedExpenses,
      myDebts: myDebts ?? this.myDebts,
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
      // Get expenses where I am the debtor (Issue #19)
      final myDebtsResult = await _expenseRepository.getMyDebts();

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

          final myDebts = myDebtsResult.fold(
            (_) => <ExpenseEntity>[],
            (debts) => debts,
          );

          state = state.copyWith(
            reimbursableExpenses: reimbursable,
            reimbursedExpenses: reimbursed,
            myDebts: myDebts,
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

  /// Confirm reimbursement — called by the debtor (Issue #19).
  ///
  /// Sets status to `reimbursed` and records `reimbursement_confirmed_by`.
  Future<bool> confirmReimbursement(
    String expenseId,
    String currentUserId,
  ) async {
    final result = await _expenseRepository.updateExpense(
      expenseId: expenseId,
      reimbursementStatus: ReimbursementStatus.reimbursed,
      reimbursementConfirmedBy: currentUserId,
    );

    return result.fold(
      (failure) {
        state = state.copyWith(errorMessage: failure.message);
        return false;
      },
      (updatedExpense) {
        // Remove from myDebts list
        final updatedDebts =
            state.myDebts.where((e) => e.id != expenseId).toList();
        // Add to reimbursedExpenses list
        final updatedReimbursed = <ExpenseEntity>[
          updatedExpense,
          ...state.reimbursedExpenses
        ]..sort((a, b) => b.date.compareTo(a.date));
        // Remove from reimbursableExpenses list
        final updatedReimbursable = state.reimbursableExpenses
            .where((e) => e.id != expenseId)
            .toList();

        state = state.copyWith(
          myDebts: updatedDebts,
          reimbursedExpenses: updatedReimbursed,
          reimbursableExpenses: updatedReimbursable,
        );
        return true;
      },
    );
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
