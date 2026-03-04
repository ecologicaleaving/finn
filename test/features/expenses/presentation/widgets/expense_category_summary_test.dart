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
    testWidgets('shows all categories when many are present', (tester) async {
      final expenses = [
        _makeExpense(id: '1', amount: 318.00, categoryName: 'Bollette'),
        _makeExpense(id: '2', amount: 292.00, categoryName: 'Spesa'),
        _makeExpense(id: '3', amount: 100.80, categoryName: 'Trasporti'),
        _makeExpense(id: '4', amount: 87.00, categoryName: 'Salute'),
        _makeExpense(id: '5', amount: 50.00, categoryName: 'Abbigliamento'),
        _makeExpense(id: '6', amount: 30.00, categoryName: 'Svago'),
      ];

      await tester.pumpWidget(_buildWidget(expenses));

      // All 6 categories must be visible — no silent truncation
      expect(find.text('Bollette'), findsOneWidget);
      expect(find.text('Spesa'), findsOneWidget);
      expect(find.text('Trasporti'), findsOneWidget);
      expect(find.text('Salute'), findsOneWidget);
      expect(find.text('Abbigliamento'), findsOneWidget);
      expect(find.text('Svago'), findsOneWidget);
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

    testWidgets('does not use ListView (no nested scroll)', (tester) async {
      final expenses = [
        _makeExpense(id: '1', amount: 100.00, categoryName: 'Bollette'),
        _makeExpense(id: '2', amount: 200.00, categoryName: 'Spesa'),
      ];

      await tester.pumpWidget(_buildWidget(expenses));

      // The widget should NOT contain any ListView inside the Card
      final card = find.byType(Card);
      expect(card, findsOneWidget);

      // No ListView descendant within the Card
      final listViews = find.descendant(
        of: card,
        matching: find.byType(ListView),
      );
      expect(listViews, findsNothing);
    });
  });
}
