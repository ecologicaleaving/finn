import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/database/daos/recurring_expenses_dao.dart';
import '../../../../core/enums/recurrence_frequency.dart';
import '../../../../core/enums/reimbursement_status.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../offline/presentation/providers/offline_providers.dart';
import '../../data/datasources/recurring_expense_local_datasource.dart';
import '../../data/repositories/recurring_expense_repository_impl.dart';
import '../../domain/entities/expense_entity.dart';
import '../../domain/entities/recurring_expense.dart';
import '../../domain/repositories/recurring_expense_repository.dart';
import 'expense_provider.dart';

/// Provider for recurring expense DAO
final recurringExpenseDaoProvider = Provider<RecurringExpensesDao>((ref) {
  final database = ref.watch(offlineDatabaseProvider);
  return RecurringExpensesDao(database);
});

/// Provider for recurring expense local data source
final recurringExpenseLocalDataSourceProvider =
    Provider<RecurringExpenseLocalDataSource>((ref) {
  return RecurringExpenseLocalDataSourceImpl(
    dao: ref.watch(recurringExpenseDaoProvider),
    database: ref.watch(offlineDatabaseProvider),
  );
});

/// Provider for recurring expense repository
final recurringExpenseRepositoryProvider =
    Provider<RecurringExpenseRepository>((ref) {
  return RecurringExpenseRepositoryImpl(
    localDataSource: ref.watch(recurringExpenseLocalDataSourceProvider),
    expenseRemoteDataSource: ref.watch(expenseRemoteDataSourceProvider),
    supabaseClient: Supabase.instance.client,
  );
});

/// Recurring expense list state status
enum RecurringExpenseListStatus {
  initial,
  loading,
  loaded,
  error,
}

/// Recurring expense list state class
class RecurringExpenseListState {
  const RecurringExpenseListState({
    this.status = RecurringExpenseListStatus.initial,
    this.templates = const [],
    this.errorMessage,
    this.filterIsPaused,
    this.filterBudgetReservationEnabled,
  });

  final RecurringExpenseListStatus status;
  final List<RecurringExpense> templates;
  final String? errorMessage;
  final bool? filterIsPaused;
  final bool? filterBudgetReservationEnabled;

  RecurringExpenseListState copyWith({
    RecurringExpenseListStatus? status,
    List<RecurringExpense>? templates,
    String? errorMessage,
    bool? filterIsPaused,
    bool? filterBudgetReservationEnabled,
  }) {
    return RecurringExpenseListState(
      status: status ?? this.status,
      templates: templates ?? this.templates,
      errorMessage: errorMessage,
      filterIsPaused: filterIsPaused ?? this.filterIsPaused,
      filterBudgetReservationEnabled:
          filterBudgetReservationEnabled ?? this.filterBudgetReservationEnabled,
    );
  }

  bool get isLoading => status == RecurringExpenseListStatus.loading;
  bool get hasError => status == RecurringExpenseListStatus.error;
  bool get isEmpty =>
      templates.isEmpty && status == RecurringExpenseListStatus.loaded;
  bool get hasFilters =>
      filterIsPaused != null || filterBudgetReservationEnabled != null;

  /// Get active recurring expenses (not paused)
  List<RecurringExpense> get activeTemplates =>
      templates.where((t) => !t.isPaused).toList();

  /// Get paused recurring expenses
  List<RecurringExpense> get pausedTemplates =>
      templates.where((t) => t.isPaused).toList();

  /// Get templates with budget reservation enabled
  List<RecurringExpense> get budgetReservationTemplates =>
      templates.where((t) => t.budgetReservationEnabled).toList();
}

/// Recurring expense list notifier
class RecurringExpenseListNotifier
    extends StateNotifier<RecurringExpenseListState> {
  RecurringExpenseListNotifier(this._recurringExpenseRepository)
      : super(const RecurringExpenseListState());

  final RecurringExpenseRepository _recurringExpenseRepository;

  /// Load recurring expenses
  Future<void> loadRecurringExpenses({bool refresh = false}) async {
    if (state.isLoading && !refresh) return;

    state = state.copyWith(
      status: RecurringExpenseListStatus.loading,
      errorMessage: null,
      templates: refresh ? [] : state.templates,
    );

    final result = await _recurringExpenseRepository.getRecurringExpenses(
      isPaused: state.filterIsPaused,
      budgetReservationEnabled: state.filterBudgetReservationEnabled,
    );

    result.fold(
      (failure) {
        state = state.copyWith(
          status: RecurringExpenseListStatus.error,
          errorMessage: failure.message,
        );
      },
      (templates) {
        state = state.copyWith(
          status: RecurringExpenseListStatus.loaded,
          templates: templates,
        );
      },
    );
  }

  /// Refresh recurring expenses
  Future<void> refresh() async {
    await loadRecurringExpenses(refresh: true);
  }

  /// Set pause filter
  void setFilterPaused(bool? isPaused) {
    state = state.copyWith(filterIsPaused: isPaused);
    loadRecurringExpenses(refresh: true);
  }

  /// Set budget reservation filter
  void setFilterBudgetReservation(bool? enabled) {
    state = state.copyWith(filterBudgetReservationEnabled: enabled);
    loadRecurringExpenses(refresh: true);
  }

  /// Clear all filters
  void clearFilters() {
    state = const RecurringExpenseListState();
    loadRecurringExpenses(refresh: true);
  }

  /// Add template to list (after creation)
  void addTemplate(RecurringExpense template) {
    state = state.copyWith(
      templates: [template, ...state.templates],
    );
  }

  /// Update template in list
  void updateTemplateInList(RecurringExpense template) {
    state = state.copyWith(
      templates: state.templates
          .map((t) => t.id == template.id ? template : t)
          .toList(),
    );
  }

  /// Remove template from list
  void removeTemplateFromList(String templateId) {
    state = state.copyWith(
      templates: state.templates.where((t) => t.id != templateId).toList(),
    );
  }

  /// Get template by ID from current list
  /// Returns null if template not found in loaded templates
  RecurringExpense? getTemplateById(String templateId) {
    try {
      return state.templates.firstWhere((t) => t.id == templateId);
    } catch (_) {
      return null;
    }
  }
}

/// Provider for recurring expense list state
final recurringExpenseListProvider = StateNotifierProvider<
    RecurringExpenseListNotifier, RecurringExpenseListState>((ref) {
  // Refresh when auth changes
  ref.watch(authProvider);
  return RecurringExpenseListNotifier(
      ref.watch(recurringExpenseRepositoryProvider));
});

/// Recurring expense form state
enum RecurringExpenseFormStatus {
  initial,
  submitting,
  success,
  error,
}

/// Recurring expense form state class
class RecurringExpenseFormState {
  const RecurringExpenseFormState({
    this.status = RecurringExpenseFormStatus.initial,
    this.template,
    this.errorMessage,
  });

  final RecurringExpenseFormStatus status;
  final RecurringExpense? template;
  final String? errorMessage;

  RecurringExpenseFormState copyWith({
    RecurringExpenseFormStatus? status,
    RecurringExpense? template,
    String? errorMessage,
  }) {
    return RecurringExpenseFormState(
      status: status ?? this.status,
      template: template ?? this.template,
      errorMessage: errorMessage,
    );
  }

  bool get isSubmitting => status == RecurringExpenseFormStatus.submitting;
  bool get isSuccess => status == RecurringExpenseFormStatus.success;
  bool get hasError => status == RecurringExpenseFormStatus.error;
}

/// Recurring expense form notifier
class RecurringExpenseFormNotifier
    extends StateNotifier<RecurringExpenseFormState> {
  RecurringExpenseFormNotifier(this._recurringExpenseRepository)
      : super(const RecurringExpenseFormState());

  final RecurringExpenseRepository _recurringExpenseRepository;

  /// Create a new recurring expense template
  Future<RecurringExpense?> createRecurringExpense({
    required double amount,
    required String categoryId,
    required String categoryName,
    required RecurrenceFrequency frequency,
    required DateTime anchorDate,
    String? merchant,
    String? notes,
    bool isGroupExpense = true,
    bool budgetReservationEnabled = false,
    ReimbursementStatus defaultReimbursementStatus = ReimbursementStatus.none,
    String? paymentMethodId,
    String? paymentMethodName,
    String? templateExpenseId,
  }) async {
    state = state.copyWith(
        status: RecurringExpenseFormStatus.submitting, errorMessage: null);

    final result =
        await _recurringExpenseRepository.createRecurringExpense(
      amount: amount,
      categoryId: categoryId,
      categoryName: categoryName,
      frequency: frequency,
      anchorDate: anchorDate,
      merchant: merchant,
      notes: notes,
      isGroupExpense: isGroupExpense,
      budgetReservationEnabled: budgetReservationEnabled,
      defaultReimbursementStatus: defaultReimbursementStatus,
      paymentMethodId: paymentMethodId,
      paymentMethodName: paymentMethodName,
      templateExpenseId: templateExpenseId,
    );

    return result.fold(
      (failure) {
        state = state.copyWith(
          status: RecurringExpenseFormStatus.error,
          errorMessage: failure.message,
        );
        return null;
      },
      (template) {
        state = state.copyWith(
          status: RecurringExpenseFormStatus.success,
          template: template,
        );
        return template;
      },
    );
  }

  /// Update an existing recurring expense template
  Future<RecurringExpense?> updateRecurringExpense({
    required String id,
    double? amount,
    String? categoryId,
    String? categoryName,
    RecurrenceFrequency? frequency,
    String? merchant,
    String? notes,
    bool? budgetReservationEnabled,
    ReimbursementStatus? defaultReimbursementStatus,
    String? paymentMethodId,
    String? paymentMethodName,
  }) async {
    state = state.copyWith(
        status: RecurringExpenseFormStatus.submitting, errorMessage: null);

    final result =
        await _recurringExpenseRepository.updateRecurringExpense(
      id: id,
      amount: amount,
      categoryId: categoryId,
      categoryName: categoryName,
      frequency: frequency,
      merchant: merchant,
      notes: notes,
      budgetReservationEnabled: budgetReservationEnabled,
      defaultReimbursementStatus: defaultReimbursementStatus,
      paymentMethodId: paymentMethodId,
      paymentMethodName: paymentMethodName,
    );

    return result.fold(
      (failure) {
        state = state.copyWith(
          status: RecurringExpenseFormStatus.error,
          errorMessage: failure.message,
        );
        return null;
      },
      (template) {
        state = state.copyWith(
          status: RecurringExpenseFormStatus.success,
          template: template,
        );
        return template;
      },
    );
  }

  /// Pause a recurring expense template
  Future<RecurringExpense?> pauseRecurringExpense({
    required BuildContext context,
    required String id,
  }) async {
    state = state.copyWith(
        status: RecurringExpenseFormStatus.submitting, errorMessage: null);

    final result = await _recurringExpenseRepository.pauseRecurringExpense(
      id: id,
    );

    return result.fold(
      (failure) {
        state = state.copyWith(
          status: RecurringExpenseFormStatus.error,
          errorMessage: failure.message,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(failure.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return null;
      },
      (template) {
        state = state.copyWith(
          status: RecurringExpenseFormStatus.success,
          template: template,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Spesa ricorrente messa in pausa'),
            ),
          );
        }
        return template;
      },
    );
  }

  /// Resume a paused recurring expense template
  Future<RecurringExpense?> resumeRecurringExpense({
    required BuildContext context,
    required String id,
  }) async {
    state = state.copyWith(
        status: RecurringExpenseFormStatus.submitting, errorMessage: null);

    final result = await _recurringExpenseRepository.resumeRecurringExpense(
      id: id,
    );

    return result.fold(
      (failure) {
        state = state.copyWith(
          status: RecurringExpenseFormStatus.error,
          errorMessage: failure.message,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(failure.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return null;
      },
      (template) {
        state = state.copyWith(
          status: RecurringExpenseFormStatus.success,
          template: template,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Spesa ricorrente riattivata'),
            ),
          );
        }
        return template;
      },
    );
  }

  /// Delete a recurring expense template
  Future<bool> deleteRecurringExpense({
    required BuildContext context,
    required String id,
    bool deleteInstances = false,
  }) async {
    state = state.copyWith(
        status: RecurringExpenseFormStatus.submitting, errorMessage: null);

    final result = await _recurringExpenseRepository.deleteRecurringExpense(
      id: id,
      deleteInstances: deleteInstances,
    );

    return result.fold(
      (failure) {
        state = state.copyWith(
          status: RecurringExpenseFormStatus.error,
          errorMessage: failure.message,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(failure.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return false;
      },
      (_) {
        state = state.copyWith(status: RecurringExpenseFormStatus.success);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Spesa ricorrente eliminata'),
            ),
          );
        }
        return true;
      },
    );
  }

  /// Generate an expense instance from a template
  Future<ExpenseEntity?> generateExpenseInstance({
    required BuildContext context,
    required String recurringExpenseId,
    required DateTime scheduledDate,
  }) async {
    state = state.copyWith(
        status: RecurringExpenseFormStatus.submitting, errorMessage: null);

    final result =
        await _recurringExpenseRepository.generateExpenseInstance(
      recurringExpenseId: recurringExpenseId,
      scheduledDate: scheduledDate,
    );

    return result.fold(
      (failure) {
        state = state.copyWith(
          status: RecurringExpenseFormStatus.error,
          errorMessage: failure.message,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(failure.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return null;
      },
      (expense) {
        state = state.copyWith(status: RecurringExpenseFormStatus.success);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Spesa creata dalla ricorrenza'),
            ),
          );
        }
        return expense;
      },
    );
  }

  /// Reset form state
  void reset() {
    state = const RecurringExpenseFormState();
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}

/// Provider for recurring expense form state
final recurringExpenseFormProvider = StateNotifierProvider<
    RecurringExpenseFormNotifier, RecurringExpenseFormState>((ref) {
  return RecurringExpenseFormNotifier(
      ref.watch(recurringExpenseRepositoryProvider));
});

/// Provider for a single recurring expense template
final recurringExpenseProvider =
    FutureProvider.family<RecurringExpense?, String>((ref, templateId) async {
  final repository = ref.watch(recurringExpenseRepositoryProvider);
  final result = await repository.getRecurringExpense(id: templateId);
  return result.fold((_) => null, (template) => template);
});

/// Provider for instances of a recurring expense
final recurringExpenseInstancesProvider =
    FutureProvider.family<List<ExpenseEntity>, String>(
        (ref, recurringExpenseId) async {
  final repository = ref.watch(recurringExpenseRepositoryProvider);
  final result = await repository.getRecurringExpenseInstances(
      recurringExpenseId: recurringExpenseId);
  return result.fold(
    (_) => [],
    (expenses) => expenses,
  );
});

/// Provider for active recurring expenses (not paused)
final activeRecurringExpensesProvider =
    FutureProvider<List<RecurringExpense>>((ref) async {
  final repository = ref.watch(recurringExpenseRepositoryProvider);
  final result = await repository.getRecurringExpenses(isPaused: false);
  return result.fold(
    (_) => [],
    (templates) => templates,
  );
});

/// Provider for paused recurring expenses
final pausedRecurringExpensesProvider =
    FutureProvider<List<RecurringExpense>>((ref) async {
  final repository = ref.watch(recurringExpenseRepositoryProvider);
  final result = await repository.getRecurringExpenses(isPaused: true);
  return result.fold(
    (_) => [],
    (templates) => templates,
  );
});

/// Provider for recurring expenses with budget reservation enabled
final budgetReservationRecurringExpensesProvider =
    FutureProvider<List<RecurringExpense>>((ref) async {
  final repository = ref.watch(recurringExpenseRepositoryProvider);
  final result =
      await repository.getRecurringExpenses(budgetReservationEnabled: true);
  return result.fold(
    (_) => [],
    (templates) => templates,
  );
});
