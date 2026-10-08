import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../dashboard/presentation/providers/dashboard_refresh.dart';
import '../../../expenses/presentation/providers/expense_provider.dart';
import '../../../expenses/presentation/widgets/category_selector.dart';
import '../providers/upload_provider.dart';

/// Screen for uploading file receipts and creating expenses.
class UploadFileScreen extends ConsumerStatefulWidget {
  const UploadFileScreen({super.key});

  @override
  ConsumerState<UploadFileScreen> createState() => _UploadFileScreenState();
}

class _UploadFileScreenState extends ConsumerState<UploadFileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String? _selectedCategoryId;

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    await ref.read(uploadProvider.notifier).pickFile();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final uploadState = ref.read(uploadProvider);
    if (!uploadState.hasFile) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleziona un file prima di salvare'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

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
      receiptImage: uploadState.fileBytes,
    );

    if (expense != null && mounted) {
      listNotifier.addExpense(expense);
      // Refresh dashboard to reflect the new expense
      refreshPersonalDashboard(ref);
      ref.read(uploadProvider.notifier).clearFile();
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
    final uploadState = ref.watch(uploadProvider);
    final formState = ref.watch(expenseFormProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            ref.read(uploadProvider.notifier).clearFile();
            context.go('/');
          },
        ),
        title: const Text('Carica file'),
        actions: [
          if (uploadState.hasFile)
            TextButton(
              onPressed: () {
                ref.read(uploadProvider.notifier).clearFile();
              },
              child: const Text('Rimuovi'),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Upload error message
              if (uploadState.hasError && uploadState.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: InlineError(message: uploadState.errorMessage!),
                ),

              // Form error message
              if (formState.hasError && formState.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: InlineError(message: formState.errorMessage!),
                ),

              // File picker / preview area
              _buildFileArea(theme, uploadState),

              const SizedBox(height: 24),

              // Amount field
              AmountTextField(
                controller: _amountController,
                validator: Validators.validateAmount,
                enabled: !formState.isSubmitting,
                autofocus: !uploadState.hasFile,
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
                onPressed: uploadState.hasFile ? _handleSave : null,
                label: 'Salva spesa',
                isLoading: formState.isSubmitting,
                loadingLabel: 'Salvataggio...',
                icon: Icons.check,
              ),

              const SizedBox(height: 16),

              // Or manual entry button
              SecondaryButton(
                onPressed: () {
                  ref.read(uploadProvider.notifier).clearFile();
                  context.go('/add-expense');
                },
                label: 'Inserimento manuale',
                icon: Icons.edit_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileArea(ThemeData theme, UploadState uploadState) {
    // File picker button when no file selected
    if (!uploadState.hasFile) {
      return _buildFilePickerButton(theme, uploadState);
    }

    // Show file preview based on type
    if (uploadState.isImage) {
      return _buildImagePreview(theme, uploadState);
    }

    // PDF file card
    return _buildPdfCard(theme, uploadState);
  }

  Widget _buildFilePickerButton(ThemeData theme, UploadState uploadState) {
    return InkWell(
      onTap: uploadState.isPicking ? null : _pickFile,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.5),
            width: 2,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(12),
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        ),
        child: Center(
          child: uploadState.isPicking
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.upload_file_outlined,
                      size: 48,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Tocca per selezionare un file',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'PDF, PNG, JPG (max 5 MB)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildImagePreview(ThemeData theme, UploadState uploadState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 150,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            image: DecorationImage(
              image: MemoryImage(uploadState.fileBytes!),
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildFileInfo(theme, uploadState),
      ],
    );
  }

  Widget _buildPdfCard(ThemeData theme, UploadState uploadState) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.picture_as_pdf,
              size: 32,
              color: Colors.red,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  uploadState.filename ?? 'File PDF',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${uploadState.fileSizeMB.toStringAsFixed(2)} MB',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              ref.read(uploadProvider.notifier).clearFile();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFileInfo(ThemeData theme, UploadState uploadState) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.image_outlined,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Text(
          uploadState.filename ?? 'Immagine',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(width: 8),
        Text(
          '(${uploadState.fileSizeMB.toStringAsFixed(2)} MB)',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
