import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:family_expense_tracker/core/enums/transaction_type.dart';
import 'package:family_expense_tracker/features/expenses/data/models/expense_model.dart';
import 'package:family_expense_tracker/features/expenses/domain/entities/expense_entity.dart';
import 'package:family_expense_tracker/features/expenses/presentation/widgets/monthly_expense_category_view.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it_IT');
    Intl.defaultLocale = 'it_IT';
  });

  Widget buildTestWidget({
    required List<ExpenseEntity> expenses,
    DateTime? initialMonth,
    DateTime Function()? nowBuilder,
    ValueChanged<ExpenseEntity>? onExpenseTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: MonthlyExpenseCategoryView(
          expenses: expenses,
          hasMoreExpenses: false,
          initialMonth: initialMonth,
          nowBuilder: nowBuilder,
          onExpenseTap: onExpenseTap,
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

    testWidgets('category detail shows the saved note without a merchant', (tester) async {
      final savedExpense = _savedExpense(
        id: 'current-food',
        notes: '  Spesa settimanale  ',
      );
      ExpenseEntity? openedExpense;
      await tester.pumpWidget(buildTestWidget(
        expenses: [
          savedExpense,
          _savedExpense(id: 'old-food', notes: 'Spesa ottobre', date: '2026-10-08'),
          _savedExpense(id: 'current-travel', notes: 'Abbonamento treno', categoryName: 'Trasporti'),
        ],
        nowBuilder: () => DateTime(2026, 11, 9),
        onExpenseTap: (expense) => openedExpense = expense,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cibo'));
      await tester.pumpAndSettle();

      expect(find.text('Spesa settimanale'), findsOneWidget);
      expect(find.text('Spesa ottobre'), findsNothing);
      expect(find.text('Abbonamento treno'), findsNothing);
      expect(find.text('Spesa senza nome'), findsNothing);
      await tester.tap(find.text('Spesa settimanale'));
      await tester.pumpAndSettle();
      expect(openedExpense, same(savedExpense));
    });

    final titleCases = [
      (
        label: 'prefers the saved note to a legacy merchant',
        notes: '  Materiale scolastico  ',
        merchant: 'Negozio storico',
        categoryName: 'Cibo',
        category: 'Cibo',
        title: 'Materiale scolastico',
      ),
      (
        label: 'uses a legacy merchant when notes are blank',
        notes: ' \n\t ',
        merchant: '  Negozio storico  ',
        categoryName: 'Cibo',
        category: 'Cibo',
        title: 'Negozio storico',
      ),
      (
        label: 'uses the category when both optional text fields are empty',
        notes: null,
        merchant: '   ',
        categoryName: ' Cibo ',
        category: 'Cibo',
        title: 'Cibo',
      ),
      (
        label: 'uses a neutral expense label when no descriptive data exists',
        notes: ' ',
        merchant: null,
        categoryName: null,
        category: 'Altro',
        title: 'Spesa',
      ),
    ];
    for (final example in titleCases) {
      testWidgets('category detail ${example.label}', (tester) async {
        final savedExpense = _savedExpense(
          id: 'saved-expense',
          notes: example.notes,
          merchant: example.merchant,
          categoryName: example.categoryName,
        );
        ExpenseEntity? openedExpense;
        await tester.pumpWidget(buildTestWidget(
          expenses: [savedExpense],
          nowBuilder: () => DateTime(2026, 11, 9),
          onExpenseTap: (expense) => openedExpense = expense,
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.text(example.category));
        await tester.pumpAndSettle();

        final title = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text(example.title),
        );
        expect(title, findsWidgets);
        expect(find.text('Spesa senza nome'), findsNothing);
        // When the title is the category, tap the expense row, not the sheet header.
        await tester.tap(title.last);
        await tester.pumpAndSettle();
        expect(openedExpense, same(savedExpense));
      });
    }

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

    testWidgets('le entrate non entrano nei totali del mese ne\' delle categorie', (tester) async {
      final expenses = [
        _expense(
          id: '1',
          categoryName: 'Cibo',
          amount: 10.0,
          date: DateTime(2026, 3, 10),
          merchant: 'Conad',
        ),
        _expense(
          id: '2',
          categoryName: 'Cibo',
          amount: 100.0,
          date: DateTime(2026, 3, 11),
          merchant: 'Rimborso',
          transactionType: TransactionType.income,
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

      expect(find.text('Totale personale: ${format.format(10.0)}'), findsOneWidget);
      expect(find.text('Cibo'), findsOneWidget);
      expect(find.text(format.format(10.0)), findsOneWidget);
      expect(find.text(format.format(110.0)), findsNothing);
      expect(find.text('1 spesa'), findsOneWidget);

      await tester.tap(find.text('Cibo'));
      await tester.pumpAndSettle();

      expect(find.text('Conad'), findsOneWidget);
      expect(find.text('Rimborso'), findsNothing);
    });

    testWidgets('mese con sole entrate mostra stato vuoto', (tester) async {
      final expenses = [
        _expense(
          id: '1',
          categoryName: 'Stipendio',
          amount: 1500.0,
          date: DateTime(2026, 3, 1),
          merchant: 'Azienda',
          transactionType: TransactionType.income,
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
      expect(find.text('Nessuna spesa questo mese'), findsOneWidget);
      expect(find.text('Stipendio'), findsNothing);
    });
  });
}

ExpenseEntity _savedExpense({
  required String id,
  String? notes,
  String? merchant,
  String? categoryName = 'Cibo',
  String date = '2026-11-08',
}) {
  return ExpenseModel.fromJson({
    'id': id,
    'group_id': 'group',
    'created_by': 'user',
    'amount': 24.90,
    'date': date,
    'category_id': categoryName?.trim().toLowerCase(),
    'category_name': categoryName,
    'payment_method_id': 'pm',
    'payment_method_name': 'Carta',
    'is_group_expense': false,
    'merchant': merchant,
    'notes': notes,
  });
}

ExpenseEntity _expense({
  required String id,
  required String categoryName,
  required double amount,
  required DateTime date,
  required String merchant,
  TransactionType transactionType = TransactionType.expense,
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
    transactionType: transactionType,
  );
}
