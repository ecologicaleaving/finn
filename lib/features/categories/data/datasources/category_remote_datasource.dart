import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../models/expense_category_model.dart';

/// Remote data source for category operations using Supabase.
abstract class CategoryRemoteDataSource {
  /// Get all categories for a group.
  Future<List<ExpenseCategoryModel>> getCategories({
    required String groupId,
    bool includeExpenseCount = false,
  });

  /// Get a single category by ID.
  Future<ExpenseCategoryModel> getCategory({required String categoryId});

  /// Create a new category.
  Future<ExpenseCategoryModel> createCategory({
    required String groupId,
    required String name,
    String? iconName,
  });

  /// Update a category name.
  Future<ExpenseCategoryModel> updateCategory({
    required String categoryId,
    required String name,
  });

  /// Update a category icon.
  Future<ExpenseCategoryModel> updateCategoryIcon({
    required String categoryId,
    required String iconName,
  });

  /// Delete a category.
  Future<void> deleteCategory({required String categoryId});

  /// Batch update expenses to new category (using RPC function).
  Future<int> batchUpdateExpenseCategory({
    required String groupId,
    required String oldCategoryId,
    required String newCategoryId,
  });

  /// Get expense count for a category (using RPC function).
  Future<int> getCategoryExpenseCount({required String categoryId});

  /// Feature 013 T066: Get recurring expense count for a category.
  Future<int> getCategoryRecurringExpenseCount({required String categoryId});

  /// Check if category name exists in group.
  Future<bool> categoryNameExists({
    required String groupId,
    required String name,
    String? excludeCategoryId,
  });

  // ========== Virgin Category Tracking (Feature 004) ==========

  /// Check if a user has used a specific category (virgin detection).
  Future<bool> hasUserUsedCategory({
    required String userId,
    required String categoryId,
  });

  /// Mark a category as used by a user (after first expense).
  Future<void> markCategoryAsUsed({
    required String userId,
    required String categoryId,
  });

  // ========== MRU (Most Recently Used) Tracking (Feature 001) ==========

  /// Get categories ordered by MRU for a user.
  ///
  /// Uses LEFT JOIN with user_category_usage to sort by last_used_at.
  /// Virgin categories (never used) appear last, sorted alphabetically.
  Future<List<ExpenseCategoryModel>> getCategoriesByMRU({
    required String groupId,
    required String userId,
  });

  /// Update category usage tracking (using RPC function).
  ///
  /// Calls upsert_category_usage to increment use_count and update last_used_at.
  Future<void> updateCategoryUsage({
    required String userId,
    required String categoryId,
  });
}

/// Implementation of [CategoryRemoteDataSource] using Supabase.
class CategoryRemoteDataSourceImpl implements CategoryRemoteDataSource {
  CategoryRemoteDataSourceImpl({required this.supabaseClient});

  final SupabaseClient supabaseClient;

  String get _currentUserId {
    final userId = supabaseClient.auth.currentUser?.id;
    if (userId == null) {
      throw const AppAuthException('No authenticated user', 'not_authenticated');
    }
    return userId;
  }

  @override
  Future<List<ExpenseCategoryModel>> getCategories({
    required String groupId,
    bool includeExpenseCount = false,
  }) async {
    try {
      var query = supabaseClient
          .from('expense_categories')
          .select(includeExpenseCount
              ? '*, expense_count:get_category_expense_count(category_id)'
              : '*')
          .eq('group_id', groupId)
          .order('is_default', ascending: false) // Default categories first
          .order('name', ascending: true);

      final response = await query;

      return (response as List)
          .map((json) => ExpenseCategoryModel.fromJson(json))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException('Failed to get categories: $e');
    }
  }

  @override
  Future<ExpenseCategoryModel> getCategory({required String categoryId}) async {
    try {
      final response = await supabaseClient
          .from('expense_categories')
          .select()
          .eq('id', categoryId)
          .single();

      return ExpenseCategoryModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException('Failed to get category: $e');
    }
  }

  @override
  Future<ExpenseCategoryModel> createCategory({
    required String groupId,
    required String name,
    String? iconName,
  }) async {
    try {
      final userId = _currentUserId;

      final insertData = {
        'group_id': groupId,
        'name': name,
        'is_default': false,
        'created_by': userId,
      };

      if (iconName != null) {
        insertData['icon_name'] = iconName;
      }

      final response = await supabaseClient
          .from('expense_categories')
          .insert(insertData)
          .select()
          .single();

      return ExpenseCategoryModel.fromJson(response);
    } on PostgrestException catch (e) {
      // Check for unique constraint violation
      if (e.code == '23505') {
        throw const ValidationException(
          'A category with this name already exists',
        );
      }
      // Check for permission error
      if (e.code == '42501' || e.code == 'PGRST301') {
        throw const PermissionException(
          'Only administrators can create categories',
        );
      }
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException('Failed to create category: $e');
    }
  }

  @override
  Future<ExpenseCategoryModel> updateCategory({
    required String categoryId,
    required String name,
  }) async {
    try {
      final response = await supabaseClient
          .from('expense_categories')
          .update({'name': name, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', categoryId)
          .select()
          .single();

      return ExpenseCategoryModel.fromJson(response);
    } on PostgrestException catch (e) {
      // Check for unique constraint violation
      if (e.code == '23505') {
        throw const ValidationException(
          'A category with this name already exists',
        );
      }
      // Check for permission error or default category update attempt
      if (e.code == '42501' || e.code == 'PGRST301') {
        throw const PermissionException(
          'Only administrators can update categories, and default categories cannot be renamed',
        );
      }
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException('Failed to update category: $e');
    }
  }

  @override
  Future<ExpenseCategoryModel> updateCategoryIcon({
    required String categoryId,
    required String iconName,
  }) async {
    try {
      final response = await supabaseClient
          .from('expense_categories')
          .update({
            'icon_name': iconName,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', categoryId)
          .select()
          .single();

      return ExpenseCategoryModel.fromJson(response);
    } on PostgrestException catch (e) {
      // Check for permission error
      if (e.code == '42501' || e.code == 'PGRST301') {
        throw const PermissionException(
          'Only administrators can update category icons',
        );
      }
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException('Failed to update category icon: $e');
    }
  }

  @override
  Future<void> deleteCategory({required String categoryId}) async {
    try {
      await supabaseClient
          .from('expense_categories')
          .delete()
          .eq('id', categoryId);
    } on PostgrestException catch (e) {
      // Check for foreign key constraint violation
      if (e.code == '23503') {
        throw const ValidationException(
          'Cannot delete category with existing expenses. Reassign expenses first.',
        );
      }
      // Check for permission error or default category deletion attempt
      if (e.code == '42501' || e.code == 'PGRST301') {
        throw const PermissionException(
          'Only administrators can delete categories, and default categories cannot be deleted',
        );
      }
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException('Failed to delete category: $e');
    }
  }

  @override
  Future<int> batchUpdateExpenseCategory({
    required String groupId,
    required String oldCategoryId,
    required String newCategoryId,
  }) async {
    try {
      // Call PostgreSQL RPC function for efficient batch update
      final response = await supabaseClient.rpc(
        'batch_update_expense_category',
        params: {
          'p_group_id': groupId,
          'p_old_category_id': oldCategoryId,
          'p_new_category_id': newCategoryId,
        },
      );

      return response as int;
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException('Failed to batch update expense category: $e');
    }
  }

  @override
  Future<int> getCategoryExpenseCount({required String categoryId}) async {
    try {
      // Call PostgreSQL RPC function
      final response = await supabaseClient.rpc(
        'get_category_expense_count',
        params: {'p_category_id': categoryId},
      );

      return response as int;
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException('Failed to get category expense count: $e');
    }
  }

  /// Feature 013 T066: Get count of recurring expenses using this category
  Future<int> getCategoryRecurringExpenseCount({
    required String categoryId,
  }) async {
    try {
      // Query recurring_expenses table directly
      final response = await supabaseClient
          .from('recurring_expenses')
          .select('id')
          .eq('category_id', categoryId)
          .count(CountOption.exact);

      return response.count;
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException(
        'Failed to get category recurring expense count: $e',
      );
    }
  }

  @override
  Future<bool> categoryNameExists({
    required String groupId,
    required String name,
    String? excludeCategoryId,
  }) async {
    try {
      var query = supabaseClient
          .from('expense_categories')
          .select('id')
          .eq('group_id', groupId)
          .ilike('name', name); // Case-insensitive

      if (excludeCategoryId != null) {
        query = query.neq('id', excludeCategoryId);
      }

      final response = await query;
      return (response as List).isNotEmpty;
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException('Failed to check category name: $e');
    }
  }

  // ========== Virgin Category Tracking (Feature 004) ==========

  @override
  Future<bool> hasUserUsedCategory({
    required String userId,
    required String categoryId,
  }) async {
    try {
      final response = await supabaseClient
          .from('user_category_usage')
          .select('id')
          .eq('user_id', userId)
          .eq('category_id', categoryId)
          .maybeSingle();

      return response != null;
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException('Failed to check user category usage: $e');
    }
  }

  @override
  Future<void> markCategoryAsUsed({
    required String userId,
    required String categoryId,
  }) async {
    try {
      await supabaseClient.from('user_category_usage').insert({
        'user_id': userId,
        'category_id': categoryId,
      });
    } on PostgrestException catch (e) {
      // Ignore duplicate key error (23505) - user already has record
      if (e.code != '23505') {
        throw ServerException(e.message, e.code);
      }
    } catch (e) {
      throw ServerException('Failed to mark category as used: $e');
    }
  }

  // ========== MRU (Most Recently Used) Tracking (Feature 001) ==========

  @override
  Future<List<ExpenseCategoryModel>> getCategoriesByMRU({
    required String groupId,
    required String userId,
  }) async {
    try {
      // Query categories with LEFT JOIN to user_category_usage
      // This allows us to get MRU data while still returning all categories
      final response = await supabaseClient
          .from('expense_categories')
          .select('''
            *,
            user_category_usage!left(last_used_at, use_count)
          ''')
          .eq('group_id', groupId)
          .eq('user_category_usage.user_id', userId);

      // Parse response and extract categories
      final categories = (response as List)
          .map((json) => ExpenseCategoryModel.fromJson(json))
          .toList();

      // Sort alphabetically by name
      categories.sort((a, b) => a.name.compareTo(b.name));

      return categories;
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException('Failed to get categories by MRU: $e');
    }
  }

  @override
  Future<void> updateCategoryUsage({
    required String userId,
    required String categoryId,
  }) async {
    try {
      // Call the PostgreSQL RPC function to upsert usage tracking
      // Note: Function expects UUID types, Supabase handles string->UUID conversion
      await supabaseClient.rpc(
        'upsert_category_usage',
        params: {
          'p_user_id': userId,
          'p_category_id': categoryId,
          'p_last_used_at': DateTime.now().toIso8601String(),
        },
      );
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException('Failed to update category usage: $e');
    }
  }
}
