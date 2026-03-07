import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:finn/features/expenses/domain/entities/expense_entity.dart';
import 'package:finn/features/expenses/presentation/widgets/monthly_expense_category_view.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it_IT');
    Intl.defaultLocale = 'it_IT';
  });

  Widget buildTestWidget({
    required List<ExpenseEntity> expenses,
    DateTime? initialMonth,
    DateTime Function()? nowBuilder,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: MonthlyExpenseCategoryView(
          expenses: expenses,
          hasMoreExpenses: false,
          initialMonth: initialMonth,
          nowBuilder: nowBuilder,
        ),
      ),
    );
  }

  group('MonthlyExpenseCategoryView', () {
    testWidgets('mostra il mese corrente con categorie e totali', (tester) async {
      final expenses = [
        _expense(
          id: '1',
          categoryName: 'Cibo',
          amount: 40.10,
          date: DateTime(2026, 3, 5),
          merchant: 'Mercato',
        ),
        _expense(
          id: '2',
          categoryName: 'Cibo',
          amount: 79.90,
          date: DateTime(2026, 3, 12),
          merchant: 'Conad',
        ),
        _expense(
          id: '3',
          categoryName: 'Trasporti',
          amount: 45.00,
          date: DateTime(2026, 3, 10),
          merchant: 'Treno',
        ),
      ];

      final format = NumberFormat.currency(locale: 'it_IT', symbol: '\u20ac', decimalDigits: 2);
      await tester.pumpWidget(
        buildTestWidget(
          expenses: expenses,
          nowBuilder: () => DateTime(2026, 3, 15),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Marzo 2026'), findsOneWidget);
      expect(find.text('Totale personale: ${format.format(165.0)}'), findsOneWidget);
      expect(find.text('Cibo'), findsOneWidget);
      expect(find.text('Trasporti'), findsOneWidget);
      expect(find.text(format.format(120.0)), findsOneWidget);
      expect(find.text(format.format(45.0)), findsOneWidget);
    });

    testWidgets('navigazione frecce cambia mese', (tester) async {
      final expenses = [
        _expense(
          id: '1',
          categoryName: 'Cibo',
          amount: 120.0,
          date: DateTime(2026, 3, 10),
          merchant: 'Conad',
        ),
        _expense(
          id: '2',
          categoryName: 'Casa',
          amount: 60.0,
          date: DateTime(2026, 2, 8),
          merchant: 'Ikea',
        ),
      ];

      await tester.pumpWidget(
        buildTestWidget(
          expenses: expenses,
          nowBuilder: () => DateTime(2026, 3, 15),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Marzo 2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Mese precedente'));
      await tester.pumpAndSettle();

      expect(find.text('Febbraio 2026'), findsOneWidget);
      expect(find.text('Casa'), findsOneWidget);

      await tester.tap(find.byTooltip('Mese successivo'));
      await tester.pumpAndSettle();
      expect(find.text('Marzo 2026'), findsOneWidget);
    });

    testWidgets('tap su categoria mostra lista spese del mese', (tester) async {
      final expenses = [
        _expense(
          id: '1',
          categoryName: 'Cibo',
          amount: 70.0,
          date: DateTime(2026, 3, 10),
          merchant: 'Conad',
        ),
        _expense(
          id: '2',
          categoryName: 'Cibo',
          amount: 50.0,
          date: DateTime(2026, 3, 12),
          merchant: 'Mercato',
        ),
        _expense(
          id: '3',
          categoryName: 'Trasporti',
          amount: 30.0,
          date: DateTime(2026, 3, 9),
          merchant: 'Metro',
        ),
      ];

      await tester.pumpWidget(
        buildTestWidget(
          expenses: expenses,
          nowBuilder: () => DateTime(2026, 3, 15),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cibo'));
      await tester.pumpAndSettle();

      expect(find.text('Conad'), findsOneWidget);
      expect(find.text('Mercato'), findsOneWidget);
      expect(find.text('Metro'), findsNothing);
    });

    testWidgets('mese senza spese mostra stato vuoto', (tester) async {
      final expenses = [
        _expense(
          id: '1',
          categoryName: 'Cibo',
          amount: 120.0,
          date: DateTime(2026, 3, 10),
          merchant: 'Conad',
        ),
      ];

      await tester.pumpWidget(
        buildTestWidget(
          expenses: expenses,
          initialMonth: DateTime(2026, 4, 1),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aprile 2026'), findsOneWidget);
      expect(find.text('Nessuna spesa questo mese'), findsOneWidget);
    });
  });
}

ExpenseEntity _expense({
  required String id,
  required String categoryName,
  required double amount,
  required DateTime date,
  required String merchant,
}) {
  return ExpenseEntity(
    id: id,
    groupId: 'group',
    createdBy: 'user',
    amount: amount,
    date: date,
    categoryId: categoryName.toLowerCase(),
    categoryName: categoryName,
    paymentMethodId: 'pm',
    paymentMethodName: 'Carta',
    merchant: merchant,
  );
}
