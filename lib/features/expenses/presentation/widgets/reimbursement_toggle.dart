import 'package:flutter/material.dart';
import '../../../../core/enums/reimbursement_status.dart';

/// Three-state toggle widget for selecting reimbursement status
///
/// Feature 012-expense-improvements - User Story 3 (T034)
///
/// Allows users to select between three reimbursement states:
/// - None: Regular expense (default)
/// - Reimbursable: Expense awaiting reimbursement
/// - Reimbursed: Expense that has been reimbursed
///
/// Used in expense creation and edit forms
class ReimbursementToggle extends StatelessWidget {
  const ReimbursementToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  /// Current reimbursement status
  final ReimbursementStatus value;

  /// Callback when status is changed
  final ValueChanged<ReimbursementStatus> onChanged;

  /// Whether the toggle is enabled
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
            // Header
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Stato rimborso',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Options
            ...ReimbursementStatus.values.map((status) {
              final isSelected = value == status;
              final color = status.getColor(colorScheme);

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: enabled ? () => onChanged(status) : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withOpacity(0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? color.withOpacity(0.5)
                            : colorScheme.outline.withOpacity(0.2),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Radio button
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? color
                                  : colorScheme.outline,
                              width: 2,
                            ),
                            color: isSelected
                                ? color
                                : Colors.transparent,
                          ),
                          child: isSelected
                              ? Center(
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: colorScheme.surface,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),

                        // Icon and label
                        Icon(
                          status.icon,
                          size: 20,
                          color: isSelected ? color : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                status.label,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? color
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _getDescription(status),
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
              );
            }),
          ],
        ),
      ),
    );
  }

  /// Get description for each status
  String _getDescription(ReimbursementStatus status) {
    switch (status) {
      case ReimbursementStatus.none:
        return 'Spesa normale (nessun rimborso previsto)';
      case ReimbursementStatus.reimbursable:
        return 'In attesa di rimborso da altri';
      case ReimbursementStatus.reimbursed:
        return 'Rimborso già ricevuto';
    }
  }
}
