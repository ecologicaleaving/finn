import 'package:dartz/dartz.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/services/icon_helper.dart';
import '../../domain/entities/expense_category_entity.dart';
import '../../domain/repositories/category_repository.dart';
import '../datasources/category_remote_datasource.dart';

/// Counts local (Drift) recurring expense templates that use a category.
typedef LocalRecurringTemplateCounter = Future<int> Function(String categoryId);

/// Implementation of [CategoryRepository] using remote data source.
class CategoryRepositoryImpl implements CategoryRepository {
  CategoryRepositoryImpl({
    required this.remoteDataSource,
    this.localRecurringTemplateCounter,
  });

  final CategoryRemoteDataSource remoteDataSource;

  /// Issue #49: recurring templates live only in the local Drift database
  /// (they are never uploaded to the remote `recurring_expenses` table), so
  /// deletion must also check them locally.
  final LocalRecurringTemplateCounter? localRecurringTemplateCounter;

  // ========== Category CRUD Operations ==========

  @override
  Future<Either<Failure, List<ExpenseCategoryEntity>>> getCategories({
    required String groupId,
    bool includeExpenseCount = false,
  }) async {
    try {
      final categories = await remoteDataSource.getCategories(
        groupId: groupId,
        includeExpenseCount: includeExpenseCount,
      );
      return Right(categories.map((c) => c.toEntity()).toList());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ExpenseCategoryEntity>> getCategory({
    required String categoryId,
  }) async {
    try {
      final category = await remoteDataSource.getCategory(
        categoryId: categoryId,
      );
      return Right(category.toEntity());
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ExpenseCategoryEntity>> createCategory({
    required String groupId,
    required String name,
    String? iconName,
  }) async {
    // Validate category name
    final validationError = _validateCategoryName(name);
    if (validationError != null) {
      return Left(ValidationFailure(validationError));
    }

    // Validate icon name if provided
    if (iconName != null && !IconHelper.isValidIconName(iconName)) {
      return Left(ValidationFailure('Invalid icon name: $iconName'));
    }

    try {
      // Check if name already exists
      final exists = await remoteDataSource.categoryNameExists(
        groupId: groupId,
        name: name,
      );

      if (exists) {
        return Left(
          ValidationFailure('A category with this name already exists'),
        );
      }

      final category = await remoteDataSource.createCategory(
        groupId: groupId,
        name: name,
        iconName: iconName,
      );
      return Right(category.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on PermissionException catch (e) {
      return Left(PermissionFailure(e.message));
    } on ValidationException catch (e) {
      return Left(ValidationFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ExpenseCategoryEntity>> updateCategory({
    required String categoryId,
    required String name,
  }) async {
    print('📦 [Repository] updateCategory called');
    print('   categoryId: $categoryId');
    print('   name: $name');

    // Validate category name
    final validationError = _validateCategoryName(name);
    if (validationError != null) {
      print('   ❌ Validation failed: $validationError');
      return Left(ValidationFailure(validationError));
    }

    try {
      // Get the category to check permissions and get group_id
      print('   📖 Fetching category...');
      final categoryResult = await getCategory(categoryId: categoryId);

      return await categoryResult.fold(
        (failure) {
          print('   ❌ Failed to get category: $failure');
          return Left(failure);
        },
        (category) async {
          print('   ✅ Category fetched: ${category.name}');
          print('   📝 isDefault: ${category.isDefault}');

          // Check if name already exists (excluding current category)
          print('   🔍 Checking if name exists...');
          final exists = await remoteDataSource.categoryNameExists(
            groupId: category.groupId,
            name: name,
            excludeCategoryId: categoryId,
          );

          if (exists) {
            print('   ❌ Name already exists');
            return Left(
              ValidationFailure('A category with this name already exists'),
            );
          }
          print('   ✅ Name is unique');

          // Check if it's a default category
          if (category.isDefault) {
            print('   ❌ Cannot rename default category');
            return Left(
              PermissionFailure('Default categories cannot be renamed'),
            );
          }

          print('   💾 Calling datasource.updateCategory...');
          final updated = await remoteDataSource.updateCategory(
            categoryId: categoryId,
            name: name,
          );
          print('   ✅ Datasource returned: ${updated.name}');
          return Right(updated.toEntity());
        },
      );
    } on PermissionException catch (e) {
      print('   💥 PermissionException: ${e.message}');
      return Left(PermissionFailure(e.message));
    } on ValidationException catch (e) {
      print('   💥 ValidationException: ${e.message}');
      return Left(ValidationFailure(e.message));
    } on ServerException catch (e) {
      print('   💥 ServerException: ${e.message}');
      return Left(ServerFailure(e.message));
    } catch (e, stackTrace) {
      print('   💥 Unexpected exception: $e');
      print('   Stack: $stackTrace');
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, ExpenseCategoryEntity>> updateCategoryIcon({
    required String categoryId,
    required String iconName,
  }) async {
    // Validate icon name
    if (!IconHelper.isValidIconName(iconName)) {
      return Left(ValidationFailure('Invalid icon name: $iconName'));
    }

    try {
      final updated = await remoteDataSource.updateCategoryIcon(
        categoryId: categoryId,
        iconName: iconName,
      );
      return Right(updated.toEntity());
    } on PermissionException catch (e) {
      return Left(PermissionFailure(e.message));
    } on ValidationException catch (e) {
      return Left(ValidationFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteCategory({
    required String categoryId,
  }) async {
    try {
      // Get the category to check if it can be deleted
      final categoryResult = await getCategory(categoryId: categoryId);

      return await categoryResult.fold(
        (failure) => Left(failure),
        (category) async {
          // Check if it's a default category
          if (category.isDefault) {
            return Left(
              PermissionFailure('Default categories cannot be deleted'),
            );
          }

          // Check if it has expenses
          final expenseCount = await remoteDataSource.getCategoryExpenseCount(
            categoryId: categoryId,
          );

          if (expenseCount > 0) {
            return Left(
              ValidationFailure(
                'Cannot delete category with existing expenses. '
                'Please reassign all expenses to another category first.',
              ),
            );
          }

          // Issue #49: recurring templates are stored locally (Drift).
          // Fail-closed: if the local count cannot be read, do not delete.
          var localRecurringCount = 0;
          final localCounter = localRecurringTemplateCounter;
          if (localCounter != null) {
            try {
              localRecurringCount = await localCounter(categoryId);
            } catch (e) {
              return Left(
                CacheFailure(
                  'Unable to verify recurring expenses for this category: $e',
                ),
              );
            }
          }

          // Feature 013 T066: remote `recurring_expenses` check, kept as a
          // best-effort safety net. A failure here (table missing, RLS)
          // must not mask the local check nor block deletion by itself.
          var remoteRecurringCount = 0;
          try {
            remoteRecurringCount =
                await remoteDataSource.getCategoryRecurringExpenseCount(
              categoryId: categoryId,
            );
          } on ServerException {
            remoteRecurringCount = 0;
          }

          final recurringExpenseCount =
              localRecurringCount > remoteRecurringCount
                  ? localRecurringCount
                  : remoteRecurringCount;

          if (recurringExpenseCount > 0) {
            return Left(
              ValidationFailure(
                'Cannot delete category with $recurringExpenseCount recurring expense(s). '
                'Please delete or reassign the recurring expenses first.',
              ),
            );
          }

          await remoteDataSource.deleteCategory(categoryId: categoryId);
          return const Right(unit);
        },
      );
    } on PermissionException catch (e) {
      return Left(PermissionFailure(e.message));
    } on ValidationException catch (e) {
      return Left(ValidationFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  // ========== Bulk Operations ==========

  @override
  Future<Either<Failure, int>> batchUpdateExpenseCategory({
    required String groupId,
    required String oldCategoryId,
    required String newCategoryId,
  }) async {
    try {
      final count = await remoteDataSource.batchUpdateExpenseCategory(
        groupId: groupId,
        oldCategoryId: oldCategoryId,
        newCategoryId: newCategoryId,
      );
      return Right(count);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, int>> getCategoryExpenseCount({
    required String categoryId,
  }) async {
    try {
      final count = await remoteDataSource.getCategoryExpenseCount(
        categoryId: categoryId,
      );
      return Right(count);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  // ========== Validation ==========

  @override
  Future<Either<Failure, bool>> categoryNameExists({
    required String groupId,
    required String name,
    String? excludeCategoryId,
  }) async {
    try {
      final exists = await remoteDataSource.categoryNameExists(
        groupId: groupId,
        name: name,
        excludeCategoryId: excludeCategoryId,
      );
      return Right(exists);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  // ========== Virgin Category Tracking (Feature 004) ==========

  @override
  Future<Either<Failure, bool>> hasUserUsedCategory({
    required String userId,
    required String categoryId,
  }) async {
    try {
      final hasUsed = await remoteDataSource.hasUserUsedCategory(
        userId: userId,
        categoryId: categoryId,
      );
      return Right(hasUsed);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> markCategoryAsUsed({
    required String userId,
    required String categoryId,
  }) async {
    try {
      await remoteDataSource.markCategoryAsUsed(
        userId: userId,
        categoryId: categoryId,
      );
      return const Right(unit);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  // ========== MRU (Most Recently Used) Tracking (Feature 001) ==========

  @override
  Future<Either<Failure, List<ExpenseCategoryEntity>>> getCategoriesByMRU({
    required String groupId,
    required String userId,
  }) async {
    try {
      final categories = await remoteDataSource.getCategoriesByMRU(
        groupId: groupId,
        userId: userId,
      );
      return Right(categories.map((c) => c.toEntity()).toList());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> updateCategoryUsage({
    required String userId,
    required String categoryId,
  }) async {
    try {
      await remoteDataSource.updateCategoryUsage(
        userId: userId,
        categoryId: categoryId,
      );
      return const Right(unit);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// Validate category name.
  ///
  /// Returns error message if invalid, null if valid.
  String? _validateCategoryName(String name) {
    final trimmed = name.trim();

    if (trimmed.isEmpty) {
      return 'Category name cannot be empty';
    }

    if (trimmed.length < 1) {
      return 'Category name must be at least 1 character';
    }

    if (trimmed.length > 50) {
      return 'Category name must be at most 50 characters';
    }

    return null;
  }
}
