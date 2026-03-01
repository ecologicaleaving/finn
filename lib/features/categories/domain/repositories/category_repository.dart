import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/expense_category_entity.dart';

/// Abstract category repository interface.
///
/// Defines the contract for category operations (CRUD + bulk operations).
/// Implementations should handle the actual communication with the backend (Supabase).
abstract class CategoryRepository {
  // ========== Category CRUD Operations ==========

  /// Get all categories for a group.
  ///
  /// Returns list of categories with optional expense counts.
  Future<Either<Failure, List<ExpenseCategoryEntity>>> getCategories({
    required String groupId,
    bool includeExpenseCount = false,
  });

  /// Get a single category by ID.
  Future<Either<Failure, ExpenseCategoryEntity>> getCategory({
    required String categoryId,
  });

  /// Create a new custom category.
  ///
  /// Only administrators can create categories.
  /// Returns the created category with its generated ID.
  Future<Either<Failure, ExpenseCategoryEntity>> createCategory({
    required String groupId,
    required String name,
    String? iconName,
  });

  /// Update a category name.
  ///
  /// Only administrators can update categories.
  /// Default categories cannot be renamed.
  Future<Either<Failure, ExpenseCategoryEntity>> updateCategory({
    required String categoryId,
    required String name,
  });

  /// Update a category's icon.
  ///
  /// Only administrators can update category icons.
  /// Validates that iconName is a valid Material Icons name.
  Future<Either<Failure, ExpenseCategoryEntity>> updateCategoryIcon({
    required String categoryId,
    required String iconName,
  });

  /// Delete a category.
  ///
  /// Only administrators can delete categories.
  /// Default categories cannot be deleted.
  /// Must reassign all expenses to another category first.
  Future<Either<Failure, Unit>> deleteCategory({
    required String categoryId,
  });

  // ========== Bulk Operations ==========

  /// Batch update expenses to new category.
  ///
  /// Used when deleting a category - reassigns all expenses to a new category.
  /// Supports bulk reassignment of 500+ expenses efficiently.
  Future<Either<Failure, int>> batchUpdateExpenseCategory({
    required String groupId,
    required String oldCategoryId,
    required String newCategoryId,
  });

  /// Get expense count for a category.
  ///
  /// Returns the number of expenses using this category.
  Future<Either<Failure, int>> getCategoryExpenseCount({
    required String categoryId,
  });

  // ========== Validation ==========

  /// Check if a category name already exists in the group.
  ///
  /// Used for validation before creating or renaming categories.
  Future<Either<Failure, bool>> categoryNameExists({
    required String groupId,
    required String name,
    String? excludeCategoryId,
  });

  // ========== Virgin Category Tracking (Feature 004) ==========

  /// Check if a user has used a specific category (virgin detection).
  ///
  /// Used to determine if budget prompt should be shown on first expense.
  Future<Either<Failure, bool>> hasUserUsedCategory({
    required String userId,
    required String categoryId,
  });

  /// Mark a category as used by a user (after first expense).
  ///
  /// Creates user_category_usage record to prevent future prompts.
  Future<Either<Failure, Unit>> markCategoryAsUsed({
    required String userId,
    required String categoryId,
  });

  // ========== MRU (Most Recently Used) Tracking (Feature 001) ==========

  /// Get categories ordered by MRU (Most Recently Used) for a user.
  ///
  /// Categories are sorted by:
  /// 1. Most recently used first (last_used_at DESC)
  /// 2. Virgin categories (never used) appear last, sorted alphabetically
  ///
  /// Used for category dropdown in manual expense entry.
  Future<Either<Failure, List<ExpenseCategoryEntity>>> getCategoriesByMRU({
    required String groupId,
    required String userId,
  });

  /// Update category usage tracking when an expense is saved.
  ///
  /// Increments use_count and updates last_used_at timestamp.
  /// Called after expense creation/update with a category.
  Future<Either<Failure, Unit>> updateCategoryUsage({
    required String userId,
    required String categoryId,
  });
}
