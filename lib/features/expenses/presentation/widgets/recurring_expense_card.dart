import 'package:flutter/material.dart';

import '../../../../core/services/icon_matching_service.dart';
import '../../domain/entities/recurring_expense.dart';

/// Card widget for displaying a recurring expense template
///
/// Feature 013-recurring-expenses - User Story 3 (T042-T044)
///
/// Shows:
/// - Amount, category, merchant
/// - Frequency and next due date
/// - Pause/Resume and Delete actions
/// - Budget reservation indicator
class RecurringExpenseCard extends StatelessWidget {
  const RecurringExpenseCard({
    super.key,
    required this.template,
    required this.onTap,
    this.onPauseResume,
    this.onDelete,
  });

  final RecurringExpense template;
  final VoidCallback onTap;
  final VoidCallback? onPauseResume;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Amount and actions
              Row(
                children: [
                  // Amount
                  Expanded(
                    child: Text(
                      template.formattedAmount,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),

                  // Pause/Resume button (T043)
                  if (onPauseResume != null)
                    IconButton(
                      icon: Icon(
                        template.isPaused ? Icons.play_arrow : Icons.pause,
                        color: template.isPaused
                            ? colorScheme.tertiary
                            : colorScheme.onSurfaceVariant,
                      ),
                      tooltip:
                          template.isPaused ? 'Riattiva' : 'Metti in pausa',
                      onPressed: onPauseResume,
                    ),

                  // Delete button (T044)
                  if (onDelete != null)
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: colorScheme.error,
                      ),
                      tooltip: 'Elimina',
                      onPressed: onDelete,
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Category and merchant
              Row(
                children: [
                  Icon(
                    IconMatchingService.getDefaultIconForCategory(
                      template.categoryName,
                    ),
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      template.categoryName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              if (template.merchant != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.store_outlined,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        template.merchant!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Frequency and status
              Row(
                children: [
                  // Frequency
                  Icon(
                    Icons.loop,
                    size: 16,
                    color: colorScheme.tertiary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    template.frequency.displayString,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.tertiary,
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Next due date (if active)
                  if (!template.isPaused && template.nextDueDate != null) ...[
                    Icon(
                      Icons.schedule,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatNextDueDate(template.nextDueDate!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],

                  const Spacer(),

                  // Status badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: template.isPaused
                          ? colorScheme.errorContainer
                          : colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      template.isPaused ? 'In pausa' : 'Attiva',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: template.isPaused
                            ? colorScheme.onErrorContainer
                            : colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              // Budget reservation indicator
              if (template.budgetReservationEnabled) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.savings_outlined,
                      size: 16,
                      color: colorScheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Riserva budget attiva',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.secondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Format next due date in a user-friendly way
  String _formatNextDueDate(DateTime date) {
    final now = DateTime.now();
    final difference = date.difference(now).inDays;

    if (difference == 0) return 'Oggi';
    if (difference == 1) return 'Domani';
    if (difference < 7) return 'Tra $difference giorni';

    // Format as DD/MM
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }
}
