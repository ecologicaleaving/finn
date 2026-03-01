import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../budgets/presentation/providers/budget_actions_provider.dart';
import '../../../budgets/presentation/widgets/personal_budget_card.dart';
import '../../../expenses/presentation/providers/expense_provider.dart';
import '../../../groups/presentation/providers/group_provider.dart';
import '../../domain/entities/dashboard_stats_entity.dart';
import '../providers/dashboard_provider.dart';
import '../../../categories/presentation/widgets/orphaned_expenses_notification.dart';
import '../widgets/budget_summary_card.dart';
import '../widgets/category_budget_list.dart';
import '../widgets/category_pie_chart.dart';
import '../widgets/member_breakdown_list.dart';
import '../widgets/member_filter.dart';
import '../widgets/period_selector.dart';
import '../widgets/personal_dashboard_view.dart';
import '../widgets/recent_expenses_list.dart';
import '../widgets/total_summary_card.dart';
import '../widgets/trend_bar_chart.dart';

/// Main dashboard screen showing personal view only.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardState = ref.watch(dashboardProvider);
    final groupState = ref.watch(groupProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: dashboardState.isLoading
                ? null
                : () => ref.read(dashboardProvider.notifier).refresh(),
            tooltip: 'Aggiorna',
          ),
        ],
      ),
      body: _DashboardContent(
        dashboardState: dashboardState,
        members: groupState.members,
        isPersonalView: true,
        onRefresh: () => ref.read(dashboardProvider.notifier).refresh(),
        onPeriodChanged: (period) =>
            ref.read(dashboardProvider.notifier).setPeriod(period),
        onNavigatePrevious: () =>
            ref.read(dashboardProvider.notifier).navigatePrevious(),
        onNavigateNext: () =>
            ref.read(dashboardProvider.notifier).navigateNext(),
        groupId: groupState.group?.id ?? '',
      ),
    );
  }
}

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent({
    required this.dashboardState,
    required this.members,
    required this.isPersonalView,
    required this.onRefresh,
    required this.onPeriodChanged,
    required this.onNavigatePrevious,
    required this.onNavigateNext,
    this.onMemberFilterChanged,
    required this.groupId,
  });

  final DashboardState dashboardState;
  final List<dynamic> members;
  final bool isPersonalView;
  final VoidCallback onRefresh;
  final ValueChanged<DashboardPeriod> onPeriodChanged;
  final VoidCallback onNavigatePrevious;
  final VoidCallback onNavigateNext;
  final ValueChanged<String?>? onMemberFilterChanged;
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (dashboardState.status == DashboardStatus.error &&
        dashboardState.stats == null) {
      return ErrorDisplay(
        message: dashboardState.errorMessage ?? 'Errore nel caricamento',
        onRetry: onRefresh,
      );
    }

    if (dashboardState.status == DashboardStatus.loading &&
        dashboardState.stats == null) {
      return const LoadingIndicator(message: 'Caricamento dati...');
    }

    final stats = dashboardState.stats;

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Orphaned expenses notification (Feature 004)
            if (!isPersonalView) const OrphanedExpensesNotification(),

            // Period selector
            Center(
              child: PeriodSelector(
                selectedPeriod: dashboardState.period,
                onPeriodChanged: onPeriodChanged,
              ),
            ),
            const SizedBox(height: 12),

            // Period navigator
            PeriodNavigator(
              period: dashboardState.period,
              offset: dashboardState.offset,
              onPrevious: onNavigatePrevious,
              onNext: onNavigateNext,
            ),
            const SizedBox(height: 16),

            // Member filter (group view only)
            if (!isPersonalView && onMemberFilterChanged != null) ...[
              MemberFilterChips(
                members: members.cast(),
                selectedMemberId: dashboardState.selectedMemberId,
                onMemberChanged: onMemberFilterChanged!,
              ),
              const SizedBox(height: 16),
            ],

            // Error banner if we have stale data
            if (dashboardState.errorMessage != null && stats != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dati non aggiornati. Tocca per riprovare.',
                        style: TextStyle(color: Colors.amber.shade900),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: onRefresh,
                      color: Colors.amber.shade900,
                    ),
                  ],
                ),
              ),

            // Budget cards
            if (!isPersonalView) ...[
              // Group view - show all group-related budget widgets
              Consumer(
                builder: (context, ref, child) {
                  final group = ref.watch(currentGroupProvider);
                  final userId = ref.watch(currentUserIdProvider);
                  final dashboardState = ref.watch(dashboardProvider);

                  if (group == null) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Icon(Icons.group_off, size: 48, color: Colors.grey),
                            const SizedBox(height: 8),
                            Text(
                              'Nessun gruppo disponibile',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Crea o unisciti a un gruppo per visualizzare il budget',
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: [
                      // Category budget summary (Feature 004)
                      BudgetSummaryCard(
                        onTap: () {
                          context.push('/budget');
                        },
                        period: dashboardState.period,
                        offset: dashboardState.offset,
                      ),
                      const SizedBox(height: 16),

                      // Category budget list (Feature 004)
                      CategoryBudgetList(
                        maxItems: 5,
                        onViewAll: () {
                          context.push('/budget');
                        },
                        period: dashboardState.period,
                        offset: dashboardState.offset,
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
            ] else ...[
              // Personal dashboard view with unified card
              const PersonalDashboardView(),
              const SizedBox(height: 16),
            ],

            // Summary card - only for group view
            if (!isPersonalView && stats != null) ...[
              TotalSummaryCard(
                stats: stats,
                isPersonalView: isPersonalView,
              ),
              const SizedBox(height: 16),

              // Empty state
              if (stats.isEmpty)
                EmptyDisplay(
                  icon: Icons.receipt_long,
                  message: 'Nessuna spesa del gruppo in questo periodo',
                  actionLabel: 'Aggiungi spesa',
                  action: () {
                    Navigator.of(context).pushNamed('/add-expense');
                  },
                )
              else ...[
                // Category breakdown
                CategoryPieChart(categories: stats.byCategory),
                const SizedBox(height: 16),

                // Trend chart
                TrendBarChart(
                  trend: stats.trend,
                  period: stats.period,
                ),
                const SizedBox(height: 16),

                // Member breakdown (group view only)
                if (stats.byMember.isNotEmpty)
                  MemberBreakdownList(
                    members: stats.byMember,
                    onMemberTap: onMemberFilterChanged,
                  ),
              ],
            ],

            // Loading overlay
            if (dashboardState.isLoading && stats != null)
              Container(
                padding: const EdgeInsets.all(16),
                child: const Center(
                  child: InlineLoadingIndicator(
                    size: 24,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
