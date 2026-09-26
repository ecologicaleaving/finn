import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:family_expense_tracker/core/errors/exceptions.dart';
import 'package:family_expense_tracker/core/errors/failures.dart';
import 'package:family_expense_tracker/features/categories/data/datasources/category_remote_datasource.dart';
import 'package:family_expense_tracker/features/categories/data/models/expense_category_model.dart';
import 'package:family_expense_tracker/features/categories/data/repositories/category_repository_impl.dart';

/// Hand-written fake (no codegen) covering the calls made by deleteCategory.
class FakeCategoryRemoteDataSource implements CategoryRemoteDataSource {
  FakeCategoryRemoteDataSource({
    this.isDefault = false,
    this.expenseCount = 0,
    this.remoteRecurringCount = 0,
    this.remoteRecurringThrows = false,
  });

  final bool isDefault;
  final int expenseCount;
  final int remoteRecurringCount;
  final bool remoteRecurringThrows;

  bool deleteCalled = false;

  @override
  Future<ExpenseCategoryModel> getCategory({required String categoryId}) async {
    final now = DateTime(2026, 1, 1);
    return ExpenseCategoryModel(
      id: categoryId,
      name: 'Test',
      groupId: 'group-1',
      isDefault: isDefault,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<int> getCategoryExpenseCount({required String categoryId}) async =>
      expenseCount;

  @override
  Future<int> getCategoryRecurringExpenseCount({
    required String categoryId,
  }) async {
    if (remoteRecurringThrows) {
      throw const ServerException('relation "recurring_expenses" not found');
    }
    return remoteRecurringCount;
  }

  @override
  Future<void> deleteCategory({required String categoryId}) async {
    deleteCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  const categoryId = '11111111-1111-1111-1111-111111111111';

  group('CategoryRepositoryImpl.deleteCategory (issue #49)', () {
    test('blocks deletion when local recurring templates use the category',
        () async {
      final remote = FakeCategoryRemoteDataSource();
      final repo = CategoryRepositoryImpl(
        remoteDataSource: remote,
        localRecurringTemplateCounter: (_) async => 2,
      );

      final result = await repo.deleteCategory(categoryId: categoryId);

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<ValidationFailure>()),
        (_) => fail('expected failure'),
      );
      expect(remote.deleteCalled, isFalse);
    });

    test('local check still applies when remote recurring check fails',
        () async {
      final remote = FakeCategoryRemoteDataSource(remoteRecurringThrows: true);
      final repo = CategoryRepositoryImpl(
        remoteDataSource: remote,
        localRecurringTemplateCounter: (_) async => 1,
      );

      final result = await repo.deleteCategory(categoryId: categoryId);

      result.fold(
        (f) => expect(f, isA<ValidationFailure>()),
        (_) => fail('expected failure'),
      );
      expect(remote.deleteCalled, isFalse);
    });

    test('blocks deletion when the category has expenses', () async {
      final remote = FakeCategoryRemoteDataSource(expenseCount: 3);
      final repo = CategoryRepositoryImpl(
        remoteDataSource: remote,
        localRecurringTemplateCounter: (_) async => 0,
      );

      final result = await repo.deleteCategory(categoryId: categoryId);

      result.fold(
        (f) => expect(f, isA<ValidationFailure>()),
        (_) => fail('expected failure'),
      );
      expect(remote.deleteCalled, isFalse);
    });

    test('deletes when there are no expenses nor recurring templates',
        () async {
      final remote = FakeCategoryRemoteDataSource();
      final repo = CategoryRepositoryImpl(
        remoteDataSource: remote,
        localRecurringTemplateCounter: (_) async => 0,
      );

      final result = await repo.deleteCategory(categoryId: categoryId);

      expect(result, const Right<Failure, Unit>(unit));
      expect(remote.deleteCalled, isTrue);
    });

    test('remote recurring failure alone does not block deletion', () async {
      final remote = FakeCategoryRemoteDataSource(remoteRecurringThrows: true);
      final repo = CategoryRepositoryImpl(
        remoteDataSource: remote,
        localRecurringTemplateCounter: (_) async => 0,
      );

      final result = await repo.deleteCategory(categoryId: categoryId);

      expect(result.isRight(), isTrue);
      expect(remote.deleteCalled, isTrue);
    });

    test('default category cannot be deleted', () async {
      final remote = FakeCategoryRemoteDataSource(isDefault: true);
      final repo = CategoryRepositoryImpl(
        remoteDataSource: remote,
        localRecurringTemplateCounter: (_) async => 0,
      );

      final result = await repo.deleteCategory(categoryId: categoryId);

      result.fold(
        (f) => expect(f, isA<PermissionFailure>()),
        (_) => fail('expected failure'),
      );
      expect(remote.deleteCalled, isFalse);
    });

    test('fails closed when the local counter throws', () async {
      final remote = FakeCategoryRemoteDataSource();
      final repo = CategoryRepositoryImpl(
        remoteDataSource: remote,
        localRecurringTemplateCounter: (_) async =>
            throw StateError('database closed'),
      );

      final result = await repo.deleteCategory(categoryId: categoryId);

      expect(result.isLeft(), isTrue);
      expect(remote.deleteCalled, isFalse);
    });
  });
}
