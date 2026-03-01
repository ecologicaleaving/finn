import 'package:flutter/material.dart';
import '../../../../core/enums/recurrence_frequency.dart';

/// Widget for configuring recurring expense settings
///
/// Feature 013-recurring-expenses - User Story 1 (T025)
///
/// Allows users to:
/// - Toggle expense as recurring
/// - Select recurrence frequency (daily, weekly, monthly, yearly)
/// - Enable/disable budget reservation
///
/// Used in expense creation and edit forms
class RecurringExpenseConfigWidget extends StatelessWidget {
  const RecurringExpenseConfigWidget({
    super.key,
    required this.isRecurring,
    required this.onRecurringChanged,
    this.frequency = RecurrenceFrequency.monthly,
    required this.onFrequencyChanged,
    this.budgetReservationEnabled = false,
    required this.onBudgetReservationChanged,
    this.enabled = true,
  });

  /// Whether the expense is configured as recurring
  final bool isRecurring;

  /// Callback when recurring status changes
  final ValueChanged<bool> onRecurringChanged;

  /// Current recurrence frequency
  final RecurrenceFrequency frequency;

  /// Callback when frequency is changed
  final ValueChanged<RecurrenceFrequency> onFrequencyChanged;

  /// Whether budget reservation is enabled
  final bool budgetReservationEnabled;

  /// Callback when budget reservation status changes
  final ValueChanged<bool> onBudgetReservationChanged;

  /// Whether the widget is enabled
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outline.withOpacity(0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Recurring expense toggle
            InkWell(
              onTap: enabled ? () => onRecurringChanged(!isRecurring) : null,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Icon(
                    Icons.loop,
                    size: 20,
                    color: isRecurring
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Spesa ricorrente',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ripeti automaticamente questa spesa',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isRecurring,
                    onChanged: enabled ? onRecurringChanged : null,
                  ),
                ],
              ),
            ),

            // Frequency selector and budget reservation (shown when recurring is enabled)
            if (isRecurring) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Frequency selector
              Text(
                'Frequenza',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),

              // Frequency options
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: RecurrenceFrequency.values.map((freq) {
                  final isSelected = frequency == freq;
                  return ChoiceChip(
                    label: Text(freq.displayString),
                    selected: isSelected,
                    onSelected: enabled
                        ? (selected) {
                            if (selected) {
                              onFrequencyChanged(freq);
                            }
                          }
                        : null,
                    selectedColor: colorScheme.primaryContainer,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.outline.withOpacity(0.5),
                      width: isSelected ? 2 : 1,
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Budget reservation toggle
              InkWell(
                onTap: enabled
                    ? () =>
                        onBudgetReservationChanged(!budgetReservationEnabled)
                    : null,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: budgetReservationEnabled
                        ? colorScheme.primaryContainer.withOpacity(0.3)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: budgetReservationEnabled
                          ? colorScheme.primary.withOpacity(0.5)
                          : colorScheme.outline.withOpacity(0.2),
                      width: budgetReservationEnabled ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: budgetReservationEnabled,
                        onChanged: enabled
                            ? (value) => onBudgetReservationChanged(value ?? false)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Riserva budget',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: budgetReservationEnabled
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Sottrai l\'importo dal budget disponibile',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
