// Contract: CategoryRepository Interface Updates
// Feature: 014-category-icons
// Purpose: Define new methods for icon management

import 'package:dartz/dartz.dart';
import '../../../lib/core/errors/failures.dart';
import '../../../lib/features/categories/domain/entities/expense_category_entity.dart';

abstract class CategoryRepository {
  // ... existing methods ...

  /// Update a category's icon.
  ///
  /// Only administrators can update category icons.
  /// Validates that iconName is a valid Material Icons name.
  ///
  /// Returns the updated category or a Failure.
  Future<Either<Failure, ExpenseCategoryEntity>> updateCategoryIcon({
    required String categoryId,
    required String iconName,
  });

  /// Create a new custom category with optional icon.
  ///
  /// Only administrators can create categories.
  /// If iconName is not provided, defaults to name-based icon matching.
  ///
  /// Returns the created category with its generated ID or a Failure.
  Future<Either<Failure, ExpenseCategoryEntity>> createCategory({
    required String groupId,
    required String name,
    String? iconName,  // NEW: Optional icon selection
  });
}
