import 'package:flutter_test/flutter_test.dart';
import 'package:family_expense_tracker/core/utils/budget_validator.dart';
import 'package:family_expense_tracker/features/budgets/domain/entities/budget_composition_entity.dart';
import 'package:family_expense_tracker/features/budgets/domain/entities/budget_validation_issue_entity.dart';
import 'package:family_expense_tracker/features/budgets/domain/entities/category_budget_with_members_entity.dart';

CategoryBudgetWithMembers _category({
  required String id,
  required String name,
  required int amount,
  int spent = 0,
}) {
  return CategoryBudgetWithMembers(
    categoryId: id,
    categoryName: name,
    categoryColor: 0xFF000000,
    groupBudgetId: 'budget-$id',
    groupBudgetAmount: amount,
    memberContributions: const [],
    stats: CategoryStats.fromAmounts(budgetAmount: amount, spentAmount: spent),
    month: 9,
    year: 2026,
  );
}

BudgetComposition _composition(List<CategoryBudgetWithMembers> categories) {
  final total = categories.fold<int>(0, (s, c) => s + c.groupBudgetAmount);
  return BudgetComposition(
    calculatedGroupBudget: total,
    categoryBudgets: categories,
    stats: BudgetStats(
      totalCategoryBudgets: total,
      totalSpent: 0,
      totalRemaining: total,
      overallPercentageUsed: 0,
      categoriesWithBudgets: categories.length,
      alertCategoriesCount: 0,
      overBudgetCount: 0,
      nearLimitCount: 0,
    ),
    issues: const [],
    month: 9,
    year: 2026,
    groupId: 'group-1',
  );
}

void main() {
  group('BudgetValidator - category budget amount (issue #50)', () {
    test('Varie with a budget of 0 produces no validation issue', () {
      final composition = _composition([
        _category(id: 'spesa', name: 'Spesa', amount: 40000),
        _category(id: 'varie', name: 'Varie', amount: 0),
      ]);

      final issues = BudgetValidator.validateComposition(composition);

      expect(issues.where((i) => i.severity == Severity.error), isEmpty);
      expect(issues, isEmpty);
    });

    test('Varie at 0 with spending still produces no validation error', () {
      final composition = _composition([
        _category(id: 'spesa', name: 'Spesa', amount: 40000),
        _category(id: 'varie', name: 'Varie', amount: 0, spent: 1500),
      ]);

      final issues = BudgetValidator.validateComposition(composition);

      expect(issues.where((i) => i.isError), isEmpty);
    });

    test('negative category budget is still an error', () {
      final composition = _composition([
        _category(id: 'spesa', name: 'Spesa', amount: 40000),
        _category(id: 'bad', name: 'Bad', amount: -100),
      ]);

      final issues = BudgetValidator.validateComposition(composition);

      expect(
        issues.where((i) => i.isError && i.type == IssueType.invalidAmount),
        isNotEmpty,
      );
    });

    test('category budget above the maximum is an error', () {
      final composition = _composition([
        _category(
          id: 'huge',
          name: 'Huge',
          amount: BudgetValidator.MAX_BUDGET_CENTS + 1,
        ),
      ]);

      final issues = BudgetValidator.validateComposition(composition);

      expect(
        issues.where((i) => i.isError && i.type == IssueType.invalidAmount),
        isNotEmpty,
      );
    });

    test('normal budget without member contributions has no issues', () {
      final composition = _composition([
        _category(id: 'spesa', name: 'Spesa', amount: 40000),
      ]);

      expect(BudgetValidator.validateComposition(composition), isEmpty);
    });
  });
}
