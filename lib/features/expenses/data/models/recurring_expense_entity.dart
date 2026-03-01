import 'package:drift/drift.dart';
import '../../../../core/database/drift/tables/recurring_expenses_table.dart';
import '../../../../core/enums/recurrence_frequency.dart';
import '../../../../core/enums/reimbursement_status.dart';
import '../../domain/entities/recurring_expense.dart';
import '../../../offline/data/local/offline_database.dart';

/// Data model for RecurringExpense with conversion methods
///
/// Handles transformation between:
/// - Domain entity (RecurringExpense)
/// - Drift database (RecurringExpenseData)
/// - JSON (Supabase API)
class RecurringExpenseEntity extends RecurringExpense {
  const RecurringExpenseEntity({
    required super.id,
    required super.userId,
    super.groupId,
    super.templateExpenseId,
    required super.amount,
    required super.categoryId,
    required super.categoryName,
    super.merchant,
    super.notes,
    required super.isGroupExpense,
    required super.frequency,
    required super.anchorDate,
    required super.isPaused,
    super.lastInstanceCreatedAt,
    super.nextDueDate,
    required super.budgetReservationEnabled,
    required super.defaultReimbursementStatus,
    super.paymentMethodId,
    super.paymentMethodName,
    required super.createdAt,
    required super.updatedAt,
  });

  /// Create from domain entity
  factory RecurringExpenseEntity.fromDomain(RecurringExpense entity) {
    return RecurringExpenseEntity(
      id: entity.id,
      userId: entity.userId,
      groupId: entity.groupId,
      templateExpenseId: entity.templateExpenseId,
      amount: entity.amount,
      categoryId: entity.categoryId,
      categoryName: entity.categoryName,
      merchant: entity.merchant,
      notes: entity.notes,
      isGroupExpense: entity.isGroupExpense,
      frequency: entity.frequency,
      anchorDate: entity.anchorDate,
      isPaused: entity.isPaused,
      lastInstanceCreatedAt: entity.lastInstanceCreatedAt,
      nextDueDate: entity.nextDueDate,
      budgetReservationEnabled: entity.budgetReservationEnabled,
      defaultReimbursementStatus: entity.defaultReimbursementStatus,
      paymentMethodId: entity.paymentMethodId,
      paymentMethodName: entity.paymentMethodName,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }

  /// Create from Drift database row
  factory RecurringExpenseEntity.fromDrift(RecurringExpenseData data) {
    return RecurringExpenseEntity(
      id: data.id,
      userId: data.userId,
      groupId: data.groupId,
      templateExpenseId: data.templateExpenseId,
      amount: data.amount,
      categoryId: data.categoryId,
      categoryName: data.categoryName,
      merchant: data.merchant,
      notes: data.notes,
      isGroupExpense: data.isGroupExpense,
      frequency: data.frequency,
      anchorDate: data.anchorDate,
      isPaused: data.isPaused,
      lastInstanceCreatedAt: data.lastInstanceCreatedAt,
      nextDueDate: data.nextDueDate,
      budgetReservationEnabled: data.budgetReservationEnabled,
      defaultReimbursementStatus: data.defaultReimbursementStatus,
      paymentMethodId: data.paymentMethodId,
      paymentMethodName: data.paymentMethodName,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  /// Convert to Drift companion for insert/update operations
  RecurringExpensesCompanion toCompanion() {
    return RecurringExpensesCompanion(
      id: Value(id),
      userId: Value(userId),
      groupId: Value(groupId),
      templateExpenseId: Value(templateExpenseId),
      amount: Value(amount),
      categoryId: Value(categoryId),
      categoryName: Value(categoryName),
      merchant: Value(merchant),
      notes: Value(notes),
      isGroupExpense: Value(isGroupExpense),
      frequency: Value(frequency),
      anchorDate: Value(anchorDate),
      isPaused: Value(isPaused),
      lastInstanceCreatedAt: Value(lastInstanceCreatedAt),
      nextDueDate: Value(nextDueDate),
      budgetReservationEnabled: Value(budgetReservationEnabled),
      defaultReimbursementStatus: Value(defaultReimbursementStatus),
      paymentMethodId: Value(paymentMethodId),
      paymentMethodName: Value(paymentMethodName),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  /// Create from JSON (Supabase API response)
  factory RecurringExpenseEntity.fromJson(Map<String, dynamic> json) {
    return RecurringExpenseEntity(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      groupId: json['group_id'] as String?,
      templateExpenseId: json['template_expense_id'] as String?,
      amount: (json['amount'] as num).toDouble(),
      categoryId: json['category_id'] as String,
      categoryName: json['category_name'] as String,
      merchant: json['merchant'] as String?,
      notes: json['notes'] as String?,
      isGroupExpense: json['is_group_expense'] as bool? ?? true,
      frequency: RecurrenceFrequency.fromString(json['frequency'] as String),
      anchorDate: DateTime.parse(json['anchor_date'] as String),
      isPaused: json['is_paused'] as bool? ?? false,
      lastInstanceCreatedAt: json['last_instance_created_at'] != null
          ? DateTime.parse(json['last_instance_created_at'] as String)
          : null,
      nextDueDate: json['next_due_date'] != null
          ? DateTime.parse(json['next_due_date'] as String)
          : null,
      budgetReservationEnabled:
          json['budget_reservation_enabled'] as bool? ?? false,
      defaultReimbursementStatus: ReimbursementStatus.fromString(
        json['default_reimbursement_status'] as String? ?? 'none',
      ),
      paymentMethodId: json['payment_method_id'] as String?,
      paymentMethodName: json['payment_method_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert to JSON (for Supabase API requests)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'group_id': groupId,
      'template_expense_id': templateExpenseId,
      'amount': amount,
      'category_id': categoryId,
      'category_name': categoryName,
      'merchant': merchant,
      'notes': notes,
      'is_group_expense': isGroupExpense,
      'frequency': frequency.toStorageString(),
      'anchor_date': anchorDate.toIso8601String(),
      'is_paused': isPaused,
      'last_instance_created_at': lastInstanceCreatedAt?.toIso8601String(),
      'next_due_date': nextDueDate?.toIso8601String(),
      'budget_reservation_enabled': budgetReservationEnabled,
      'default_reimbursement_status': defaultReimbursementStatus.value,
      'payment_method_id': paymentMethodId,
      'payment_method_name': paymentMethodName,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  @override
  RecurringExpenseEntity copyWith({
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
    return RecurringExpenseEntity(
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
}
