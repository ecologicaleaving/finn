import 'package:dartz/dartz.dart';
import 'package:family_expense_tracker/core/enums/reimbursement_status.dart';
import 'package:family_expense_tracker/core/errors/failures.dart';
import 'package:family_expense_tracker/features/expenses/domain/entities/expense_entity.dart';
import 'package:family_expense_tracker/features/expenses/domain/repositories/expense_repository.dart';
import 'package:family_expense_tracker/features/expenses/presentation/providers/expense_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parameters of one getExpenses call.
class _Query {
  _Query({
    this.startDate,
    this.endDate,
    this.categoryId,
    this.createdBy,
    this.isGroupExpense,
    this.reimbursementStatus,
  });

  final DateTime? startDate;
  final DateTime? endDate;
  final String? categoryId;
  final String? createdBy;
  final bool? isGroupExpense;
  final ReimbursementStatus? reimbursementStatus;
}

class _RecordingExpenseRepository implements ExpenseRepository {
  final List<_Query> queries = [];

  _Query get last => queries.last;

  @override
  Future<Either<Failure, List<ExpenseEntity>>> getExpenses({
    DateTime? startDate,
    DateTime? endDate,
    String? categoryId,
    String? createdBy,
    String? paidBy,
    bool? isGroupExpense,
    ReimbursementStatus? reimbursementStatus,
    int? limit,
    int? offset,
  }) async {
    queries.add(_Query(
      startDate: startDate,
      endDate: endDate,
      categoryId: categoryId,
      createdBy: createdBy,
      isGroupExpense: isGroupExpense,
      reimbursementStatus: reimbursementStatus,
    ));
    return const Right([]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('ExpenseListState.copyWith (issue #48)', () {
    final start = DateTime(2026, 9, 1);
    final end = DateTime(2026, 9, 30);
    final filtered = ExpenseListState(
      filterCategoryId: 'c1',
      filterStartDate: start,
      filterEndDate: end,
      filterCreatedBy: 'u1',
      filterReimbursementStatus: ReimbursementStatus.reimbursable,
      filterIsGroupExpense: false,
    );

    test('filters not passed are kept', () {
      final copy = filtered.copyWith(status: ExpenseListStatus.loaded);
      expect(copy.filterCategoryId, 'c1');
      expect(copy.filterStartDate, start);
      expect(copy.filterEndDate, end);
      expect(copy.filterCreatedBy, 'u1');
      expect(copy.filterReimbursementStatus, ReimbursementStatus.reimbursable);
      expect(copy.filterIsGroupExpense, false);
    });

    test('filters passed as explicit null are cleared', () {
      final copy = filtered.copyWith(
        filterCategoryId: null,
        filterStartDate: null,
        filterEndDate: null,
        filterCreatedBy: null,
        filterReimbursementStatus: null,
        filterIsGroupExpense: null,
      );
      expect(copy.filterCategoryId, isNull);
      expect(copy.filterStartDate, isNull);
      expect(copy.filterEndDate, isNull);
      expect(copy.filterCreatedBy, isNull);
      expect(copy.filterReimbursementStatus, isNull);
      expect(copy.filterIsGroupExpense, isNull);
    });

    test('filters can be replaced with new values', () {
      final copy = filtered.copyWith(
        filterCategoryId: 'c2',
        filterIsGroupExpense: true,
      );
      expect(copy.filterCategoryId, 'c2');
      expect(copy.filterIsGroupExpense, true);
      expect(copy.filterCreatedBy, 'u1');
    });
  });

  group('ExpenseListNotifier filter setters (AC1/AC2)', () {
    late _RecordingExpenseRepository repository;
    late ExpenseListNotifier notifier;

    setUp(() {
      repository = _RecordingExpenseRepository();
      notifier = ExpenseListNotifier(repository);
    });

    tearDown(() => notifier.dispose());

    test('setFilterCategory(null) clears the category filter', () async {
      notifier.setFilterCategory('c1');
      await _settle();
      expect(notifier.state.filterCategoryId, 'c1');
      expect(repository.last.categoryId, 'c1');

      notifier.setFilterCategory(null);
      await _settle();
      expect(notifier.state.filterCategoryId, isNull);
      expect(repository.last.categoryId, isNull);
    });

    test('setFilterDateRange(null, null) clears the date range', () async {
      notifier.setFilterDateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 30));
      await _settle();
      expect(notifier.state.filterStartDate, isNotNull);

      notifier.setFilterDateRange(null, null);
      await _settle();
      expect(notifier.state.filterStartDate, isNull);
      expect(notifier.state.filterEndDate, isNull);
      expect(repository.last.startDate, isNull);
      expect(repository.last.endDate, isNull);
    });

    test('tab Personali then Tutte: clearIsGroupExpenseFilter shows all',
        () async {
      notifier.setFilterIsGroupExpense(false);
      await _settle();
      expect(repository.last.isGroupExpense, false);

      notifier.clearIsGroupExpenseFilter();
      await _settle();
      expect(notifier.state.filterIsGroupExpense, isNull);
      expect(repository.last.isGroupExpense, isNull);
    });

    test('setFilterIsGroupExpense(null) clears the group filter', () async {
      notifier.setFilterIsGroupExpense(true);
      await _settle();
      notifier.setFilterIsGroupExpense(null);
      await _settle();
      expect(notifier.state.filterIsGroupExpense, isNull);
      expect(repository.last.isGroupExpense, isNull);
    });

    test('setFilterCreatedBy(null) and setFilterReimbursementStatus(null) clear',
        () async {
      notifier.setFilterCreatedBy('u1');
      notifier.setFilterReimbursementStatus(ReimbursementStatus.reimbursable);
      await _settle();

      notifier.setFilterCreatedBy(null);
      notifier.setFilterReimbursementStatus(null);
      await _settle();
      expect(notifier.state.filterCreatedBy, isNull);
      expect(notifier.state.filterReimbursementStatus, isNull);
      expect(repository.last.createdBy, isNull);
      expect(repository.last.reimbursementStatus, isNull);
    });

    test('loadExpenses and refresh keep the active filters', () async {
      notifier.setFilterCategory('c1');
      notifier.setFilterIsGroupExpense(false);
      await _settle();

      await notifier.refresh();
      expect(notifier.state.filterCategoryId, 'c1');
      expect(notifier.state.filterIsGroupExpense, false);
      expect(repository.last.categoryId, 'c1');
      expect(repository.last.isGroupExpense, false);

      await notifier.loadExpenses();
      expect(repository.last.categoryId, 'c1');
      expect(repository.last.isGroupExpense, false);
    });

    test('list mutations keep the active filters', () async {
      notifier.setFilterCategory('c1');
      await _settle();

      final expense = ExpenseEntity(
        id: 'e1',
        groupId: 'g1',
        createdBy: 'u1',
        amount: 10,
        date: DateTime(2026, 9, 10),
        paymentMethodId: 'pm',
      );
      notifier.addExpense(expense);
      notifier.updateExpenseInList(expense);
      notifier.removeExpenseFromList('e1');
      expect(notifier.state.filterCategoryId, 'c1');
    });
  });
}
