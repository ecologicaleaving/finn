import '../../../../core/enums/reimbursement_status.dart';
import '../../domain/entities/expense_entity.dart';

/// Fields that changed while editing an expense (issue #48).
///
/// Only the fields that differ from the original expense are non-null, so the
/// optimistic-lock update sends a minimal payload.
class ExpenseEditChanges {
  const ExpenseEditChanges({
    this.amount,
    this.date,
    this.categoryId,
    this.paymentMethodId,
    this.notes,
    this.reimbursementStatus,
    this.isGroupExpense,
    this.paidBy,
  });

  /// Computes the changed fields between [original] and the current form values.
  ///
  /// [selectedMemberId] follows the member selector convention: `null` means
  /// "Me stesso" (the current user), otherwise the id of the member who paid.
  factory ExpenseEditChanges.compute({
    required ExpenseEntity original,
    required String currentUserId,
    required double amount,
    required DateTime date,
    required String? categoryId,
    required String? paymentMethodId,
    required String notes,
    required ReimbursementStatus reimbursementStatus,
    required bool isGroupExpense,
    required String? selectedMemberId,
  }) {
    final trimmedNotes = notes.trim();
    final newPaidBy = selectedMemberId ?? currentUserId;

    return ExpenseEditChanges(
      amount: amount != original.amount ? amount : null,
      date: date != original.date ? date : null,
      categoryId: categoryId != original.categoryId ? categoryId : null,
      paymentMethodId:
          paymentMethodId != original.paymentMethodId ? paymentMethodId : null,
      notes: trimmedNotes != (original.notes ?? '')
          ? (trimmedNotes.isNotEmpty ? trimmedNotes : null)
          : null,
      reimbursementStatus: reimbursementStatus != original.reimbursementStatus
          ? reimbursementStatus
          : null,
      isGroupExpense:
          isGroupExpense != original.isGroupExpense ? isGroupExpense : null,
      paidBy: newPaidBy != effectivePaidBy(original) ? newPaidBy : null,
    );
  }

  final double? amount;
  final DateTime? date;
  final String? categoryId;
  final String? paymentMethodId;
  final String? notes;
  final ReimbursementStatus? reimbursementStatus;
  final bool? isGroupExpense;
  final String? paidBy;

  /// Who paid the expense; legacy rows without `paid_by` fall back to the creator.
  static String effectivePaidBy(ExpenseEntity expense) =>
      expense.paidBy ?? expense.createdBy;

  /// Initial value of the member selector when editing [expense].
  ///
  /// Returns `null` ("Me stesso") when the current user paid, otherwise the
  /// id of the member who paid.
  static String? initialSelectedMemberId(
    ExpenseEntity expense,
    String currentUserId,
  ) {
    final paidBy = effectivePaidBy(expense);
    return paidBy == currentUserId ? null : paidBy;
  }
}
