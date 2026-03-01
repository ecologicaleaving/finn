import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/date_formatter.dart';
import '../../../../core/services/icon_matching_service.dart';
import '../../../../shared/widgets/reimbursement_status_badge.dart';
import '../../domain/entities/expense_entity.dart';

/// List item widget for displaying expense summary in a list.
class ExpenseListItem extends StatelessWidget {
  const ExpenseListItem({
    super.key,
    required this.expense,
    required this.onTap,
  });

  final ExpenseEntity expense;
  final VoidCallback onTap;

  String _formatRelativeDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final targetDate = DateTime(date.year, date.month, date.day);

    if (targetDate == today) {
      return 'Oggi';
    } else if (targetDate == yesterday) {
      return 'Ieri';
    } else {
      // Formato: gg/MM
      return DateFormat('dd/MM').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Prepara i valori da mostrare
    final merchant = expense.merchant ?? '';
    final notes = expense.notes ?? '';
    final category = expense.categoryName ?? 'N/A';
    final date = _formatRelativeDate(expense.date);
    final paymentMethod = expense.paymentMethodName ?? '';
    final paidBy = expense.isGroupExpense ? (expense.paidByName ?? '') : '';

    // Lista valori per layout a due colonne
    final List<_InfoItem> items = [];

    if (merchant.isNotEmpty) items.add(_InfoItem(Icons.store, merchant));
    items.add(_InfoItem(
      category.isNotEmpty
          ? IconMatchingService.getDefaultIconForCategory(category)
          : Icons.category,
      category,
    ));
    items.add(_InfoItem(Icons.calendar_today, date));
    if (paymentMethod.isNotEmpty) items.add(_InfoItem(Icons.payment, paymentMethod));
    if (paidBy.isNotEmpty) items.add(_InfoItem(Icons.person, paidBy));
    if (notes.isNotEmpty) items.add(_InfoItem(Icons.notes, notes));

    return InkWell(
      onTap: onTap,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Amount e badge su prima riga
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    expense.formattedAmount,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Row(
                    children: [
                      // Tipo spesa
                      Icon(
                        expense.isGroupExpense ? Icons.group : Icons.lock_person,
                        size: 16,
                        color: theme.colorScheme.secondary,
                      ),
                      const SizedBox(width: 4),
                      if (expense.hasReceipt)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.receipt_long,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      const SizedBox(width: 8),
                      ReimbursementStatusBadge(
                        status: expense.reimbursementStatus,
                        mode: ReimbursementBadgeMode.compact,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Layout a due colonne
              _buildTwoColumnLayout(theme, items),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTwoColumnLayout(ThemeData theme, List<_InfoItem> items) {
    final rows = <Widget>[];

    for (int i = 0; i < items.length; i += 2) {
      final leftItem = items[i];
      final rightItem = i + 1 < items.length ? items[i + 1] : null;

      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              // Colonna sinistra
              Expanded(
                child: _buildInfoCell(theme, leftItem),
              ),
              const SizedBox(width: 12),
              // Colonna destra
              Expanded(
                child: rightItem != null
                    ? _buildInfoCell(theme, rightItem)
                    : const SizedBox(),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: rows,
    );
  }

  Widget _buildInfoCell(ThemeData theme, _InfoItem item) {
    return Row(
      children: [
        Icon(
          item.icon,
          size: 15,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            item.value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

class _InfoItem {
  final IconData icon;
  final String value;

  _InfoItem(this.icon, this.value);
}

