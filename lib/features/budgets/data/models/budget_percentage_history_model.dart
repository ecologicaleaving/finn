// Data Model: Budget Percentage History Model
// Feature: Italian Categories and Budget Management (004)

import '../../domain/entities/budget_percentage_history_entity.dart';

class BudgetPercentageHistoryModel extends BudgetPercentageHistoryEntity {
  const BudgetPercentageHistoryModel({
    required super.id,
    required super.categoryBudgetId,
    required super.userId,
    required super.categoryId,
    required super.groupId,
    required super.year,
    required super.month,
    required super.percentageValue,
    required super.groupBudgetAmount,
    required super.calculatedAmount,
    required super.changedAt,
    required super.changedBy,
    required super.createdAt,
  });

  /// Create BudgetPercentageHistoryModel from JSON (Supabase response)
  factory BudgetPercentageHistoryModel.fromJson(Map<String, dynamic> json) {
    return BudgetPercentageHistoryModel(
      id: json['id'] as String,
      categoryBudgetId: json['category_budget_id'] as String,
      userId: json['user_id'] as String,
      categoryId: json['category_id'] as String,
      groupId: json['group_id'] as String,
      year: json['year'] as int,
      month: json['month'] as int,
      percentageValue: (json['percentage_value'] as num).toDouble(),
      groupBudgetAmount: json['group_budget_amount'] as int,
      calculatedAmount: json['calculated_amount'] as int,
      changedAt: DateTime.parse(json['changed_at'] as String),
      changedBy: json['changed_by'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Convert BudgetPercentageHistoryModel to JSON (for Supabase insert)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category_budget_id': categoryBudgetId,
      'user_id': userId,
      'category_id': categoryId,
      'group_id': groupId,
      'year': year,
      'month': month,
      'percentage_value': percentageValue,
      'group_budget_amount': groupBudgetAmount,
      'calculated_amount': calculatedAmount,
      'changed_at': changedAt.toIso8601String(),
      'changed_by': changedBy,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Convert to BudgetPercentageHistoryEntity
  BudgetPercentageHistoryEntity toEntity() => this;

  /// Create BudgetPercentageHistoryModel from BudgetPercentageHistoryEntity
  factory BudgetPercentageHistoryModel.fromEntity(
    BudgetPercentageHistoryEntity entity,
  ) {
    return BudgetPercentageHistoryModel(
      id: entity.id,
      categoryBudgetId: entity.categoryBudgetId,
      userId: entity.userId,
      categoryId: entity.categoryId,
      groupId: entity.groupId,
      year: entity.year,
      month: entity.month,
      percentageValue: entity.percentageValue,
      groupBudgetAmount: entity.groupBudgetAmount,
      calculatedAmount: entity.calculatedAmount,
      changedAt: entity.changedAt,
      changedBy: entity.changedBy,
      createdAt: entity.createdAt,
    );
  }
}
