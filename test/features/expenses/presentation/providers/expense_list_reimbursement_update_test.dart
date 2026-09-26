import 'package:dartz/dartz.dart';
import 'package:family_expense_tracker/core/enums/reimbursement_status.dart';
import 'package:family_expense_tracker/core/errors/failures.dart';
import 'package:family_expense_tracker/features/expenses/domain/entities/expense_entity.dart';
import 'package:family_expense_tracker/features/expenses/domain/repositories/expense_repository.dart';
import 'package:family_expense_tracker/features/expenses/presentation/providers/expense_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records `updateExpense` calls; every other method is unused.
class _FakeExpenseRepository implements ExpenseRepository {
  _FakeExpenseRepository({this.failure});

  final Failure? failure;
  final List<({String expenseId, ReimbursementStatus? status})> calls = [];
  ExpenseEntity? serverEntity;

  @override
  Future<Either<Failure, ExpenseEntity>> updateExpense({
    required String expenseId,
    double? amount,
    DateTime? date,
    String? categoryId,
    String? paymentMethodId,
    String? merchant,
    String? notes,
    ReimbursementStatus? reimbursementStatus,
  }) async {
    calls.add((expenseId: expenseId, status: reimbursementStatus));
    if (failure != null) return Left(failure!);
    return Right(serverEntity!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ExpenseEntity _expense({
  String id = 'exp-1',
  ReimbursementStatus status = ReimbursementStatus.reimbursable,
  DateTime? reimbursedAt,
}) {
  return ExpenseEntity(
    id: id,
    groupId: 'group-1',
    createdBy: 'user-1',
    amount: 25,
    date: DateTime(2026, 9, 20),
    categoryName: 'Spesa',
    paymentMethodId: 'pm-1',
    reimbursementStatus: status,
    reimbursedAt: reimbursedAt,
  );
}

void main() {
  group('ExpenseListNotifier.changeReimbursementStatus (issue #47)', () {
    test('updates an expense that is NOT in the loaded list (AC3)', () async {
      final repo = _FakeExpenseRepository();
      final serverReimbursedAt = DateTime.utc(2026, 9, 26, 9);
      repo.serverEntity = _expense(
        status: ReimbursementStatus.reimbursed,
        reimbursedAt: serverReimbursedAt,
      );
      final notifier = ExpenseListNotifier(repo);
      addTearDown(notifier.dispose);

      expect(notifier.state.expenses, isEmpty);

      final result = await notifier.changeReimbursementStatus(
        expense: _expense(),
        newStatus: ReimbursementStatus.reimbursed,
      );

      expect(repo.calls, hasLength(1));
      expect(repo.calls.single.expenseId, 'exp-1');
      expect(repo.calls.single.status, ReimbursementStatus.reimbursed);
      expect(result.isRight(), isTrue);
      final updated = result.getOrElse(() => throw StateError('left'));
      expect(updated.reimbursementStatus, ReimbursementStatus.reimbursed);
      expect(updated.reimbursedAt, serverReimbursedAt);
      // List untouched: expense was not loaded.
      expect(notifier.state.expenses, isEmpty);
    });

    test('invalid transition none -> reimbursed does not call repository', () async {
      final repo = _FakeExpenseRepository();
      final notifier = ExpenseListNotifier(repo);
      addTearDown(notifier.dispose);

      final result = await notifier.changeReimbursementStatus(
        expense: _expense(status: ReimbursementStatus.none),
        newStatus: ReimbursementStatus.reimbursed,
      );

      expect(repo.calls, isEmpty);
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<ValidationFailure>()),
        (_) => fail('expected Left'),
      );
    });

    test('replaces the list entry with the server entity when loaded', () async {
      final repo = _FakeExpenseRepository();
      final serverReimbursedAt = DateTime.utc(2026, 9, 26, 9);
      repo.serverEntity = _expense(
        status: ReimbursementStatus.reimbursed,
        reimbursedAt: serverReimbursedAt,
      );
      final notifier = ExpenseListNotifier(repo);
      addTearDown(notifier.dispose);
      final other = _expense(id: 'exp-2', status: ReimbursementStatus.none);
      notifier.addExpense(other);
      notifier.addExpense(_expense());

      await notifier.changeReimbursementStatus(
        expense: _expense(),
        newStatus: ReimbursementStatus.reimbursed,
      );

      final inList = notifier.getExpenseById('exp-1')!;
      expect(inList.reimbursementStatus, ReimbursementStatus.reimbursed);
      expect(inList.reimbursedAt, serverReimbursedAt);
      expect(notifier.getExpenseById('exp-2'), same(other));
    });

    test('revert reimbursed -> none sends status none', () async {
      final repo = _FakeExpenseRepository();
      repo.serverEntity = _expense(status: ReimbursementStatus.none);
      final notifier = ExpenseListNotifier(repo);
      addTearDown(notifier.dispose);

      final result = await notifier.changeReimbursementStatus(
        expense: _expense(
          status: ReimbursementStatus.reimbursed,
          reimbursedAt: DateTime.utc(2026, 9, 1),
        ),
        newStatus: ReimbursementStatus.none,
      );

      expect(repo.calls.single.status, ReimbursementStatus.none);
      expect(result.isRight(), isTrue);
    });

    test('repository failure is returned and list is not changed', () async {
      final repo = _FakeExpenseRepository(
        failure: const ServerFailure('offline'),
      );
      final notifier = ExpenseListNotifier(repo);
      addTearDown(notifier.dispose);
      final original = _expense();
      notifier.addExpense(original);

      final result = await notifier.changeReimbursementStatus(
        expense: original,
        newStatus: ReimbursementStatus.reimbursed,
      );

      expect(repo.calls, hasLength(1));
      expect(result.isLeft(), isTrue);
      expect(notifier.getExpenseById('exp-1'), same(original));
    });
  });
}
