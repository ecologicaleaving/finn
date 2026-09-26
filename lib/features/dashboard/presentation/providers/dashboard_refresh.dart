import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../expenses/presentation/providers/expense_provider.dart';
import '../widgets/expenses_chart_widget.dart';
import '../widgets/personal_dashboard_view.dart';
import 'dashboard_provider.dart';

/// Tutti i provider osservati dalla dashboard personale / di gruppo
/// (PersonalDashboardView e relativi bottom sheet) che devono essere
/// ricaricati quando cambiano le spese.
///
/// Sono in gran parte `FutureProvider.autoDispose.family`: invalidare una
/// family non osservata è un no-op, quindi è sicuro invalidarle tutte.
final List<ProviderOrFamily> personalDashboardProviders = [
  expensesByPeriodProvider,
  personalExpensesByCategoryProvider,
  personalOnlyExpensesByCategoryProvider,
  groupMembersExpensesProvider,
  groupExpensesByCategoryProvider,
  memberGroupExpensesByCategoryProvider,
  groupCategoryExpensesProvider,
  personalCategoryExpensesProvider,
  expensesByCategoryProvider,
  recentPersonalExpensesProvider,
  recentGroupExpensesProvider,
];

/// Invalida tutti i [personalDashboardProviders] tramite [invalidate].
///
/// Separato dall'helper UI per poter essere testato senza widget.
void invalidatePersonalDashboardProviders(
  void Function(ProviderOrFamily provider) invalidate,
) {
  for (final provider in personalDashboardProviders) {
    invalidate(provider);
  }
}

/// Ricarica la dashboard: invalida i provider della dashboard personale e poi
/// aggiorna le statistiche di [dashboardProvider].
///
/// Unico punto dell'app da cui chiamare `dashboardProvider.notifier.refresh()`.
Future<void> refreshPersonalDashboard(WidgetRef ref) async {
  invalidatePersonalDashboardProviders(ref.invalidate);
  await ref.read(dashboardProvider.notifier).refresh();
}
