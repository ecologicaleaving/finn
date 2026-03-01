import 'package:equatable/equatable.dart';

import '../../../../core/enums/reimbursement_status.dart';

/// Expense entity representing a household expense.
class ExpenseEntity extends Equatable {
  const ExpenseEntity({
    required this.id,
    required this.groupId,
    required this.createdBy,
    required this.amount,
    required this.date,
    this.categoryId,
    this.categoryName,
    required this.paymentMethodId,
    this.paymentMethodName,
    this.isGroupExpense = true,
    this.merchant,
    this.notes,
    this.receiptUrl,
    this.createdByName,
    this.paidBy,
    this.paidByName,
    this.createdAt,
    this.updatedAt,
    this.reimbursementStatus = ReimbursementStatus.none,
    this.reimbursedAt,
    this.recurringExpenseId,
    this.isRecurringInstance = false,
    this.lastModifiedBy,
  });

  /// Unique expense identifier
  final String id;

  /// The family group this expense belongs to
  final String groupId;

  /// User ID of who created the expense
  final String createdBy;

  /// Expense amount in EUR
  final double amount;

  /// Date of the expense
  final DateTime date;

  /// Category ID (foreign key to expense_categories table) - nullable for orphaned expenses
  final String? categoryId;

  /// Category name for display (denormalized from expense_categories)
  final String? categoryName;

  /// Payment method ID (foreign key to payment_methods table)
  final String paymentMethodId;

  /// Payment method name for display (denormalized from payment_methods)
  final String? paymentMethodName;

  /// Expense classification: true for group expenses (visible to all), false for personal (visible only to creator)
  final bool isGroupExpense;

  /// Merchant/store name (optional)
  final String? merchant;

  /// Additional notes (optional)
  final String? notes;

  /// URL to receipt image in storage (optional)
  final String? receiptUrl;

  /// Display name of who created the expense (for display purposes)
  final String? createdByName;

  /// User ID of who paid for the expense
  final String? paidBy;

  /// Display name of who paid for the expense (for display purposes)
  final String? paidByName;

  /// When the expense was created
  final DateTime? createdAt;

  /// When the expense was last updated
  final DateTime? updatedAt;

  /// Reimbursement status (Feature 012-expense-improvements)
  final ReimbursementStatus reimbursementStatus;

  /// Timestamp when expense was marked as reimbursed (for period-based budget calculations)
  final DateTime? reimbursedAt;

  /// Reference to recurring expense template ID (Feature 013-recurring-expenses)
  final String? recurringExpenseId;

  /// Whether this expense was auto-generated from a recurring expense template
  final bool isRecurringInstance;

  /// User ID of who last modified the expense (for audit trail - Feature 001-admin-expenses-cash-fix)
  final String? lastModifiedBy;

  /// Check if the user can edit this expense
  bool canEdit(String userId, bool isAdmin) {
    return createdBy == userId || isAdmin;
  }

  /// Check if the user can delete this expense
  bool canDelete(String userId, bool isAdmin) {
    return createdBy == userId || isAdmin;
  }

  /// Get formatted amount string
  String get formattedAmount => '€${amount.toStringAsFixed(2)}';

  /// Check if this expense has a receipt attached
  bool get hasReceipt => receiptUrl != null && receiptUrl!.isNotEmpty;

  /// Whether this expense is part of a recurring expense (Feature 013-recurring-expenses)
  bool get isRecurringExpense =>
      recurringExpenseId != null && recurringExpenseId!.isNotEmpty;

  /// Whether this expense is pending reimbursement
  bool get isPendingReimbursement =>
      reimbursementStatus == ReimbursementStatus.reimbursable;

  /// Whether this expense has been reimbursed
  bool get isReimbursed =>
      reimbursementStatus == ReimbursementStatus.reimbursed;

  /// Check if expense was modified after creation (Feature 001-admin-expenses-cash-fix)
  bool get wasModified => lastModifiedBy != null && lastModifiedBy != createdBy;

  /// Get display name for last modifier (Feature 001-admin-expenses-cash-fix)
  /// Returns "You" if current user, actual name if available, or "(Removed User)" if user removed/unavailable
  String getLastModifiedByName(String currentUserId, Map<String, String> memberNames) {
    if (lastModifiedBy == null || lastModifiedBy == createdBy) {
      return ''; // Not modified after creation
    }
    if (lastModifiedBy == currentUserId) {
      return 'You';
    }
    return memberNames[lastModifiedBy] ?? '(Removed User)';
  }

  /// Human-readable reimbursement status label (Italian)
  String get reimbursementStatusLabel => reimbursementStatus.label;

  /// Check if transition to new status is allowed by business rules
  bool canTransitionTo(ReimbursementStatus newStatus) {
    switch (reimbursementStatus) {
      case ReimbursementStatus.none:
        return newStatus == ReimbursementStatus.reimbursable;

      case ReimbursementStatus.reimbursable:
        return newStatus == ReimbursementStatus.reimbursed ||
               newStatus == ReimbursementStatus.none;

      case ReimbursementStatus.reimbursed:
        // Can revert, but requires confirmation in UI layer
        return newStatus == ReimbursementStatus.reimbursable ||
               newStatus == ReimbursementStatus.none;
    }
  }

  /// Check if confirmation dialog is required for this transition
  bool requiresConfirmation(ReimbursementStatus newStatus) {
    return reimbursementStatus == ReimbursementStatus.reimbursed &&
           newStatus != ReimbursementStatus.reimbursed;
  }

  /// Create updated entity with new reimbursement status
  ExpenseEntity updateReimbursementStatus(ReimbursementStatus newStatus) {
    if (!canTransitionTo(newStatus)) {
      throw StateError(
        'Invalid transition from $reimbursementStatus to $newStatus',
      );
    }

    return copyWith(
      reimbursementStatus: newStatus,
      reimbursedAt: newStatus == ReimbursementStatus.reimbursed
          ? DateTime.now()  // Capture timestamp for period-based budget calc
          : null,           // Clear timestamp if reverting
      updatedAt: DateTime.now(),
    );
  }

  /// Check if user can change reimbursement status
  bool canChangeReimbursementStatus(String userId, bool isAdmin) {
    return canEdit(userId, isAdmin);
  }

  /// Create an empty expense (for initial state)
  factory ExpenseEntity.empty() {
    return ExpenseEntity(
      id: '',
      groupId: '',
      createdBy: '',
      amount: 0,
      date: DateTime.now(),
      categoryId: null,
      categoryName: null,
      paymentMethodId: '',
      paymentMethodName: null,
    );
  }

  /// Check if this is an empty expense
  bool get isEmpty => id.isEmpty;

  /// Check if this is a valid expense
  bool get isNotEmpty => id.isNotEmpty;

  /// Create a copy with updated fields
  ExpenseEntity copyWith({
    String? id,
    String? groupId,
    String? createdBy,
    double? amount,
    DateTime? date,
    String? categoryId,
    String? categoryName,
    String? paymentMethodId,
    String? paymentMethodName,
    bool? isGroupExpense,
    String? merchant,
    String? notes,
    String? receiptUrl,
    String? createdByName,
    String? paidBy,
    String? paidByName,
    DateTime? createdAt,
    DateTime? updatedAt,
    ReimbursementStatus? reimbursementStatus,
    DateTime? reimbursedAt,
    String? recurringExpenseId,
    bool? isRecurringInstance,
    String? lastModifiedBy,
  }) {
    return ExpenseEntity(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      createdBy: createdBy ?? this.createdBy,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      paymentMethodName: paymentMethodName ?? this.paymentMethodName,
      isGroupExpense: isGroupExpense ?? this.isGroupExpense,
      merchant: merchant ?? this.merchant,
      notes: notes ?? this.notes,
      receiptUrl: receiptUrl ?? this.receiptUrl,
      createdByName: createdByName ?? this.createdByName,
      paidBy: paidBy ?? this.paidBy,
      paidByName: paidByName ?? this.paidByName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reimbursementStatus: reimbursementStatus ?? this.reimbursementStatus,
      reimbursedAt: reimbursedAt ?? this.reimbursedAt,
      recurringExpenseId: recurringExpenseId ?? this.recurringExpenseId,
      isRecurringInstance: isRecurringInstance ?? this.isRecurringInstance,
      lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
    );
  }

  @override
  List<Object?> get props => [
        id,
        groupId,
        createdBy,
        amount,
        date,
        categoryId,
        categoryName,
        paymentMethodId,
        paymentMethodName,
        isGroupExpense,
        merchant,
        notes,
        receiptUrl,
        createdByName,
        paidBy,
        paidByName,
        createdAt,
        updatedAt,
        reimbursementStatus,
        reimbursedAt,
        recurringExpenseId,
        isRecurringInstance,
        lastModifiedBy,
      ];

  @override
  String toString() {
    return 'ExpenseEntity(id: $id, amount: $formattedAmount, merchant: $merchant, category: $categoryName)';
  }
}
