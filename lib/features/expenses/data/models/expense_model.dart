import '../../../../core/enums/reimbursement_status.dart';
import '../../domain/entities/expense_entity.dart';

/// Expense model for JSON serialization/deserialization.
///
/// Maps to the 'expenses' table in Supabase.
class ExpenseModel extends ExpenseEntity {
  const ExpenseModel({
    required super.id,
    required super.groupId,
    required super.createdBy,
    required super.amount,
    required super.date,
    super.categoryId,
    super.categoryName,
    required super.paymentMethodId,
    super.paymentMethodName,
    super.isGroupExpense = true,
    super.merchant,
    super.notes,
    super.receiptUrl,
    super.createdByName,
    super.paidBy,
    super.paidByName,
    super.createdAt,
    super.updatedAt,
    super.reimbursementStatus = ReimbursementStatus.none,
    super.reimbursedAt,
    super.recurringExpenseId,
    super.isRecurringInstance = false,
    super.lastModifiedBy,
  });

  /// Create an ExpenseModel from a JSON map (expenses table row).
  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    return ExpenseModel(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      createdBy: json['created_by'] as String,
      amount: (json['amount'] as num).toDouble(),
      date: DateTime.parse(json['date'] as String),
      categoryId: json['category_id'] as String?,
      categoryName: json['category_name'] as String?,
      paymentMethodId: json['payment_method_id'] as String,
      paymentMethodName: json['payment_method_name'] as String?,
      // Backward compatibility: default to true if field doesn't exist
      isGroupExpense: json['is_group_expense'] as bool? ?? true,
      merchant: json['merchant'] as String?,
      notes: json['notes'] as String?,
      receiptUrl: json['receipt_url'] as String?,
      createdByName: json['created_by_name'] as String?,
      paidBy: json['paid_by'] as String?,
      paidByName: json['paid_by_name'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      reimbursementStatus: ReimbursementStatus.fromString(
        json['reimbursement_status'] as String? ?? 'none',
      ),
      reimbursedAt: json['reimbursed_at'] != null
          ? DateTime.parse(json['reimbursed_at'] as String)
          : null,
      recurringExpenseId: json['recurring_expense_id'] as String?,
      isRecurringInstance: json['is_recurring_instance'] as bool? ?? false,
      lastModifiedBy: json['last_modified_by'] as String?,
    );
  }

  /// Convert to JSON map for database operations.
  Map<String, dynamic> toJson() {
    // Normalize date to UTC date only (no time component)
    final normalizedDate = DateTime.utc(date.year, date.month, date.day);

    return {
      'id': id,
      'group_id': groupId,
      'created_by': createdBy,
      'amount': amount,
      'date': normalizedDate.toIso8601String().split('T')[0],
      'category_id': categoryId,
      'payment_method_id': paymentMethodId,
      'payment_method_name': paymentMethodName,
      'is_group_expense': isGroupExpense,
      'merchant': merchant,
      'notes': notes,
      'receipt_url': receiptUrl,
      'paid_by': paidBy,
      'paid_by_name': paidByName,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'reimbursement_status': reimbursementStatus.value,
      'reimbursed_at': reimbursedAt?.toIso8601String(),
      'last_modified_by': lastModifiedBy,
    };
  }

  /// Create an ExpenseModel from an ExpenseEntity.
  factory ExpenseModel.fromEntity(ExpenseEntity entity) {
    return ExpenseModel(
      id: entity.id,
      groupId: entity.groupId,
      createdBy: entity.createdBy,
      amount: entity.amount,
      date: entity.date,
      categoryId: entity.categoryId,
      categoryName: entity.categoryName,
      paymentMethodId: entity.paymentMethodId,
      paymentMethodName: entity.paymentMethodName,
      isGroupExpense: entity.isGroupExpense,
      merchant: entity.merchant,
      notes: entity.notes,
      receiptUrl: entity.receiptUrl,
      createdByName: entity.createdByName,
      paidBy: entity.paidBy,
      paidByName: entity.paidByName,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      reimbursementStatus: entity.reimbursementStatus,
      reimbursedAt: entity.reimbursedAt,
      recurringExpenseId: entity.recurringExpenseId,
      isRecurringInstance: entity.isRecurringInstance,
      lastModifiedBy: entity.lastModifiedBy,
    );
  }

  /// Convert to ExpenseEntity.
  ExpenseEntity toEntity() {
    return ExpenseEntity(
      id: id,
      groupId: groupId,
      createdBy: createdBy,
      amount: amount,
      date: date,
      categoryId: categoryId,
      categoryName: categoryName,
      paymentMethodId: paymentMethodId,
      paymentMethodName: paymentMethodName,
      isGroupExpense: isGroupExpense,
      merchant: merchant,
      notes: notes,
      receiptUrl: receiptUrl,
      createdByName: createdByName,
      paidBy: paidBy,
      paidByName: paidByName,
      createdAt: createdAt,
      updatedAt: updatedAt,
      reimbursementStatus: reimbursementStatus,
      reimbursedAt: reimbursedAt,
      recurringExpenseId: recurringExpenseId,
      isRecurringInstance: isRecurringInstance,
      lastModifiedBy: lastModifiedBy,
    );
  }

  /// Create a copy with updated fields.
  @override
  ExpenseModel copyWith({
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
    return ExpenseModel(
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
}
