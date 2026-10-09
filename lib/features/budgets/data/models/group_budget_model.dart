import '../../domain/entities/group_budget_entity.dart';

/// Group budget model for JSON serialization/deserialization.
///
/// Maps to the 'group_budgets' table in Supabase.
class GroupBudgetModel extends GroupBudgetEntity {
  const GroupBudgetModel({
    required super.id,
    required super.groupId,
    required super.amount,
    required super.month,
    required super.year,
    required super.createdBy,
    required super.createdAt,
    required super.updatedAt,
  });

  /// Create a GroupBudgetModel from a JSON map (group_budgets table row).
  factory GroupBudgetModel.fromJson(Map<String, dynamic> json) {
    return GroupBudgetModel(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      amount: json['amount'] as int,
      month: json['month'] as int,
      year: json['year'] as int,
      createdBy: json['created_by'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert to JSON map for database operations.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'group_id': groupId,
      'amount': amount,
      'month': month,
      'year': year,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Create a GroupBudgetModel from a GroupBudgetEntity.
  factory GroupBudgetModel.fromEntity(GroupBudgetEntity entity) {
    return GroupBudgetModel(
      id: entity.id,
      groupId: entity.groupId,
      amount: entity.amount,
      month: entity.month,
      year: entity.year,
      createdBy: entity.createdBy,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }

  /// Convert to GroupBudgetEntity.
  GroupBudgetEntity toEntity() {
    return GroupBudgetEntity(
      id: id,
      groupId: groupId,
      amount: amount,
      month: month,
      year: year,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Create a copy with updated fields.
  @override
  GroupBudgetModel copyWith({
    String? id,
    String? groupId,
    int? amount,
    int? month,
    int? year,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GroupBudgetModel(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      amount: amount ?? this.amount,
      month: month ?? this.month,
      year: year ?? this.year,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
