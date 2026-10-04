import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:family_expense_tracker/core/utils/currency_utils.dart';
import 'package:family_expense_tracker/features/budgets/domain/entities/budget_composition_entity.dart';
import 'package:family_expense_tracker/features/budgets/presentation/widgets/budget_overview_card.dart';

BudgetStats _stats(int total) => BudgetStats(
      totalCategoryBudgets: total,
      totalSpent: 0,
      totalRemaining: total,
      overallPercentageUsed: 0,
      categoriesWithBudgets: 1,
      alertCategoriesCount: 0,
      overBudgetCount: 0,
      nearLimitCount: 0,
    );

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('groupBoxBudgetCents (#68)', () {
    test('AC1: somma dei budget di gruppo, senza entrate', () {
      expect(groupBoxBudgetCents(_stats(40000)), 40000);
    });

    test('AC2: mai negativo', () {
      expect(groupBoxBudgetCents(_stats(40000)), greaterThanOrEqualTo(0));
      expect(groupBoxBudgetCents(_stats(0)), 0);
      expect(groupBoxBudgetCents(_stats(-5)), 0);
    });
  });

  testWidgets('AC3: entrate > budget, il riquadro GRUPPO mostra 400 EUR',
      (tester) async {
    final composition = BudgetComposition(
      calculatedGroupBudget: 40000,
      categoryBudgets: const [],
      stats: _stats(40000),
      issues: const [],
      month: 10,
      year: 2026,
      groupId: 'g',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BudgetOverviewCard(
            composition: composition,
            currentUserId: 'u',
            totalIncome: 100000,
          ),
        ),
      ),
    ));
    expect(find.text(CurrencyUtils.formatCentsCompact(40000)), findsWidgets);
    expect(find.text(CurrencyUtils.formatCentsCompact(-60000)), findsNothing);
  });
}
