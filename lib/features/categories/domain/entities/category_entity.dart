// Domain Entity: Category Entity for Italian expense categories
// Feature: Italian Categories and Budget Management (004)
// Updated for Feature 001: Added MRU tracking fields
// Task: T012, T006

import 'package:equatable/equatable.dart';

class CategoryEntity extends Equatable {
  final String id;
  final String name; // Italian category name (Spesa, Benzina, etc.)
  final String groupId;
  final bool isDefault; // True for system-provided categories
  final String? createdBy; // NULL for default categories
  final DateTime createdAt;
  final DateTime updatedAt;

  // MRU (Most Recently Used) tracking fields - Feature 001
  final DateTime? lastUsedAt; // When this category was last used in an expense
  final int useCount; // Total number of times this category was used

  const CategoryEntity({
    required this.id,
    required this.name,
    required this.groupId,
    required this.isDefault,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.lastUsedAt,
    this.useCount = 0,
  });

  /// Create a copy with updated MRU fields
  CategoryEntity copyWith({
    String? id,
    String? name,
    String? groupId,
    bool? isDefault,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastUsedAt,
    int? useCount,
  }) {
    return CategoryEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      groupId: groupId ?? this.groupId,
      isDefault: isDefault ?? this.isDefault,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      useCount: useCount ?? this.useCount,
    );
  }

  /// Is this category a "virgin" category (never used)?
  bool get isVirgin => lastUsedAt == null;

  @override
  List<Object?> get props => [
        id,
        name,
        groupId,
        isDefault,
        createdBy,
        createdAt,
        updatedAt,
        lastUsedAt,
        useCount,
      ];

  @override
  bool? get stringify => true;
}
