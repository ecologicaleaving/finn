import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/enums/reimbursement_status.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../shared/widgets/receipt_image_viewer.dart';
import '../../../../shared/widgets/reimbursement_status_badge.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../dashboard/presentation/widgets/expenses_chart_widget.dart';
import '../../../dashboard/presentation/widgets/personal_dashboard_view.dart';
import '../../../groups/presentation/providers/group_provider.dart';
import '../providers/expense_provider.dart';
import '../providers/receipt_image_provider.dart';
import '../widgets/budget_context_widget.dart';
import '../widgets/delete_confirmation_dialog.dart';

/// Screen showing full expense details with receipt image.
class ExpenseDetailScreen extends ConsumerWidget {
  const ExpenseDetailScreen({
    super.key,
    required this.expenseId,
  });

  final String expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenseAsync = ref.watch(expenseProvider(expenseId));
    final currentUser = ref.watch(currentUserProvider);
    final isAdmin = ref.watch(isGroupAdminProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Dettaglio spesa'),
        actions: [
          expenseAsync.when(
            data: (expense) {
              if (expense == null) return const SizedBox.shrink();
              final canEdit = expense.canEdit(currentUser?.id ?? '', isAdmin);
              if (!canEdit) return const SizedBox.shrink();

              return PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'edit') {
                    context.go('/expense/${expense.id}/edit');
                  } else if (value == 'delete') {
                    await _handleDelete(context, ref);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit),
                        SizedBox(width: 8),
                        Text('Modifica'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Elimina', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: expenseAsync.when(
        data: (expense) {
          if (expense == null) {
            return const ErrorDisplay(
              message: 'Spesa non trovata',
              icon: Icons.error_outline,
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Amount card (T051)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          expense.formattedAmount,
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          expense.categoryName ?? 'Categoria non specificata',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        // Reimbursement status badge (T051)
                        ReimbursementStatusBadge(
                          status: expense.reimbursementStatus,
                          mode: ReimbursementBadgeMode.full,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Details card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _DetailRow(
                          icon: Icons.calendar_today,
                          label: 'Data',
                          value: DateFormatter.formatFullDate(expense.date),
                        ),
                        const Divider(),
                        if (expense.merchant != null) ...[
                          _DetailRow(
                            icon: Icons.store,
                            label: 'Negozio',
                            value: expense.merchant!,
                          ),
                          const Divider(),
                        ],
                        _DetailRow(
                          icon: Icons.person,
                          label: 'Inserito da',
                          value: expense.createdByName ?? 'Utente',
                        ),
                        const Divider(),
                        _DetailRow(
                          icon: Icons.account_circle,
                          label: 'Pagato da',
                          value: expense.paidByName ?? 'Non specificato',
                        ),
                        const Divider(),
                        _DetailRow(
                          icon: expense.isGroupExpense ? Icons.group : Icons.person_outline,
                          label: 'Tipo',
                          value: expense.isGroupExpense ? 'Spesa di gruppo' : 'Spesa personale',
                        ),
                        if (expense.paymentMethodName != null) ...[
                          const Divider(),
                          _DetailRow(
                            icon: Icons.payment,
                            label: 'Metodo di pagamento',
                            value: expense.paymentMethodName!,
                          ),
                        ],
                        // Recurring expense indicator (T029)
                        if (expense.isRecurringExpense) ...[
                          const Divider(),
                          _DetailRow(
                            icon: Icons.loop,
                            label: 'Ricorrenza',
                            value: expense.isRecurringInstance
                                ? 'Generata automaticamente'
                                : 'Spesa ricorrente',
                            iconColor: theme.colorScheme.tertiary,
                          ),
                        ],
                        if (expense.createdAt != null) ...[
                          const Divider(),
                          _DetailRow(
                            icon: Icons.access_time,
                            label: 'Creato',
                            value: DateFormatter.formatDateTime(expense.createdAt!),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // T022: Audit trail display (Feature 001-admin-expenses-cash-fix)
                if (expense.wasModified) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_note,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Consumer(
                              builder: (context, ref, _) {
                                // Get member names for display
                                final groupMembers = ref.watch(groupMembersProvider);
                                final memberNames = Map<String, String>.fromEntries(
                                  groupMembers.map((m) => MapEntry(m.userId, m.displayName)),
                                );

                                // Get current user ID
                                final currentUserId = ref.watch(currentUserIdProvider);

                                final modifierName = expense.getLastModifiedByName(
                                  currentUserId,
                                  memberNames,
                                );

                                return Text(
                                  modifierName.isNotEmpty
                                      ? 'Modificato da $modifierName'
                                      : 'Modificato',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Reimbursement status change section (T051)
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.account_balance_wallet_outlined, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Stato rimborso',
                              style: theme.textTheme.titleSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ReimbursementStatus.values.map((status) {
                            final isSelected = expense.reimbursementStatus == status;
                            final color = status.getColor(theme.colorScheme);

                            return FilterChip(
                              selected: isSelected,
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(status.icon, size: 16),
                                  const SizedBox(width: 4),
                                  Text(status.label),
                                ],
                              ),
                              selectedColor: color.withOpacity(0.2),
                              checkmarkColor: color,
                              onSelected: (selected) {
                                if (selected && !isSelected) {
                                  ref.read(expenseListProvider.notifier).updateReimbursementStatus(
                                    context: context,
                                    expenseId: expense.id,
                                    newStatus: status,
                                  );
                                }
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),

                // Notes
                if (expense.notes != null && expense.notes!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.notes, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Note',
                                style: theme.textTheme.titleSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(expense.notes!),
                        ],
                      ),
                    ),
                  ),
                ],

                // Budget context widget (Feature 004: T060-T065)
                const SizedBox(height: 16),
                BudgetContextWidget(
                  categoryId: expense.categoryId,
                  categoryName: expense.categoryName,
                  expenseAmount: (expense.amount * 100).toInt(), // Convert EUR to cents
                  expenseDate: expense.date,
                ),

                // Receipt image
                if (expense.hasReceipt) ...[
                  const SizedBox(height: 16),
                  _ReceiptImageSection(receiptPath: expense.receiptUrl!),
                ],
              ],
            ),
          );
        },
        loading: () => const LoadingIndicator(message: 'Caricamento...'),
        error: (error, _) => ErrorDisplay(
          message: error.toString(),
          onRetry: () => ref.invalidate(expenseProvider(expenseId)),
        ),
      ),
    );
  }

  Future<void> _handleDelete(BuildContext context, WidgetRef ref) async {
    // Get the expense to check if it's reimbursable
    final expenseAsync = await ref.read(expenseProvider(expenseId).future);
    if (expenseAsync == null) return;

    // Show confirmation dialog with reimbursement warning if applicable (T016-T017)
    final confirmed = await DeleteConfirmationDialog.show(
      context,
      expenseName: expenseAsync.merchant ?? expenseAsync.formattedAmount,
      isReimbursable: expenseAsync.isPendingReimbursement,
    );

    // Only proceed with deletion if dialog returns true (user confirmed) (T018)
    if (confirmed == true) {
      final success = await ref.read(expenseFormProvider.notifier).deleteExpense(
            expenseId: expenseId,
          );

      if (success && context.mounted) {
        ref.read(expenseListProvider.notifier).removeExpenseFromList(expenseId);

        // Invalidate providers to refresh totals
        ref.invalidate(recentGroupExpensesProvider);
        ref.invalidate(recentPersonalExpensesProvider);
        ref.invalidate(personalExpensesByCategoryProvider);
        ref.invalidate(expensesByPeriodProvider);
        ref.invalidate(groupMembersExpensesProvider);
        ref.invalidate(groupExpensesByCategoryProvider);
        ref.read(dashboardProvider.notifier).refresh();

        context.pop();
      }
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: iconColor ?? theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptImageSection extends ConsumerWidget {
  const _ReceiptImageSection({required this.receiptPath});

  final String receiptPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final receiptUrlAsync = ref.watch(receiptImageUrlProvider(receiptPath));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Scontrino',
                  style: theme.textTheme.titleSmall,
                ),
                const Spacer(),
                Text(
                  'Tocca per ingrandire',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            receiptUrlAsync.when(
              data: (imageUrl) => _ReceiptPreview(imageUrl: imageUrl),
              loading: () => _ReceiptPlaceholder(
                theme: theme,
                child: const LoadingIndicator(
                  message: 'Caricamento...',
                ),
              ),
              error: (error, _) => _ReceiptPlaceholder(
                theme: theme,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.image_not_supported_outlined,
                      size: 48,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Impossibile caricare',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => ref.invalidate(receiptImageUrlProvider(receiptPath)),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Riprova'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder container for loading and error states.
class _ReceiptPlaceholder extends StatelessWidget {
  const _ReceiptPlaceholder({
    required this.theme,
    required this.child,
  });

  final ThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

/// Receipt image preview that opens full-screen viewer on tap.
class _ReceiptPreview extends StatelessWidget {
  const _ReceiptPreview({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => ReceiptImageViewerNavigation.show(context, imageUrl),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 200,
          width: double.infinity,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) {
                    return child;
                  }
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.broken_image_outlined,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Immagine non disponibile',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              // Zoom hint overlay at bottom
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.6),
                      ],
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.zoom_in,
                        size: 16,
                        color: Colors.white,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Tocca per vedere',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
