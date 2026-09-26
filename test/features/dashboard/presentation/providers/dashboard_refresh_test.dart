import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_expense_tracker/features/dashboard/presentation/providers/dashboard_refresh.dart';
import 'package:family_expense_tracker/features/dashboard/presentation/widgets/expenses_chart_widget.dart';
import 'package:family_expense_tracker/features/dashboard/presentation/widgets/personal_dashboard_view.dart';
import 'package:family_expense_tracker/features/expenses/presentation/providers/expense_provider.dart';

void main() {
  group('invalidatePersonalDashboardProviders', () {
    test('invalida tutti i provider osservati dalla dashboard personale', () {
      final invalidated = <ProviderOrFamily>{};
      invalidatePersonalDashboardProviders(invalidated.add);

      expect(
        invalidated,
        containsAll(<ProviderOrFamily>[
          personalOnlyExpensesByCategoryProvider,
          memberGroupExpensesByCategoryProvider,
          expensesByPeriodProvider,
          personalExpensesByCategoryProvider,
          groupMembersExpensesProvider,
          groupExpensesByCategoryProvider,
          groupCategoryExpensesProvider,
          personalCategoryExpensesProvider,
          expensesByCategoryProvider,
          recentPersonalExpensesProvider,
          recentGroupExpensesProvider,
        ]),
      );
    });
  });

  group('source guard', () {
    test('dashboardProvider.refresh() e\' chiamato solo da dashboard_refresh.dart', () {
      const needle = 'dashboardProvider.notifier).refresh(';
      final offenders = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains(needle))
          .map((f) => f.path.replaceAll('\\', '/'))
          .toList();

      expect(
        offenders,
        ['lib/features/dashboard/presentation/providers/dashboard_refresh.dart'],
        reason: 'Usa refreshPersonalDashboard(ref) invece di chiamare '
            'direttamente dashboardProvider.notifier.refresh(): altrimenti i '
            'provider della dashboard personale non vengono invalidati.',
      );
    });
  });
}
