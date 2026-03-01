import '../../domain/entities/expense_category_entity.dart';

/// Expense category model for JSON serialization/deserialization.
///
/// Maps to the 'expense_categories' table in Supabase.
class ExpenseCategoryModel extends ExpenseCategoryEntity {
  const ExpenseCategoryModel({
    required super.id,
    required super.name,
    required super.groupId,
    required super.isDefault,
    super.createdBy,
    required super.createdAt,
    required super.updatedAt,
    super.expenseCount,
    super.iconName,
  });

  /// Create an ExpenseCategoryModel from a JSON map (expense_categories table row).
  factory ExpenseCategoryModel.fromJson(Map<String, dynamic> json) {
    return ExpenseCategoryModel(
      id: json['id'] as String,
      name: json['name'] as String,
      groupId: json['group_id'] as String,
      isDefault: json['is_default'] as bool,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      expenseCount: json['expense_count'] as int?,
      iconName: json['icon_name'] as String?,
    );
  }

  /// Convert to JSON map for database operations.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'group_id': groupId,
      'is_default': isDefault,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (expenseCount != null) 'expense_count': expenseCount,
      if (iconName != null) 'icon_name': iconName,
    };
  }

  /// Create an ExpenseCategoryModel from an ExpenseCategoryEntity.
  factory ExpenseCategoryModel.fromEntity(ExpenseCategoryEntity entity) {
    return ExpenseCategoryModel(
      id: entity.id,
      name: entity.name,
      groupId: entity.groupId,
      isDefault: entity.isDefault,
      createdBy: entity.createdBy,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      expenseCount: entity.expenseCount,
      iconName: entity.iconName,
    );
  }

  /// Convert to ExpenseCategoryEntity.
  ExpenseCategoryEntity toEntity() {
    return ExpenseCategoryEntity(
      id: id,
      name: name,
      groupId: groupId,
      isDefault: isDefault,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
      expenseCount: expenseCount,
      iconName: iconName,
    );
  }

  /// Create a copy with updated fields.
  @override
  ExpenseCategoryModel copyWith({
    String? id,
    String? name,
    String? groupId,
    bool? isDefault,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? expenseCount,
    String? iconName,
  }) {
    return ExpenseCategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      groupId: groupId ?? this.groupId,
      isDefault: isDefault ?? this.isDefault,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expenseCount: expenseCount ?? this.expenseCount,
      iconName: iconName ?? this.iconName,
    );
  }
}
