import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../dashboard/presentation/providers/dashboard_refresh.dart';
import '../../../expenses/presentation/providers/expense_provider.dart';
import '../../../expenses/presentation/widgets/category_selector.dart';
import '../providers/scanner_provider.dart';

/// Screen for reviewing and editing scanned receipt data.
class ReviewScanScreen extends ConsumerStatefulWidget {
  const ReviewScanScreen({super.key});

  @override
  ConsumerState<ReviewScanScreen> createState() => _ReviewScanScreenState();
}

class _ReviewScanScreenState extends ConsumerState<ReviewScanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String? _selectedCategoryId;
  bool _hasInitialized = false;

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _initializeFromScanResult() {
    if (_hasInitialized) return;
    _hasInitialized = true;

    final scanState = ref.read(scannerProvider);

    // Start scanning if we have an image but no result yet
    if (scanState.hasCapturedImage && !scanState.hasScanResult && !scanState.isProcessing) {
      ref.read(scannerProvider.notifier).scanImage();
    }
  }

  void _populateFromScanResult() {
    final scanState = ref.read(scannerProvider);
    if (scanState.scanResult == null) return;

    final result = scanState.scanResult!;

    if (result.amount != null) {
      _amountController.text = result.amount!.toStringAsFixed(2).replaceAll('.', ',');
    }
    if (result.date != null) {
      _selectedDate = result.date!;
    }
    if (result.merchant != null) {
      _merchantController.text = result.merchant!;
    }
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

    final scanState = ref.read(scannerProvider);
    final formNotifier = ref.read(expenseFormProvider.notifier);
    final listNotifier = ref.read(expenseListProvider.notifier);

    final expense = await formNotifier.createExpense(
      amount: amount,
      date: _selectedDate,
      categoryId: _selectedCategoryId!,
      merchant: _merchantController.text.trim().isNotEmpty
          ? _merchantController.text.trim()
          : null,
      notes: _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
      receiptImage: scanState.capturedImage,
    );

    if (expense != null && mounted) {
      listNotifier.addExpense(expense);
      // Refresh dashboard to reflect the new expense
      refreshPersonalDashboard(ref);
      ref.read(scannerProvider.notifier).reset();
      context.go('/expenses');
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
    final scanState = ref.watch(scannerProvider);
    final formState = ref.watch(expenseFormProvider);
    final theme = Theme.of(context);

    // Initialize and start scan
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeFromScanResult();
    });

    // Populate form when scan completes
    ref.listen<ScannerState>(scannerProvider, (previous, next) {
      if (previous?.isProcessing == true && next.isSuccess) {
        _populateFromScanResult();
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            ref.read(scannerProvider.notifier).reset();
            context.go('/scan-receipt');
          },
        ),
        title: const Text('Verifica dati'),
        actions: [
          if (!scanState.isProcessing)
            TextButton(
              onPressed: () {
                ref.read(scannerProvider.notifier).reset();
                context.go('/add-expense');
              },
              child: const Text('Manuale'),
            ),
        ],
      ),
      body: _buildBody(theme, scanState, formState),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    ScannerState scanState,
    ExpenseFormState formState,
  ) {
    if (scanState.isProcessing) {
      return const Center(
        child: LoadingIndicator(
          message: 'Analisi dello scontrino...',
        ),
      );
    }

    if (scanState.hasError && scanState.errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ErrorDisplay(
              message: scanState.errorMessage!,
              title: 'Errore scansione',
              icon: Icons.document_scanner_outlined,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    onPressed: () => ref.read(scannerProvider.notifier).retryScan(),
                    label: 'Riprova',
                    icon: Icons.refresh,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: PrimaryButton(
                    onPressed: () {
                      ref.read(scannerProvider.notifier).reset();
                      context.go('/add-expense');
                    },
                    label: 'Inserisci manualmente',
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Scan confidence indicator
            if (scanState.scanResult != null)
              _buildConfidenceIndicator(theme, scanState.scanResult!.confidence),

            const SizedBox(height: 16),

            // Image preview
            if (scanState.capturedImage != null)
              Container(
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  image: DecorationImage(
                    image: MemoryImage(scanState.capturedImage!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),

            const SizedBox(height: 24),

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
          ],
        ),
      ),
    );
  }

  Widget _buildConfidenceIndicator(ThemeData theme, int confidence) {
    Color color;
    String label;
    IconData icon;

    if (confidence >= 70) {
      color = Colors.green;
      label = 'Alta precisione';
      icon = Icons.check_circle;
    } else if (confidence >= 40) {
      color = Colors.orange;
      label = 'Verifica i dati';
      icon = Icons.warning;
    } else {
      color = Colors.red;
      label = 'Bassa precisione';
      icon = Icons.error;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(
            '$label ($confidence%)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
