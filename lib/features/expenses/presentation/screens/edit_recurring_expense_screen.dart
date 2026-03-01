import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/enums/recurrence_frequency.dart';
import '../../../../core/enums/reimbursement_status.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../shared/widgets/navigation_guard.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../groups/presentation/providers/group_provider.dart';
import '../../../categories/presentation/providers/category_provider.dart';
import '../../domain/entities/recurring_expense.dart';
import '../providers/recurring_expense_provider.dart';
import '../widgets/category_selector.dart';
import '../widgets/payment_method_selector.dart';
import '../widgets/recurring_expense_config_widget.dart';
import '../widgets/reimbursement_toggle.dart';

/// Screen for editing an existing recurring expense template
///
/// Feature 013-recurring-expenses - User Story 1 (T027)
///
/// Allows editing:
/// - Amount, merchant, notes
/// - Category
/// - Frequency
/// - Budget reservation setting
/// - Default reimbursement status
class EditRecurringExpenseScreen extends ConsumerWidget {
  const EditRecurringExpenseScreen({
    super.key,
    required this.templateId,
  });

  /// The ID of the recurring expense template to edit
  final String templateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templateAsync = ref.watch(recurringExpenseProvider(templateId));

    return templateAsync.when(
      data: (template) {
        if (template == null) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              title: const Text('Modifica spesa ricorrente'),
            ),
            body: const ErrorDisplay(
              message: 'Spesa ricorrente non trovata',
              icon: Icons.error_outline,
            ),
          );
        }
        return _EditRecurringExpenseForm(template: template);
      },
      loading: () => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          title: const Text('Modifica spesa ricorrente'),
        ),
        body: const LoadingIndicator(message: 'Caricamento...'),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          title: const Text('Modifica spesa ricorrente'),
        ),
        body: ErrorDisplay(
          message: error.toString(),
          onRetry: () => ref.invalidate(recurringExpenseProvider(templateId)),
        ),
      ),
    );
  }
}

/// Internal form widget for editing recurring expense template
class _EditRecurringExpenseForm extends ConsumerStatefulWidget {
  const _EditRecurringExpenseForm({
    required this.template,
  });

  final RecurringExpense template;

  @override
  ConsumerState<_EditRecurringExpenseForm> createState() =>
      _EditRecurringExpenseFormState();
}

class _EditRecurringExpenseFormState
    extends ConsumerState<_EditRecurringExpenseForm>
    with UnsavedChangesGuard {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _notesController = TextEditingController();
  late DateTime _anchorDate;
  String? _selectedCategoryId;
  String? _selectedPaymentMethodId;
  late RecurrenceFrequency _recurrenceFrequency;
  late bool _budgetReservationEnabled;
  late ReimbursementStatus _defaultReimbursementStatus;

  // Track initial values for unsaved changes detection
  late String _initialAmount;
  late String _initialMerchant;
  late String _initialNotes;
  late DateTime _initialAnchorDate;
  String? _initialCategoryId;
  String? _initialPaymentMethodId;
  late RecurrenceFrequency _initialRecurrenceFrequency;
  late bool _initialBudgetReservationEnabled;
  late ReimbursementStatus _initialDefaultReimbursementStatus;

  @override
  void initState() {
    super.initState();
    // Reset form provider state to ensure clean start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(recurringExpenseFormProvider.notifier).reset();
    });

    // Initialize form with existing template data
    _amountController.text = widget.template.amount.toStringAsFixed(2);
    _merchantController.text = widget.template.merchant ?? '';
    _notesController.text = widget.template.notes ?? '';
    _anchorDate = widget.template.anchorDate;
    _selectedCategoryId = widget.template.categoryId;
    _selectedPaymentMethodId = widget.template.paymentMethodId;
    _recurrenceFrequency = widget.template.frequency;
    _budgetReservationEnabled = widget.template.budgetReservationEnabled;
    _defaultReimbursementStatus = widget.template.defaultReimbursementStatus;

    // Store initial values for change detection
    _initialAmount = _amountController.text;
    _initialMerchant = _merchantController.text;
    _initialNotes = _notesController.text;
    _initialAnchorDate = _anchorDate;
    _initialCategoryId = _selectedCategoryId;
    _initialPaymentMethodId = _selectedPaymentMethodId;
    _initialRecurrenceFrequency = _recurrenceFrequency;
    _initialBudgetReservationEnabled = _budgetReservationEnabled;
    _initialDefaultReimbursementStatus = _defaultReimbursementStatus;
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
        _anchorDate != _initialAnchorDate ||
        _selectedCategoryId != _initialCategoryId ||
        _selectedPaymentMethodId != _initialPaymentMethodId ||
        _recurrenceFrequency != _initialRecurrenceFrequency ||
        _budgetReservationEnabled != _initialBudgetReservationEnabled ||
        _defaultReimbursementStatus != _initialDefaultReimbursementStatus;
  }

  Future<void> _handleUpdate() async {
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

    final formNotifier = ref.read(recurringExpenseFormProvider.notifier);
    final listNotifier = ref.read(recurringExpenseListProvider.notifier);

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
      categoryName = widget.template.categoryName; // Keep original if not found
    }

    final updatedTemplate = await formNotifier.updateRecurringExpense(
      id: widget.template.id,
      amount: amount,
      categoryId: _selectedCategoryId!,
      categoryName: categoryName,
      frequency: _recurrenceFrequency,
      merchant: _merchantController.text.trim().isNotEmpty
          ? _merchantController.text.trim()
          : null,
      notes: _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
      budgetReservationEnabled: _budgetReservationEnabled,
      defaultReimbursementStatus: _defaultReimbursementStatus,
      paymentMethodId: _selectedPaymentMethodId,
    );

    if (updatedTemplate != null && mounted) {
      listNotifier.updateTemplateInList(updatedTemplate);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Spesa ricorrente aggiornata'),
          ),
        );
        context.pop(); // Return to previous screen
      }
    }
  }

  Future<void> _selectAnchorDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchorDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)), // Allow future dates for anchor
      locale: const Locale('it', 'IT'),
    );
    if (picked != null) {
      setState(() {
        _anchorDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(recurringExpenseFormProvider);
    final theme = Theme.of(context);

    return buildWithNavigationGuard(
      context,
      Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          title: const Text('Modifica spesa ricorrente'),
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
                  autofocus: true,
                ),
                const SizedBox(height: 16),

                // Anchor date field
                InkWell(
                  onTap: formState.isSubmitting ? null : _selectAnchorDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Data di riferimento',
                      prefixIcon: Icon(Icons.calendar_today),
                      helperText: 'Data da cui calcolare le ricorrenze',
                    ),
                    child: Text(DateFormatter.formatFullDate(_anchorDate)),
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

                // Category selector
                CategorySelector(
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

                // Reimbursement status toggle
                ReimbursementToggle(
                  value: _defaultReimbursementStatus,
                  onChanged: (status) {
                    setState(() {
                      _defaultReimbursementStatus = status;
                    });
                  },
                  enabled: !formState.isSubmitting,
                ),
                const SizedBox(height: 8),
                Text(
                  'Stato predefinito per le nuove istanze',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),

                // Recurring expense configuration
                RecurringExpenseConfigWidget(
                  isRecurring: true, // Always true in edit mode
                  onRecurringChanged: (_) {}, // Can't toggle off in edit mode
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

                // Update button
                PrimaryButton(
                  onPressed: _handleUpdate,
                  label: 'Aggiorna',
                  isLoading: formState.isSubmitting,
                  loadingLabel: 'Aggiornamento...',
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
