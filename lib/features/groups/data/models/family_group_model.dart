import 'dart:convert';

import '../../domain/entities/family_group_entity.dart';

/// Family group model for JSON serialization/deserialization.
///
/// Maps to the 'family_groups' table in Supabase.
class FamilyGroupModel extends FamilyGroupEntity {
  const FamilyGroupModel({
    required super.id,
    required super.name,
    required super.createdBy,
    super.createdAt,
    super.updatedAt,
    super.memberCount,
  });

  /// Create a FamilyGroupModel from a JSON map (family_groups table row).
  factory FamilyGroupModel.fromJson(Map<String, dynamic> json) {
    return FamilyGroupModel(
      id: json['id'] as String,
      name: json['name'] as String,
      createdBy: json['created_by'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      memberCount: json['member_count'] as int? ?? 0,
    );
  }

  /// Convert to JSON map for database operations.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'created_by': createdBy,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'member_count': memberCount,
    };
  }

  /// Convert to JSON string for caching
  String toJsonString() {
    return jsonEncode(toJson());
  }

  /// Create from JSON string for caching
  factory FamilyGroupModel.fromJsonString(String jsonString) {
    return FamilyGroupModel.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  /// Create a FamilyGroupModel from a FamilyGroupEntity.
  factory FamilyGroupModel.fromEntity(FamilyGroupEntity entity) {
    return FamilyGroupModel(
      id: entity.id,
      name: entity.name,
      createdBy: entity.createdBy,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      memberCount: entity.memberCount,
    );
  }

  /// Convert to FamilyGroupEntity.
  FamilyGroupEntity toEntity() {
    return FamilyGroupEntity(
      id: id,
      name: name,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
      memberCount: memberCount,
    );
  }

  /// Create a copy with updated fields.
  @override
  FamilyGroupModel copyWith({
    String? id,
    String? name,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? memberCount,
  }) {
    return FamilyGroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      memberCount: memberCount ?? this.memberCount,
    );
  }
}
