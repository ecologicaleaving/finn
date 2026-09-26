import 'package:flutter_test/flutter_test.dart';
import 'package:family_expense_tracker/features/budgets/data/datasources/budget_remote_datasource.dart';

void main() {
  group('groupCategoryBudgetRows (issue #50)', () {
    test('keeps only group budgets and does not double-count personal ones',
        () {
      final rows = [
        {
          'id': 'b1',
          'category_id': 'spesa',
          'amount': 40000,
          'is_group_budget': true,
        },
        {
          'id': 'b2',
          'category_id': 'spesa',
          'amount': 20000,
          'is_group_budget': false,
          'user_id': 'user-a',
        },
        {
          'id': 'b3',
          'category_id': 'spesa',
          'amount': 10000,
          'is_group_budget': false,
          'user_id': 'user-b',
        },
        {
          'id': 'b4',
          'category_id': 'varie',
          'amount': 0,
          'is_group_budget': true,
        },
      ];

      final result = groupCategoryBudgetRows(rows);

      expect(result, hasLength(2));
      final categoryIds = result.map((r) => r['category_id']).toList();
      expect(categoryIds.toSet(), hasLength(categoryIds.length));
      expect(categoryIds, containsAll(['spesa', 'varie']));

      final total =
          result.fold<int>(0, (s, r) => s + (r['amount'] as num).toInt());
      // "Budget Totale" must be the group budget of Spesa only (AC6)
      expect(total, 40000);
      expect(result.firstWhere((r) => r['category_id'] == 'spesa')['id'], 'b1');
    });

    test('a row without is_group_budget is treated as a group budget', () {
      final rows = [
        {'id': 'legacy', 'category_id': 'casa', 'amount': 5000},
      ];

      final result = groupCategoryBudgetRows(rows);

      expect(result, hasLength(1));
      expect(result.single['id'], 'legacy');
    });

    test('duplicate group rows for the same category are collapsed to one',
        () {
      final rows = [
        {
          'id': 'old',
          'category_id': 'spesa',
          'amount': 30000,
          'is_group_budget': true,
          'updated_at': '2026-09-01T10:00:00Z',
        },
        {
          'id': 'new',
          'category_id': 'spesa',
          'amount': 40000,
          'is_group_budget': true,
          'updated_at': '2026-09-10T10:00:00Z',
        },
      ];

      final result = groupCategoryBudgetRows(rows);

      expect(result, hasLength(1));
      expect(result.single['id'], 'new');
      expect(result.single['amount'], 40000);
    });

    test('duplicates without timestamps keep the first occurrence', () {
      final rows = [
        {'id': 'first', 'category_id': 'spesa', 'amount': 1, 'is_group_budget': true},
        {'id': 'second', 'category_id': 'spesa', 'amount': 2, 'is_group_budget': true},
      ];

      final result = groupCategoryBudgetRows(rows);

      expect(result, hasLength(1));
      expect(result.single['id'], 'first');
    });

    test('category with only personal budgets is excluded', () {
      final rows = [
        {
          'id': 'p1',
          'category_id': 'svago',
          'amount': 5000,
          'is_group_budget': false,
          'user_id': 'user-a',
        },
      ];

      expect(groupCategoryBudgetRows(rows), isEmpty);
    });
  });
}
