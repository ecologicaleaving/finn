import 'package:family_expense_tracker/features/expenses/data/datasources/expense_remote_datasource.dart';
import 'package:family_expense_tracker/features/expenses/domain/entities/expense_entity.dart';
import 'package:family_expense_tracker/features/expenses/domain/utils/expense_ordering.dart';
import 'package:flutter_test/flutter_test.dart';

ExpenseEntity _e(String id, DateTime date, {DateTime? createdAt}) =>
    ExpenseEntity(
      id: id,
      groupId: 'g',
      createdBy: 'u',
      amount: 1,
      date: date,
      categoryId: 'c',
      paymentMethodId: 'cash',
      isGroupExpense: true,
      createdAt: createdAt,
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  final d = DateTime(2026, 9, 1);

  test('date descending first', () {
    final a = _e('a', DateTime(2026, 9, 2));
    final b = _e('b', DateTime(2026, 9, 1));
    expect(compareExpensesNewestFirst(a, b), lessThan(0));
    expect(compareExpensesNewestFirst(b, a), greaterThan(0));
  });

  test('same date: createdAt descending', () {
    final older = _e('z', d, createdAt: DateTime(2026, 9, 1, 8));
    final newer = _e('a', d, createdAt: DateTime(2026, 9, 1, 9));
    expect(compareExpensesNewestFirst(newer, older), lessThan(0));
  });

  test('same date and createdAt: id descending', () {
    final c = DateTime(2026, 9, 1, 8);
    final a = _e('a', d, createdAt: c);
    final b = _e('b', d, createdAt: c);
    expect(compareExpensesNewestFirst(b, a), lessThan(0));
    expect(compareExpensesNewestFirst(a, a), 0);
  });

  test('null createdAt goes last', () {
    final withTs = _e('a', d, createdAt: DateTime(2026, 9, 1));
    final noTs = _e('z', d);
    expect(compareExpensesNewestFirst(withTs, noTs), lessThan(0));
    expect(compareExpensesNewestFirst(noTs, withTs), greaterThan(0));
  });

  test('result is independent of the starting order', () {
    final items = [
      _e('1', d, createdAt: DateTime(2026, 9, 1, 8)),
      _e('2', d, createdAt: DateTime(2026, 9, 1, 8)),
      _e('3', d),
      _e('4', DateTime(2026, 9, 3)),
      _e('5', d, createdAt: DateTime(2026, 9, 1, 9)),
    ];
    final first = [...items]..sort(compareExpensesNewestFirst);
    final second = [...items.reversed]..sort(compareExpensesNewestFirst);
    final third = [items[2], items[4], items[0], items[3], items[1]]
      ..sort(compareExpensesNewestFirst);
    final ids = first.map((e) => e.id).toList();
    expect(ids, ['4', '5', '2', '1', '3']);
    expect(second.map((e) => e.id).toList(), ids);
    expect(third.map((e) => e.id).toList(), ids);
  });

  test('remote query uses the same total order', () {
    expect(ExpenseRemoteDataSourceImpl.expenseListOrdering, [
      ('date', false),
      ('created_at', false),
      ('id', false),
    ]);
  });
}
