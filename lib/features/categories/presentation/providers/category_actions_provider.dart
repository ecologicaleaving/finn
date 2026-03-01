import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/icon_matching_service.dart';
import '../../domain/entities/expense_category_entity.dart';
import '../../domain/repositories/category_repository.dart';
import 'category_provider.dart';
import 'category_repository_provider.dart';

/// Actions for category operations
class CategoryActions {
  CategoryActions(this._ref);

  final Ref _ref;

  /// Create a new category
  Future<ExpenseCategoryEntity?> createCategory({
    required String groupId,
    required String name,
    String? iconName,
  }) async {
    final repository = _ref.read(categoryRepositoryProvider);

    // Auto-set icon based on name if not provided
    final finalIconName = iconName ??
        IconMatchingService.getDefaultIconNameForCategory(name);

    final result = await repository.createCategory(
      groupId: groupId,
      name: name,
      iconName: finalIconName,
    );

    return result.fold(
      (failure) {
        // Handle error
        return null;
      },
      (category) {
        // Refresh category state
        _ref.read(categoryProvider(groupId).notifier).loadCategories();
        return category;
      },
    );
  }

  /// Update category name
  Future<ExpenseCategoryEntity?> updateCategory({
    required String groupId,
    required String categoryId,
    required String name,
  }) async {
    print('🎯 [CategoryActions] updateCategory called');
    print('   groupId: $groupId');
    print('   categoryId: $categoryId');
    print('   name: $name');

    final repository = _ref.read(categoryRepositoryProvider);

    final result = await repository.updateCategory(
      categoryId: categoryId,
      name: name,
    );

    return result.fold(
      (failure) {
        print('   ❌ [CategoryActions] Repository returned failure: $failure');
        print('   Failure type: ${failure.runtimeType}');
        // Handle error
        return null;
      },
      (category) {
        print('   ✅ [CategoryActions] Repository returned success: ${category.name}');
        // Refresh category state
        _ref.read(categoryProvider(groupId).notifier).loadCategories();
        return category;
      },
    );
  }

  /// Update category icon
  Future<ExpenseCategoryEntity?> updateCategoryIcon({
    required String groupId,
    required String categoryId,
    required String iconName,
  }) async {
    final repository = _ref.read(categoryRepositoryProvider);

    final result = await repository.updateCategoryIcon(
      categoryId: categoryId,
      iconName: iconName,
    );

    return result.fold(
      (failure) {
        // Handle error
        return null;
      },
      (category) {
        // Refresh category state
        _ref.read(categoryProvider(groupId).notifier).loadCategories();
        return category;
      },
    );
  }

  /// Delete category
  Future<bool> deleteCategory({
    required String groupId,
    required String categoryId,
  }) async {
    final repository = _ref.read(categoryRepositoryProvider);

    final result = await repository.deleteCategory(
      categoryId: categoryId,
    );

    return result.fold(
      (failure) {
        // Handle error
        return false;
      },
      (_) {
        // Refresh category state
        _ref.read(categoryProvider(groupId).notifier).loadCategories();
        return true;
      },
    );
  }

  /// Batch reassign expenses from one category to another
  Future<int?> batchUpdateExpenseCategory({
    required String groupId,
    required String oldCategoryId,
    required String newCategoryId,
  }) async {
    final repository = _ref.read(categoryRepositoryProvider);

    final result = await repository.batchUpdateExpenseCategory(
      groupId: groupId,
      oldCategoryId: oldCategoryId,
      newCategoryId: newCategoryId,
    );

    return result.fold(
      (failure) {
        // Handle error
        return null;
      },
      (count) {
        // Refresh category state to update expense counts
        _ref.read(categoryProvider(groupId).notifier).loadCategories(
              includeExpenseCount: true,
            );
        return count;
      },
    );
  }

  /// Get expense count for a category
  Future<int?> getCategoryExpenseCount({
    required String categoryId,
  }) async {
    final repository = _ref.read(categoryRepositoryProvider);

    final result = await repository.getCategoryExpenseCount(
      categoryId: categoryId,
    );

    return result.fold(
      (failure) => null,
      (count) => count,
    );
  }

  /// Check if category name exists
  Future<bool> categoryNameExists({
    required String groupId,
    required String name,
    String? excludeCategoryId,
  }) async {
    final repository = _ref.read(categoryRepositoryProvider);

    final result = await repository.categoryNameExists(
      groupId: groupId,
      name: name,
      excludeCategoryId: excludeCategoryId,
    );

    return result.fold(
      (failure) => false,
      (exists) => exists,
    );
  }
}

/// Provider for category actions
final categoryActionsProvider = Provider<CategoryActions>((ref) {
  return CategoryActions(ref);
});
