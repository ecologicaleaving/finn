import 'package:equatable/equatable.dart';
import '../../../../core/enums/recurrence_frequency.dart';
import '../../../../core/enums/reimbursement_status.dart';

/// Domain entity representing a recurring expense template.
///
/// This entity generates expense instances automatically on a schedule.
/// It follows the template pattern where the recurring expense acts as
/// a template that creates actual expense entries.
class RecurringExpense extends Equatable {
  /// Unique identifier (UUID)
  final String id;

  /// Creator/owner of recurring template
  final String userId;

  /// Family group for shared budgets (nullable)
  final String? groupId;

  /// Original expense that became recurring (nullable)
  final String? templateExpenseId;

  /// Expense amount in euros
  final double amount;

  /// Expense category ID
  final String categoryId;

  /// Category name (denormalized for offline access)
  final String categoryName;

  /// Merchant/vendor name (nullable)
  final String? merchant;

  /// Description/notes (nullable)
  final String? notes;

  /// Whether expense affects group budget
  final bool isGroupExpense;

  /// Recurrence frequency
  final RecurrenceFrequency frequency;

  /// Reference date for recurrence calculation
  final DateTime anchorDate;

  /// Whether instance generation is paused
  final bool isPaused;

  /// Last time an instance was generated (nullable)
  final DateTime? lastInstanceCreatedAt;

  /// Calculated next occurrence (nullable)
  final DateTime? nextDueDate;

  /// Whether to reserve budget for this expense
  final bool budgetReservationEnabled;

  /// Default reimbursement status for instances
  final ReimbursementStatus defaultReimbursementStatus;

  /// Payment method ID (nullable)
  final String? paymentMethodId;

  /// Payment method name (nullable)
  final String? paymentMethodName;

  /// Template creation timestamp
  final DateTime createdAt;

  /// Last modification timestamp
  final DateTime updatedAt;

  const RecurringExpense({
    required this.id,
    required this.userId,
    this.groupId,
    this.templateExpenseId,
    required this.amount,
    required this.categoryId,
    required this.categoryName,
    this.merchant,
    this.notes,
    required this.isGroupExpense,
    required this.frequency,
    required this.anchorDate,
    required this.isPaused,
    this.lastInstanceCreatedAt,
    this.nextDueDate,
    required this.budgetReservationEnabled,
    required this.defaultReimbursementStatus,
    this.paymentMethodId,
    this.paymentMethodName,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Returns true if this recurring expense is active (not paused)
  bool get isActive => !isPaused;

  /// Get formatted amount string
  String get formattedAmount => '€${amount.toStringAsFixed(2)}';

  /// Returns true if budget reservation is enabled and active
  bool get hasActiveBudgetReservation =>
      budgetReservationEnabled && !isPaused;

  /// Returns true if this is a personal expense (not group expense)
  bool get isPersonalExpense => !isGroupExpense;

  /// Creates a copy of this recurring expense with the given fields replaced
  RecurringExpense copyWith({
    String? id,
    String? userId,
    String? groupId,
    String? templateExpenseId,
    double? amount,
    String? categoryId,
    String? categoryName,
    String? merchant,
    String? notes,
    bool? isGroupExpense,
    RecurrenceFrequency? frequency,
    DateTime? anchorDate,
    bool? isPaused,
    DateTime? lastInstanceCreatedAt,
    DateTime? nextDueDate,
    bool? budgetReservationEnabled,
    ReimbursementStatus? defaultReimbursementStatus,
    String? paymentMethodId,
    String? paymentMethodName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RecurringExpense(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      groupId: groupId ?? this.groupId,
      templateExpenseId: templateExpenseId ?? this.templateExpenseId,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      merchant: merchant ?? this.merchant,
      notes: notes ?? this.notes,
      isGroupExpense: isGroupExpense ?? this.isGroupExpense,
      frequency: frequency ?? this.frequency,
      anchorDate: anchorDate ?? this.anchorDate,
      isPaused: isPaused ?? this.isPaused,
      lastInstanceCreatedAt:
          lastInstanceCreatedAt ?? this.lastInstanceCreatedAt,
      nextDueDate: nextDueDate ?? this.nextDueDate,
      budgetReservationEnabled:
          budgetReservationEnabled ?? this.budgetReservationEnabled,
      defaultReimbursementStatus:
          defaultReimbursementStatus ?? this.defaultReimbursementStatus,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      paymentMethodName: paymentMethodName ?? this.paymentMethodName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        groupId,
        templateExpenseId,
        amount,
        categoryId,
        categoryName,
        merchant,
        notes,
        isGroupExpense,
        frequency,
        anchorDate,
        isPaused,
        lastInstanceCreatedAt,
        nextDueDate,
        budgetReservationEnabled,
        defaultReimbursementStatus,
        paymentMethodId,
        paymentMethodName,
        createdAt,
        updatedAt,
      ];
}
