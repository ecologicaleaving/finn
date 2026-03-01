import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/enums/recurrence_frequency.dart';
import '../../../../core/enums/reimbursement_status.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/navigation_guard.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../budgets/presentation/providers/budget_repository_provider.dart';
import '../../../categories/presentation/providers/category_provider.dart';
import '../../../categories/presentation/providers/category_repository_provider.dart';
import '../../../categories/presentation/widgets/budget_prompt_dialog.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../dashboard/presentation/widgets/expenses_chart_widget.dart';
import '../../../dashboard/presentation/widgets/personal_dashboard_view.dart';
import '../../../groups/presentation/providers/group_provider.dart';
import '../../../payment_methods/presentation/providers/payment_method_provider.dart';
import '../../domain/entities/expense_entity.dart';
import '../providers/expense_provider.dart';
import '../providers/recurring_expense_provider.dart';
import '../widgets/category_selector.dart';
import '../widgets/expense_type_toggle.dart';
import '../widgets/member_selector.dart';
import '../widgets/payment_method_selector.dart';
import '../widgets/recurring_expense_config_widget.dart';
import '../widgets/reimbursement_toggle.dart';

/// Screen for manual expense entry.
///
/// T016: Supports edit mode when expenseId is provided
class ManualExpenseScreen extends ConsumerStatefulWidget {
  const ManualExpenseScreen({
    super.key,
    this.expenseId, // T016: Optional expense ID for edit mode
  });

  final String? expenseId;

  @override
  ConsumerState<ManualExpenseScreen> createState() => _ManualExpenseScreenState();
}

class _ManualExpenseScreenState extends ConsumerState<ManualExpenseScreen>
    with UnsavedChangesGuard {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String? _selectedCategoryId; // Will be set when categories load
  String? _selectedPaymentMethodId; // Will be set to default Contanti
  bool _isGroupExpense = true; // Default to group expense
  ReimbursementStatus _selectedReimbursementStatus = ReimbursementStatus.none; // T035

  // T013: Member selection for admin creating expenses on behalf of members
  String? _selectedMemberIdForExpense; // null = current user, non-null = admin creating for member

  // T016: Edit mode tracking
  bool _isEditMode = false;
  ExpenseEntity? _originalExpense;
  DateTime? _originalUpdatedAt; // T019: For optimistic locking

  // Recurring expense configuration (T025)
  bool _isRecurring = false;
  RecurrenceFrequency _recurrenceFrequency = RecurrenceFrequency.monthly;
  bool _budgetReservationEnabled = false;

  // Track initial values for unsaved changes detection
  late final String _initialAmount;
  late final String _initialNotes;
  late final DateTime _initialDate;
  late final String? _initialCategoryId;
  late final String? _initialPaymentMethodId;
  late final bool _initialIsGroupExpense;
  late final ReimbursementStatus _initialReimbursementStatus; // T035
  late final bool _initialIsRecurring; // T025
  late final RecurrenceFrequency _initialRecurrenceFrequency; // T025
  late final bool _initialBudgetReservationEnabled; // T025

  @override
  void initState() {
    super.initState();

    // T016: Check if in edit mode
    _isEditMode = widget.expenseId != null;

    // Issue #6: Set default category SYNCHRONOUSLY before storing initial values.
    // ref.read is valid in ConsumerStatefulWidget.initState().
    // Fires before the first build() → first frame already shows the chip highlighted.
    // For async loading (categories not yet cached), ref.listen in build() handles it.
    if (!_isEditMode) {
      final groupId = ref.read(authProvider).user?.groupId;
      if (groupId != null) {
        final cats = ref.read(categoryProvider(groupId)).categories;
        if (cats.isNotEmpty) {
          _selectedCategoryId = cats.first.id;
        }
      }
    }

    // Store initial values AFTER setting defaults.
    // This prevents false "unsaved changes" detection when only the auto-selection fired.
    _initialAmount = _amountController.text;
    _initialNotes = _notesController.text;
    _initialDate = _selectedDate;
    _initialCategoryId = _selectedCategoryId; // captures auto-selected value
    _initialPaymentMethodId = _selectedPaymentMethodId;
    _initialIsGroupExpense = _isGroupExpense;
    _initialReimbursementStatus = _selectedReimbursementStatus; // T035
    _initialIsRecurring = _isRecurring; // T025
    _initialRecurrenceFrequency = _recurrenceFrequency; // T025
    _initialBudgetReservationEnabled = _budgetReservationEnabled; // T025

    // T010: Initialize payment method to default Contanti after first frame
    // T014: Initialize selected member to current user for admin
    // T016: Load expense data if in edit mode
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Get current user ID
      final userId = ref.read(currentUserIdProvider);

      // T016: Load expense data if editing
      if (_isEditMode && widget.expenseId != null) {
        await _loadExpenseForEditing(widget.expenseId!);
      } else {
        // T010: Set payment method to default Contanti if not already set (create mode only)
        final paymentMethodState = ref.read(paymentMethodProvider(userId));
        if (_selectedPaymentMethodId == null && paymentMethodState.defaultContanti != null) {
          setState(() {
            _selectedPaymentMethodId = paymentMethodState.defaultContanti!.id;
          });
        }

        // T014: Keep _selectedMemberIdForExpense as null when user creates expense for themselves
        // Only set it when admin explicitly selects another member
      }
    });
  }

  /// T016: Load expense data for editing
  Future<void> _loadExpenseForEditing(String expenseId) async {
    final repository = ref.read(expenseRepositoryProvider);
    final result = await repository.getExpense(expenseId: expenseId);

    result.fold(
      (failure) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Errore nel caricamento della spesa: ${failure.message}'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          // Navigate back on error
          context.pop();
        }
      },
      (expense) {
        if (mounted) {
          setState(() {
            // Store original expense for reference
            _originalExpense = expense;
            _originalUpdatedAt = expense.updatedAt; // T019: For optimistic locking

            // Pre-populate form fields
            _amountController.text = expense.amount.toString();
            _selectedDate = expense.date;
            _selectedCategoryId = expense.categoryId;
            _selectedPaymentMethodId = expense.paymentMethodId;
            _notesController.text = expense.notes ?? '';
            _isGroupExpense = expense.isGroupExpense;
            _selectedReimbursementStatus = expense.reimbursementStatus;
            _selectedMemberIdForExpense = expense.createdBy; // Show who the expense is for
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  bool get hasUnsavedChanges {
    return _amountController.text != _initialAmount ||
        _notesController.text != _initialNotes ||
        _selectedDate != _initialDate ||
        _selectedCategoryId != _initialCategoryId ||
        _selectedPaymentMethodId != _initialPaymentMethodId ||
        _isGroupExpense != _initialIsGroupExpense ||
        _selectedReimbursementStatus != _initialReimbursementStatus || // T035
        _isRecurring != _initialIsRecurring || // T025
        _recurrenceFrequency != _initialRecurrenceFrequency || // T025
        _budgetReservationEnabled != _initialBudgetReservationEnabled; // T025
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = Validators.parseAmount(_amountController.text);
    if (amount == null) return;

    // Validate category is selected
    if (_selectedCategoryId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleziona una categoria')),
        );
      }
      return;
    }

    // Validate payment method is selected
    if (_selectedPaymentMethodId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seleziona un metodo di pagamento')),
        );
      }
      return;
    }

    // T018: Branch based on edit mode, recurring, or regular create
    if (_isEditMode) {
      await _updateExpense(amount);
    } else if (_isRecurring) {
      await _saveRecurringExpense(amount);
    } else {
      await _saveRegularExpense(amount);
    }
  }

  /// T018: Update an existing expense with optimistic locking
  Future<void> _updateExpense(double amount) async {
    if (_originalExpense == null || _originalUpdatedAt == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Errore: dati spesa originale mancanti')),
        );
      }
      return;
    }

    final formNotifier = ref.read(expenseFormProvider.notifier);
    final listNotifier = ref.read(expenseListProvider.notifier);
    final currentUserId = ref.read(currentUserIdProvider);

    final updatedExpense = await formNotifier.updateExpenseWithLock(
      expenseId: _originalExpense!.id,
      originalUpdatedAt: _originalUpdatedAt!,
      lastModifiedBy: currentUserId,
      amount: amount != _originalExpense!.amount ? amount : null,
      date: _selectedDate != _originalExpense!.date ? _selectedDate : null,
      categoryId: _selectedCategoryId != _originalExpense!.categoryId ? _selectedCategoryId : null,
      paymentMethodId: _selectedPaymentMethodId != _originalExpense!.paymentMethodId ? _selectedPaymentMethodId : null,
      notes: _notesController.text.trim() != (_originalExpense!.notes ?? '')
          ? (_notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null)
          : null,
      reimbursementStatus: _selectedReimbursementStatus != _originalExpense!.reimbursementStatus
          ? _selectedReimbursementStatus
          : null,
    );

    if (updatedExpense != null && mounted) {
      listNotifier.updateExpenseInList(updatedExpense);

      // Refresh dashboard to reflect the updated expense
      ref.read(dashboardProvider.notifier).refresh();

      // Invalidate all dashboard providers to refresh totals
      ref.invalidate(personalExpensesByCategoryProvider);
      ref.invalidate(expensesByPeriodProvider);
      ref.invalidate(recentPersonalExpensesProvider);
      ref.invalidate(groupMembersExpensesProvider);
      ref.invalidate(groupExpensesByCategoryProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Spesa aggiornata')),
        );
        context.pop(); // Return to previous screen
      }
    } else if (mounted) {
      // T020: Handle conflict error with Refresh action
      final formState = ref.read(expenseFormProvider);
      if (formState.hasError && formState.errorMessage != null) {
        final isConflict = formState.errorMessage!.contains('modificata da un altro utente');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(formState.errorMessage!),
            backgroundColor: Theme.of(context).colorScheme.error,
            action: isConflict
                ? SnackBarAction(
                    label: 'Ricarica',
                    textColor: Colors.white,
                    onPressed: () async {
                      // Reload expense data
                      await _loadExpenseForEditing(widget.expenseId!);
                    },
                  )
                : null,
            duration: isConflict ? const Duration(seconds: 10) : const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Save a regular (non-recurring) expense
  Future<void> _saveRegularExpense(double amount) async {
    final formNotifier = ref.read(expenseFormProvider.notifier);
    final listNotifier = ref.read(expenseListProvider.notifier);

    // T014: Get current user ID for lastModifiedBy
    final currentUserId = ref.read(currentUserIdProvider);

    final expense = await formNotifier.createExpense(
      amount: amount,
      date: _selectedDate,
      categoryId: _selectedCategoryId!,
      paymentMethodId: _selectedPaymentMethodId!,
      notes: _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
      isGroupExpense: _isGroupExpense,
      reimbursementStatus: _selectedReimbursementStatus, // T035
      // Always set created_by to current user (admin), even when creating for others
      // This ensures the expense appears in admin's "Le mie spese" list
      createdBy: currentUserId,
      // If admin selected "Me stesso" (null), use current user ID; otherwise use selected member ID
      paidBy: _selectedMemberIdForExpense ?? currentUserId,
      lastModifiedBy: currentUserId,
    );

    if (expense != null && mounted) {
      listNotifier.addExpense(expense);

      // Check for virgin category and show budget prompt (Feature 004: T041-T044)
      await _checkAndPromptForVirginCategory();

      // Refresh dashboard to reflect the new expense
      await ref.read(dashboardProvider.notifier).refresh();

      // Invalidate all dashboard providers to refresh totals
      ref.invalidate(personalExpensesByCategoryProvider);
      ref.invalidate(expensesByPeriodProvider);
      ref.invalidate(recentPersonalExpensesProvider);
      ref.invalidate(groupMembersExpensesProvider);
      ref.invalidate(groupExpensesByCategoryProvider);

      if (mounted) {
        context.pop(); // Return to previous screen
      }
    } else if (expense == null && mounted) {
      // Show error if expense creation failed
      final errorMessage = ref.read(expenseFormProvider).errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage ?? 'Errore durante il salvataggio della spesa'),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  /// Save a recurring expense template (T026)
  Future<void> _saveRecurringExpense(double amount) async {
    final recurringFormNotifier = ref.read(recurringExpenseFormProvider.notifier);
    final recurringListNotifier = ref.read(recurringExpenseListProvider.notifier);

    // Get category name for recurring expense
    final groupId = ref.read(currentGroupIdProvider);
    final categoriesState = ref.read(categoryProvider(groupId));
    String? categoryName;
    try {
      final category = categoriesState.categories.firstWhere(
        (cat) => cat.id == _selectedCategoryId,
      );
      categoryName = category.name;
    } catch (_) {
      categoryName = 'Unknown';
    }

    // Get payment method name if available
    String? paymentMethodName;
    // TODO: Get payment method name from payment method repository

    final template = await recurringFormNotifier.createRecurringExpense(
      amount: amount,
      categoryId: _selectedCategoryId!,
      categoryName: categoryName,
      frequency: _recurrenceFrequency,
      anchorDate: _selectedDate, // Use selected date as anchor
      notes: _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
      isGroupExpense: _isGroupExpense,
      budgetReservationEnabled: _budgetReservationEnabled,
      defaultReimbursementStatus: _selectedReimbursementStatus,
      paymentMethodId: _selectedPaymentMethodId,
      paymentMethodName: paymentMethodName,
    );

    if (template != null && mounted) {
      recurringListNotifier.addTemplate(template);

      // Check for virgin category and show budget prompt
      await _checkAndPromptForVirginCategory();

      // Refresh dashboard
      ref.read(dashboardProvider.notifier).refresh();
      ref.invalidate(personalExpensesByCategoryProvider);
      ref.invalidate(expensesByPeriodProvider);
      ref.invalidate(recentPersonalExpensesProvider);
      ref.invalidate(groupMembersExpensesProvider);
      ref.invalidate(groupExpensesByCategoryProvider);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Spesa ricorrente creata (${_recurrenceFrequency.displayString.toLowerCase()})',
            ),
          ),
        );
        context.pop(); // Return to previous screen
      }
    }
  }

  /// Check if this is the first time user uses this category, and show budget prompt if so.
  /// Feature 004: Virgin Category Prompts (T041-T044)
  Future<void> _checkAndPromptForVirginCategory() async {
    if (_selectedCategoryId == null || !mounted) return;

    final userId = ref.read(currentUserIdProvider);
    final categoryRepository = ref.read(categoryRepositoryProvider);
    final budgetRepository = ref.read(budgetRepositoryProvider);
    final groupId = ref.read(currentGroupIdProvider);

    // Check if user has used this category before (T041)
    final hasUsedResult = await categoryRepository.hasUserUsedCategory(
      userId: userId,
      categoryId: _selectedCategoryId!,
    );

    final hasUsed = hasUsedResult.fold(
      (failure) => true, // On error, assume used to avoid showing prompt
      (hasUsed) => hasUsed,
    );

    if (hasUsed) return; // Category already used, no prompt needed

    // Get category name for the prompt
    final categoriesState = ref.read(categoryProvider(groupId));
    try {
      final category = categoriesState.categories.firstWhere(
        (cat) => cat.id == _selectedCategoryId,
      );

      if (!mounted) return;

      // Show budget prompt dialog (T041, T042)
      await showBudgetPrompt(
        context: context,
        categoryName: category.name,
        onDecline: () {
          // User declined - do nothing (T042)
          // Could optionally use "Varie" budget, but spec says just track usage
        },
        onSetBudget: (amountInCents) async {
          // User set a budget - save it (T042)
          final now = DateTime.now();
          await budgetRepository.createCategoryBudget(
            categoryId: _selectedCategoryId!,
            groupId: groupId,
            amount: amountInCents,
            month: now.month,
            year: now.year,
          );
        },
      );

      // Mark category as used for this user (T043)
      await categoryRepository.markCategoryAsUsed(
        userId: userId,
        categoryId: _selectedCategoryId!,
      );

      // Refresh category budgets to show the new budget if created
      ref.invalidate(categoryProvider(groupId));
    } catch (e) {
      // Category not found or error occurred - skip prompt
      return;
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

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(expenseFormProvider);

    // Issue #6: Auto-select first category when categories load asynchronously (create mode only).
    // This covers the case where categories were NOT cached when initState ran.
    // Also updates _initialCategoryId to match so "unsaved changes" detection stays correct.
    if (!_isEditMode) {
      final authState = ref.watch(authProvider);
      final groupId = authState.user?.groupId;
      if (groupId != null) {
        ref.listen<CategoryState>(categoryProvider(groupId), (previous, next) {
          if (_selectedCategoryId == null && next.categories.isNotEmpty) {
            setState(() {
              _selectedCategoryId = next.categories.first.id;
              _initialCategoryId = next.categories.first.id; // keep initial in sync
            });
          }
        });
      }
    }

    // T021: Listen for admin demotion during edit mode
    if (_isEditMode) {
      ref.listen<bool>(isGroupAdminProvider, (previous, next) {
        // If admin status changed from true to false while editing
        if (previous == true && next == false && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Hai perso i privilegi di amministratore. Non puoi più modificare questa spesa.'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          // Navigate back
          context.pop();
        }
      });
    }

    return buildWithNavigationGuard(
      context,
      Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: Text(_isEditMode ? 'Modifica spesa' : 'Nuova spesa'), // T016
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

              // T013: Member selector for admin creating expenses on behalf of members
              MemberSelector(
                selectedMemberId: _selectedMemberIdForExpense,
                onChanged: (memberId) {
                  setState(() {
                    _selectedMemberIdForExpense = memberId;
                    // Force group expense when admin creates for another member
                    // This ensures the expense is visible to both admin and member
                    if (memberId != null) {
                      _isGroupExpense = true;
                    }
                  });
                },
                enabled: !formState.isSubmitting,
              ),
              const SizedBox(height: 16),

              // Amount field
              AmountTextField(
                controller: _amountController,
                validator: Validators.validateAmount,
                enabled: !formState.isSubmitting,
                autofocus: true,
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

              // Expense type toggle
              Text(
                'Tipo di spesa',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ExpenseTypeToggle(
                isGroupExpense: _isGroupExpense,
                onChanged: (value) {
                  setState(() {
                    _isGroupExpense = value;
                  });
                },
                // Disable toggle when admin creates for another member (must be group expense)
                enabled: !formState.isSubmitting && _selectedMemberIdForExpense == null,
              ),
              const SizedBox(height: 8),
              Text(
                _isGroupExpense
                    ? 'Visibile a tutti i membri del gruppo'
                    : 'Visibile solo a te',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),

              // Category selector (compact dropdown)
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
              Consumer(
                builder: (context, ref, child) {
                  final userId = ref.watch(currentUserIdProvider);
                  return PaymentMethodSelector(
                    userId: userId,
                    selectedId: _selectedPaymentMethodId,
                    onChanged: (paymentMethodId) {
                      setState(() {
                        _selectedPaymentMethodId = paymentMethodId;
                      });
                    },
                    enabled: !formState.isSubmitting,
                  );
                },
              ),
              const SizedBox(height: 16),

              // Reimbursement status toggle (T035)
              ReimbursementToggle(
                value: _selectedReimbursementStatus,
                onChanged: (status) {
                  setState(() {
                    _selectedReimbursementStatus = status;
                  });
                },
                enabled: !formState.isSubmitting,
              ),
              const SizedBox(height: 16),

              // Recurring expense configuration (T025)
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
                label: 'Salva spesa',
                isLoading: formState.isSubmitting,
                loadingLabel: 'Salvataggio...',
                icon: Icons.check,
              ),

              const SizedBox(height: 16),

              // Or scan button
              SecondaryButton(
                onPressed: () => context.go('/scan-receipt'),
                label: 'Scansiona scontrino',
                icon: Icons.document_scanner,
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
