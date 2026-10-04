import 'package:dartz/dartz.dart';
import 'package:family_expense_tracker/core/enums/reimbursement_status.dart';
import 'package:family_expense_tracker/core/errors/failures.dart';
import 'package:family_expense_tracker/features/expenses/domain/entities/expense_entity.dart';
import 'package:family_expense_tracker/features/expenses/domain/repositories/expense_repository.dart';
import 'package:family_expense_tracker/features/expenses/presentation/providers/expense_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../data/repositories/expense_test_support.dart';

class _RecordingRepository implements ExpenseRepository {
  _RecordingRepository(this.pages);

  /// Pages returned in order.
  final List<List<ExpenseEntity>> pages;
  final List<int?> offsets = [];

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
    offsets.add(offset);
    final index = offsets.length - 1;
    return Right(index < pages.length ? pages[index] : const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<ExpenseEntity> _synced(int from, int count) => [
      for (var i = from; i < from + count; i++)
        makeExpense(
          's${i.toString().padLeft(3, '0')}',
          date: DateTime(2026, 9, 30).subtract(Duration(days: i)),
        ),
    ];

void main() {
  final pending = [
    makeExpense('p1', date: DateTime(2026, 9, 30), syncStatus: 'pending'),
    makeExpense('p2', date: DateTime(2026, 9, 29), syncStatus: 'failed'),
    makeExpense('p3', date: DateTime(2026, 9, 28), syncStatus: 'syncing'),
  ];

  test('offset of the second page ignores pending expenses', () async {
    final repo = _RecordingRepository([
      [...pending, ..._synced(0, 20)],
      _synced(20, 20),
    ]);
    final notifier = ExpenseListNotifier(repo);

    await notifier.loadExpenses(refresh: true);
    expect(notifier.state.expenses.length, 23);
    expect(notifier.state.hasMore, isTrue);

    await notifier.loadMore();
    expect(repo.offsets, [0, 20]);
    expect(notifier.state.expenses.length, 43);
  });

  test('hasMore counts only synced expenses of the page', () async {
    final repo = _RecordingRepository([
      [...pending, ..._synced(0, 5)],
    ]);
    final notifier = ExpenseListNotifier(repo);
    await notifier.loadExpenses(refresh: true);
    // 8 items but only 5 synced: fewer than a page, nothing more to load.
    expect(notifier.state.hasMore, isFalse);
  });

  test('duplicates by id are dropped and the list stays ordered', () async {
    final repo = _RecordingRepository([
      [...pending, ..._synced(0, 20)],
      // The server now returns p1 (synced meanwhile) together with the page.
      [
        makeExpense('p1', date: DateTime(2026, 9, 30), syncStatus: 'completed'),
        ..._synced(20, 19),
      ],
    ]);
    final notifier = ExpenseListNotifier(repo);
    await notifier.loadExpenses(refresh: true);
    await notifier.loadMore();

    final ids = notifier.state.expenses.map((e) => e.id).toList();
    expect(ids.length, ids.toSet().length);
    expect(ids.length, 42);
    expect(
      notifier.state.expenses.firstWhere((e) => e.id == 'p1').syncStatus,
      'completed',
    );
    final sorted = [...notifier.state.expenses]
      ..sort((a, b) => b.date.compareTo(a.date));
    expect(notifier.state.expenses.map((e) => e.date),
        sorted.map((e) => e.date));
  });
}
