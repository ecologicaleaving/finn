import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/constants.dart';
import '../../../../core/enums/reimbursement_status.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../shared/widgets/navigation_guard.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../categories/presentation/providers/category_provider.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../dashboard/presentation/widgets/expenses_chart_widget.dart';
import '../../../dashboard/presentation/widgets/personal_dashboard_view.dart';
import '../../../groups/presentation/providers/group_provider.dart';
import '../../domain/entities/expense_entity.dart';
import '../providers/expense_provider.dart';
import '../widgets/category_selector.dart';
import '../widgets/payment_method_selector.dart';
import '../widgets/reimbursement_status_change_dialog.dart';
import '../widgets/reimbursement_toggle.dart';
import '../widgets/recurring_expense_config_widget.dart';
import '../providers/recurring_expense_provider.dart';
import '../../../../core/enums/recurrence_frequency.dart';

/// Screen for editing an existing expense.
/// Loads the expense by ID and displays an edit form.
class EditExpenseScreen extends ConsumerWidget {
  const EditExpenseScreen({
    super.key,
    required this.expenseId,
  });

  /// The ID of the expense to edit.
  final String expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenseAsync = ref.watch(expenseProvider(expenseId));

    return expenseAsync.when(
      data: (expense) {
        if (expense == null) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              title: const Text('Modifica spesa'),
            ),
            body: const ErrorDisplay(
              message: 'Spesa non trovata',
              icon: Icons.error_outline,
            ),
          );
        }
        return _EditExpenseForm(expense: expense);
      },
      loading: () => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          title: const Text('Modifica spesa'),
        ),
        body: const LoadingIndicator(message: 'Caricamento...'),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          title: const Text('Modifica spesa'),
        ),
        body: ErrorDisplay(
          message: error.toString(),
          onRetry: () => ref.invalidate(expenseProvider(expenseId)),
        ),
      ),
    );
  }
}

/// Internal form widget for editing expense.
class _EditExpenseForm extends ConsumerStatefulWidget {
  const _EditExpenseForm({
    required this.expense,
  });

  final ExpenseEntity expense;

  @override
  ConsumerState<_EditExpenseForm> createState() => _EditExpenseFormState();
}

class _EditExpenseFormState extends ConsumerState<_EditExpenseForm>
    with UnsavedChangesGuard {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _notesController = TextEditingController();
  late DateTime _selectedDate;
  String? _selectedCategoryId;
  String? _selectedPaymentMethodId;
  late bool _isGroupExpense;
  late ReimbursementStatus _selectedReimbursementStatus; // T036

  // Track initial values for unsaved changes detection
  late String _initialAmount;
  late String _initialMerchant;
  late String _initialNotes;
  late DateTime _initialDate;
  String? _initialCategoryId;
  String? _initialPaymentMethodId;
  late bool _initialIsGroupExpense;
  late ReimbursementStatus _initialReimbursementStatus; // T036

  // Recurring expense configuration
  bool _isRecurring = false;
  RecurrenceFrequency _recurrenceFrequency = RecurrenceFrequency.monthly;
  bool _budgetReservationEnabled = false;

  // Track initial values for unsaved changes detection
  late final bool _initialIsRecurring;
  late final RecurrenceFrequency _initialRecurrenceFrequency;
  late final bool _initialBudgetReservationEnabled;

  @override
  void initState() {
    super.initState();
    // Reset form provider state to ensure clean start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(expenseFormProvider.notifier).reset();
    });

    // Initialize form with existing expense data
    _amountController.text = widget.expense.amount.toStringAsFixed(2);
    _merchantController.text = widget.expense.merchant ?? '';
    _notesController.text = widget.expense.notes ?? '';
    _selectedDate = widget.expense.date;
    _selectedCategoryId = widget.expense.categoryId;
    _selectedPaymentMethodId = widget.expense.paymentMethodId;
    _isGroupExpense = widget.expense.isGroupExpense;
    _selectedReimbursementStatus = widget.expense.reimbursementStatus; // T036

    // Store initial values for change detection
    _initialAmount = _amountController.text;
    _initialMerchant = _merchantController.text;
    _initialNotes = _notesController.text;
    _initialDate = _selectedDate;
    _initialCategoryId = _selectedCategoryId;
    _initialPaymentMethodId = _selectedPaymentMethodId;
    _initialIsGroupExpense = _isGroupExpense;
    _initialReimbursementStatus = _selectedReimbursementStatus; // T036

    // Initialize recurring expense state (default: not recurring)
    _initialIsRecurring = false;
    _initialRecurrenceFrequency = RecurrenceFrequency.monthly;
    _initialBudgetReservationEnabled = false;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  bool get hasUnsavedChanges {
    return _amountController.text != _initialAmount ||
        _merchantController.text != _initialMerchant ||
        _notesController.text != _initialNotes ||
        _selectedDate != _initialDate ||
        _selectedCategoryId != _initialCategoryId ||
        _selectedPaymentMethodId != _initialPaymentMethodId ||
        _isGroupExpense != _initialIsGroupExpense ||
        _selectedReimbursementStatus != _initialReimbursementStatus || // T036
        _isRecurring != _initialIsRecurring ||
        _recurrenceFrequency != _initialRecurrenceFrequency ||
        _budgetReservationEnabled != _initialBudgetReservationEnabled;
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final amount = Validators.parseAmount(_amountController.text);
    if (amount == null) {
      return;
    }

    // Validate category and payment method
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona una categoria')),
      );
      return;
    }

    if (_selectedPaymentMethodId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona un metodo di pagamento')),
      );
      return;
    }

    // Branch based on recurring status
    if (_isRecurring) {
      // Convert to recurring expense
      await _saveAsRecurringExpense(amount);
    } else {
      // Update regular expense
      await _updateRegularExpense(amount);
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('it', 'IT'),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  /// Handle reimbursement status change with confirmation (T036)
  Future<void> _handleReimbursementStatusChange(ReimbursementStatus newStatus) async {
    // If status hasn't actually changed, just update without confirmation
    if (newStatus == _selectedReimbursementStatus) return;

    // Show confirmation dialog
    final confirmed = await ReimbursementStatusChangeDialog.show(
      context,
      expenseName: widget.expense.categoryName ?? 'Questa spesa',
      currentStatus: _selectedReimbursementStatus,
      newStatus: newStatus,
    );

    if (confirmed == true && mounted) {
      setState(() {
        _selectedReimbursementStatus = newStatus;
      });
    }
  }

  /// Convert this expense to a recurring template
  Future<void> _saveAsRecurringExpense(double amount) async {
    final recurringFormNotifier = ref.read(recurringExpenseFormProvider.notifier);
    final expenseListNotifier = ref.read(expenseListProvider.notifier);

    // Get category name
    final groupId = ref.read(currentGroupIdProvider);
    final categoriesState = ref.read(categoryProvider(groupId));
    String categoryName = 'Unknown';
    try {
      final category = categoriesState.categories.firstWhere(
        (cat) => cat.id == _selectedCategoryId,
      );
      categoryName = category.name;
    } catch (_) {}

    // Create recurring template
    final template = await recurringFormNotifier.createRecurringExpense(
      amount: amount,
      categoryId: _selectedCategoryId!,
      categoryName: categoryName,
      frequency: _recurrenceFrequency,
      anchorDate: _selectedDate,
      merchant: _merchantController.text.trim().isNotEmpty
          ? _merchantController.text.trim()
          : null,
      notes: _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
      isGroupExpense: _isGroupExpense,
      budgetReservationEnabled: _budgetReservationEnabled,
      defaultReimbursementStatus: _selectedReimbursementStatus,
      paymentMethodId: _selectedPaymentMethodId,
      templateExpenseId: widget.expense.id,
    );

    if (template != null && mounted) {
      // Delete original expense to avoid duplication
      final deleteResult = await ref.read(expenseRepositoryProvider).deleteExpense(
        expenseId: widget.expense.id,
      );

      deleteResult.fold(
        (failure) {
          // Deletion failed, show error
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Errore durante la conversione: ${failure.message}'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        },
        (_) {
          // Success: update providers
          expenseListNotifier.removeExpenseFromList(widget.expense.id);
          ref.invalidate(recentGroupExpensesProvider);
          ref.invalidate(recentPersonalExpensesProvider);
          ref.invalidate(personalExpensesByCategoryProvider);
          ref.invalidate(expensesByPeriodProvider);
          ref.invalidate(groupMembersExpensesProvider);
          ref.invalidate(groupExpensesByCategoryProvider);
          ref.read(dashboardProvider.notifier).refresh();

          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Spesa convertita in ricorrente (${_recurrenceFrequency.displayString.toLowerCase()})',
              ),
            ),
          );

          // Navigate home
          context.go('/');
        },
      );
    }
  }

  /// Update the expense with current form values
  Future<void> _updateRegularExpense(double amount) async {
    final formNotifier = ref.read(expenseFormProvider.notifier);
    final listNotifier = ref.read(expenseListProvider.notifier);

    var updatedExpense = await formNotifier.updateExpense(
      expenseId: widget.expense.id,
      amount: amount,
      date: _selectedDate,
      categoryId: _selectedCategoryId,
      paymentMethodId: _selectedPaymentMethodId,
      merchant: _merchantController.text.trim().isNotEmpty
          ? _merchantController.text.trim()
          : null,
      notes: _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
      reimbursementStatus: _selectedReimbursementStatus != _initialReimbursementStatus
          ? _selectedReimbursementStatus
          : null,
    );

    if (updatedExpense == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ref.read(expenseFormProvider).errorMessage ?? 'Errore durante il salvataggio'),
            backgroundColor: Theme.of(context).colorScheme.error,
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
      return;
    }

    // Update expense classification if changed
    if (_isGroupExpense != _initialIsGroupExpense) {
      updatedExpense = await formNotifier.updateExpenseClassification(
        expenseId: widget.expense.id,
        isGroupExpense: _isGroupExpense,
      );

      if (updatedExpense == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(ref.read(expenseFormProvider).errorMessage ?? 'Errore durante il salvataggio'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }
    }

    // Update list and navigate
    listNotifier.updateExpenseInList(updatedExpense);
    ref.invalidate(expenseProvider(widget.expense.id));
    ref.invalidate(recentGroupExpensesProvider);
    ref.invalidate(recentPersonalExpensesProvider);
    ref.invalidate(personalExpensesByCategoryProvider);
    ref.invalidate(expensesByPeriodProvider);
    ref.invalidate(groupMembersExpensesProvider);
    ref.invalidate(groupExpensesByCategoryProvider);
    ref.read(dashboardProvider.notifier).refresh();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Spesa aggiornata')),
      );

      // Wait for setState rebuild to complete before navigating back
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.mounted) {
          context.go('/expense/${widget.expense.id}');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(expenseFormProvider);

    return buildWithNavigationGuard(
      context,
      Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final shouldPop = await confirmDiscardChanges(context);
              if (shouldPop && mounted) {
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            },
          ),
          title: const Text('Modifica spesa'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Error message
                if (formState.hasError && formState.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: InlineError(message: formState.errorMessage!),
                  ),

                // Amount field
                AmountTextField(
                  controller: _amountController,
                  validator: Validators.validateAmount,
                  enabled: !formState.isSubmitting,
                  autofocus: false,
                ),
                const SizedBox(height: 16),

                // Date field
                InkWell(
                  onTap: formState.isSubmitting ? null : _selectDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Data',
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(DateFormatter.formatFullDate(_selectedDate)),
                  ),
                ),
                const SizedBox(height: 16),

                // Merchant field
                CustomTextField(
                  controller: _merchantController,
                  label: 'Negozio',
                  hint: 'Nome del negozio (opzionale)',
                  prefixIcon: Icons.store_outlined,
                  enabled: !formState.isSubmitting,
                  validator: Validators.validateMerchant,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),

                // Category dropdown (more compact)
                CategoryDropdown(
                  selectedCategoryId: _selectedCategoryId,
                  onCategorySelected: (categoryId) {
                    setState(() {
                      _selectedCategoryId = categoryId;
                    });
                  },
                  enabled: !formState.isSubmitting,
                ),
                const SizedBox(height: 16),

                // Payment method selector
                PaymentMethodSelector(
                  userId: ref.watch(currentUserIdProvider),
                  selectedId: _selectedPaymentMethodId,
                  onChanged: (paymentMethodId) {
                    setState(() {
                      _selectedPaymentMethodId = paymentMethodId;
                    });
                  },
                  enabled: !formState.isSubmitting,
                ),
                const SizedBox(height: 16),

                // Reimbursement status toggle (T036)
                ReimbursementToggle(
                  value: _selectedReimbursementStatus,
                  onChanged: _handleReimbursementStatusChange,
                  enabled: !formState.isSubmitting,
                ),
                const SizedBox(height: 16),

                // Recurring expense configuration (only for non-recurring instances)
                if (!widget.expense.isRecurringInstance) ...[
                  RecurringExpenseConfigWidget(
                    isRecurring: _isRecurring,
                    onRecurringChanged: (value) {
                      setState(() {
                        _isRecurring = value;
                      });
                    },
                    frequency: _recurrenceFrequency,
                    onFrequencyChanged: (freq) {
                      setState(() {
                        _recurrenceFrequency = freq;
                      });
                    },
                    budgetReservationEnabled: _budgetReservationEnabled,
                    onBudgetReservationChanged: (value) {
                      setState(() {
                        _budgetReservationEnabled = value;
                      });
                    },
                    enabled: !formState.isSubmitting,
                  ),
                  const SizedBox(height: 16),
                ],

                // Group/Personal toggle
                SwitchListTile(
                  title: const Text('Spesa di gruppo'),
                  subtitle: Text(
                    _isGroupExpense
                        ? 'Visibile a tutti i membri del gruppo'
                        : 'Visibile solo a te',
                  ),
                  value: _isGroupExpense,
                  onChanged: formState.isSubmitting
                      ? null
                      : (value) {
                          setState(() {
                            _isGroupExpense = value;
                          });
                        },
                  secondary: Icon(
                    _isGroupExpense ? Icons.group : Icons.person,
                  ),
                ),
                const SizedBox(height: 16),

                // Notes field
                CustomTextField(
                  controller: _notesController,
                  label: 'Note',
                  hint: 'Note aggiuntive (opzionale)',
                  prefixIcon: Icons.notes_outlined,
                  enabled: !formState.isSubmitting,
                  validator: Validators.validateNotes,
                  maxLines: 3,
                ),
                const SizedBox(height: 32),

                // Save button
                PrimaryButton(
                  onPressed: _handleSave,
                  label: 'Salva modifiche',
                  isLoading: formState.isSubmitting,
                  loadingLabel: 'Salvataggio...',
                  icon: Icons.check,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
