import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_expense_tracker/features/expenses/domain/entities/expense_entity.dart';
import 'package:family_expense_tracker/features/expenses/presentation/widgets/expense_category_summary.dart';

ExpenseEntity _makeExpense({
  required String id,
  required double amount,
  required String categoryName,
}) {
  return ExpenseEntity(
    id: id,
    groupId: 'group-1',
    createdBy: 'user-1',
    amount: amount,
    date: DateTime(2026, 3, 1),
    paymentMethodId: 'pm-1',
    categoryName: categoryName,
  );
}

Widget _buildWidget(List<ExpenseEntity> expenses) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ExpenseCategorySummary(expenses: expenses),
      ),
    ),
  );
}

void main() {
  group('ExpenseCategorySummary', () {
    testWidgets('all categories reachable by scrolling in panel', (tester) async {
      final expenses = [
        _makeExpense(id: '1', amount: 318.00, categoryName: 'Bollette'),
        _makeExpense(id: '2', amount: 292.00, categoryName: 'Spesa'),
        _makeExpense(id: '3', amount: 100.80, categoryName: 'Trasporti'),
        _makeExpense(id: '4', amount: 87.00, categoryName: 'Salute'),
        _makeExpense(id: '5', amount: 50.00, categoryName: 'Abbigliamento'),
        _makeExpense(id: '6', amount: 30.00, categoryName: 'Svago'),
      ];

      await tester.pumpWidget(_buildWidget(expenses));

      // First categories visible immediately
      expect(find.text('Bollette'), findsOneWidget);
      expect(find.text('Spesa'), findsOneWidget);

      // Scroll the internal ListView to reveal all categories
      final listView = find.descendant(
        of: find.byType(Card),
        matching: find.byType(Scrollable),
      );

      for (final name in ['Trasporti', 'Salute', 'Abbigliamento', 'Svago']) {
        await tester.scrollUntilVisible(
          find.text(name),
          100,
          scrollable: listView,
        );
        expect(find.text(name), findsOneWidget);
      }
    });

    testWidgets('shows correct total amount', (tester) async {
      final expenses = [
        _makeExpense(id: '1', amount: 318.00, categoryName: 'Bollette'),
        _makeExpense(id: '2', amount: 292.00, categoryName: 'Spesa'),
        _makeExpense(id: '3', amount: 100.80, categoryName: 'Trasporti'),
      ];

      await tester.pumpWidget(_buildWidget(expenses));

      // Total should show €710.80
      expect(find.textContaining('710,80'), findsOneWidget);
    });

    testWidgets('shows nothing when expense list is empty', (tester) async {
      await tester.pumpWidget(_buildWidget([]));

      expect(find.text('Riepilogo per Categoria'), findsNothing);
    });

    testWidgets('groups multiple expenses under same category', (tester) async {
      final expenses = [
        _makeExpense(id: '1', amount: 50.00, categoryName: 'Spesa'),
        _makeExpense(id: '2', amount: 30.00, categoryName: 'Spesa'),
        _makeExpense(id: '3', amount: 20.00, categoryName: 'Trasporti'),
      ];

      await tester.pumpWidget(_buildWidget(expenses));

      // Only 2 category rows, not 3
      expect(find.text('Spesa'), findsOneWidget);
      expect(find.text('Trasporti'), findsOneWidget);
    });

    testWidgets('uses scrollable ListView inside Card for categories', (tester) async {
      final expenses = [
        _makeExpense(id: '1', amount: 100.00, categoryName: 'Bollette'),
        _makeExpense(id: '2', amount: 200.00, categoryName: 'Spesa'),
      ];

      await tester.pumpWidget(_buildWidget(expenses));

      // The Card should contain a scrollable ListView for categories
      final card = find.byType(Card);
      expect(card, findsOneWidget);

      final listViews = find.descendant(
        of: card,
        matching: find.byType(ListView),
      );
      expect(listViews, findsOneWidget);
    });

    testWidgets('all categories reachable by scrolling', (tester) async {
      // Create many categories to exceed max height (200px)
      final expenses = List.generate(
        10,
        (i) => _makeExpense(
          id: '$i',
          amount: (10 - i) * 50.0,
          categoryName: 'Categoria $i',
        ),
      );

      await tester.pumpWidget(_buildWidget(expenses));

      // First categories should be visible
      expect(find.text('Categoria 0'), findsOneWidget);

      // Last category may need scrolling — find the ListView and scroll
      final listView = find.descendant(
        of: find.byType(Card),
        matching: find.byType(ListView),
      );
      expect(listView, findsOneWidget);

      // Scroll to the bottom of the category list
      await tester.scrollUntilVisible(
        find.text('Categoria 9'),
        100,
        scrollable: find.descendant(
          of: listView,
          matching: find.byType(Scrollable),
        ),
      );

      expect(find.text('Categoria 9'), findsOneWidget);
    });
  });
}
