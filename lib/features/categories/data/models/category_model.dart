// Data Model: Category Model extending CategoryEntity
// Feature: Italian Categories and Budget Management (004)
// Updated for Feature 001: Added MRU tracking fields
// Task: T018, T006

import '../../domain/entities/category_entity.dart';

class CategoryModel extends CategoryEntity {
  const CategoryModel({
    required super.id,
    required super.name,
    required super.groupId,
    required super.isDefault,
    super.createdBy,
    required super.createdAt,
    required super.updatedAt,
    super.lastUsedAt,
    super.useCount = 0,
  });

  /// Create CategoryModel from JSON (Supabase response)
  /// Supports MRU fields from LEFT JOIN with user_category_usage
  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    // Handle nested user_category_usage from LEFT JOIN
    final usageData = json['user_category_usage'];
    DateTime? lastUsedAt;
    int useCount = 0;

    if (usageData != null) {
      if (usageData is List && usageData.isNotEmpty) {
        // Handle array format from LEFT JOIN
        final firstUsage = usageData.first as Map<String, dynamic>;
        if (firstUsage['last_used_at'] != null) {
          lastUsedAt = DateTime.parse(firstUsage['last_used_at'] as String);
        }
        useCount = (firstUsage['use_count'] as int?) ?? 0;
      } else if (usageData is Map<String, dynamic>) {
        // Handle object format
        if (usageData['last_used_at'] != null) {
          lastUsedAt = DateTime.parse(usageData['last_used_at'] as String);
        }
        useCount = (usageData['use_count'] as int?) ?? 0;
      }
    }

    return CategoryModel(
      id: json['id'] as String,
      name: json['name'] as String,
      groupId: json['group_id'] as String,
      isDefault: json['is_default'] as bool,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      lastUsedAt: lastUsedAt,
      useCount: useCount,
    );
  }

  /// Convert CategoryModel to JSON (for Supabase insert/update)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'group_id': groupId,
      'is_default': isDefault,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      // Note: MRU fields not included in category table JSON
      // They are managed separately via user_category_usage table
    };
  }

  /// Create CategoryModel from CategoryEntity
  factory CategoryModel.fromEntity(CategoryEntity entity) {
    return CategoryModel(
      id: entity.id,
      name: entity.name,
      groupId: entity.groupId,
      isDefault: entity.isDefault,
      createdBy: entity.createdBy,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      lastUsedAt: entity.lastUsedAt,
      useCount: entity.useCount,
    );
  }
}
