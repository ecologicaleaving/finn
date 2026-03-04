import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_expense_tracker/features/expenses/domain/entities/expense_entity.dart';
import 'package:family_expense_tracker/features/expenses/presentation/providers/expense_provider.dart';
import 'package:family_expense_tracker/features/expenses/presentation/screens/expense_tabs_screen.dart';
import 'package:family_expense_tracker/features/expenses/presentation/widgets/expense_category_summary.dart';
import 'package:family_expense_tracker/features/auth/presentation/providers/auth_provider.dart';
import 'package:family_expense_tracker/features/auth/domain/repositories/auth_repository.dart';
import 'package:family_expense_tracker/features/expenses/domain/repositories/expense_repository.dart';
import 'package:family_expense_tracker/features/groups/presentation/providers/group_provider.dart';

/// Helper to create a test expense entity
ExpenseEntity _makeExpense({
  required String id,
  String categoryName = 'Alimentari',
  double amount = 25.0,
  DateTime? date,
}) {
  return ExpenseEntity(
    id: id,
    groupId: 'group-1',
    createdBy: 'user-1',
    amount: amount,
    date: date ?? DateTime(2026, 3, 1),
    categoryName: categoryName,
    paymentMethodId: 'pm-1',
  );
}

/// Builds a testable widget tree with overridden providers
Widget _buildTestWidget({
  required List<ExpenseEntity> expenses,
  Size screenSize = const Size(360, 640),
}) {
  final listState = ExpenseListState(
    status: ExpenseListStatus.loaded,
    expenses: expenses,
    hasMore: false,
  );

  return ProviderScope(
    overrides: [
      expenseListProvider.overrideWith((ref) {
        return _FakeExpenseListNotifier(listState);
      }),
      authProvider.overrideWith((ref) {
        return _FakeAuthNotifier();
      }),
      isGroupAdminProvider.overrideWithValue(false),
      currentUserProvider.overrideWithValue(null),
    ],
    child: MediaQuery(
      data: MediaQueryData(size: screenSize),
      child: const MaterialApp(
        home: ExpenseTabsScreen(),
      ),
    ),
  );
}

/// Fake notifier for expense list provider
class _FakeExpenseListNotifier extends ExpenseListNotifier {
  _FakeExpenseListNotifier(this._initialState) : super(_FakeExpenseRepository());

  final ExpenseListState _initialState;

  @override
  ExpenseListState get state => _initialState;

  @override
  set state(ExpenseListState value) {
    // no-op in tests
  }

  @override
  Future<void> loadExpenses({bool refresh = false}) async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> loadMore() async {}

  @override
  void clearFilters() {}

  @override
  void clearIsGroupExpenseFilter() {}

  @override
  void setFilterIsGroupExpense(bool? value) {}

  @override
  void setFilterCategory(String? categoryId) {}

  @override
  void setFilterDateRange(DateTime? start, DateTime? end) {}
}

/// Fake auth notifier
class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier() : super(_FakeAuthRepository());

  @override
  AuthState get state => const AuthState(status: AuthStatus.unauthenticated);

  @override
  set state(AuthState value) {}
}

/// Minimal fake repository (not used, just satisfies constructor)
class _FakeExpenseRepository implements ExpenseRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeAuthRepository implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('ExpenseTabsScreen - Layout overflow', () {
    testWidgets('renders without overflow when expense list is empty', (tester) async {
      // Small screen: 360x640dp
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildTestWidget(
        expenses: [],
        screenSize: const Size(360, 640),
      ));
      await tester.pumpAndSettle();

      // Should show filter chips
      expect(find.text('Tutte'), findsOneWidget);
      expect(find.text('Personali'), findsOneWidget);
      expect(find.text('Di Gruppo'), findsOneWidget);

      // No overflow errors (test framework would fail if overflow occurred)
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without overflow with many categories on small screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Create expenses across many categories to make category summary tall
      final expenses = [
        _makeExpense(id: '1', categoryName: 'Alimentari', amount: 100),
        _makeExpense(id: '2', categoryName: 'Trasporti', amount: 80),
        _makeExpense(id: '3', categoryName: 'Utenze', amount: 60),
        _makeExpense(id: '4', categoryName: 'Salute', amount: 50),
        _makeExpense(id: '5', categoryName: 'Svago', amount: 40),
        _makeExpense(id: '6', categoryName: 'Casa', amount: 30),
        _makeExpense(id: '7', categoryName: 'Abbigliamento', amount: 20),
        _makeExpense(id: '8', categoryName: 'Istruzione', amount: 15),
        _makeExpense(id: '9', categoryName: 'Regali', amount: 10),
        _makeExpense(id: '10', categoryName: 'Sport', amount: 5),
      ];

      await tester.pumpWidget(_buildTestWidget(
        expenses: expenses,
        screenSize: const Size(360, 640),
      ));
      await tester.pumpAndSettle();

      // Category summary should be visible
      expect(find.byType(ExpenseCategorySummary), findsOneWidget);

      // No overflow errors
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without overflow with long expense list', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Create 50 expenses
      final expenses = List.generate(
        50,
        (i) => _makeExpense(
          id: 'exp-$i',
          categoryName: i % 2 == 0 ? 'Alimentari' : 'Trasporti',
          amount: 10.0 + i,
          date: DateTime(2026, 3, 1).subtract(Duration(days: i)),
        ),
      );

      await tester.pumpWidget(_buildTestWidget(
        expenses: expenses,
        screenSize: const Size(360, 640),
      ));
      await tester.pumpAndSettle();

      // Should render without overflow
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without overflow on large screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final expenses = List.generate(
        10,
        (i) => _makeExpense(
          id: 'exp-$i',
          categoryName: 'Cat-$i',
          amount: 10.0 + i,
        ),
      );

      await tester.pumpWidget(_buildTestWidget(
        expenses: expenses,
        screenSize: const Size(412, 892),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('ExpenseTabsScreen - Filter chips', () {
    testWidgets('shows all three filter chips', (tester) async {
      await tester.pumpWidget(_buildTestWidget(expenses: []));
      await tester.pumpAndSettle();

      expect(find.text('Tutte'), findsOneWidget);
      expect(find.text('Personali'), findsOneWidget);
      expect(find.text('Di Gruppo'), findsOneWidget);
    });
  });
}
