import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import 'personal_dashboard_view.dart';

/// Widget that displays a bar chart showing expense distribution across group members
class GroupMembersExpensesChart extends ConsumerWidget {
  final String groupId;
  final String period;
  final int offset;

  const GroupMembersExpensesChart({
    required this.groupId,
    required this.period,
    required this.offset,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the provider for group members' expenses data
    final expensesAsyncValue = ref.watch(
      groupMembersExpensesProvider(
        GroupMembersExpensesParams(
          groupId: groupId,
          period: period,
          offset: offset,
        ),
      ),
    );

    return expensesAsyncValue.when(
      loading: () => _buildLoadingState(context),
      error: (error, stackTrace) => _buildErrorState(context, error),
      data: (membersData) => _buildChartWidget(context, membersData),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.textTertiary.withValues(alpha: 0.2),
        ),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.sageGreen),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, Object error) {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Center(
        child: Text(
          'Errore nel caricamento dati',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.error,
          ),
        ),
      ),
    );
  }

  Widget _buildChartWidget(
    BuildContext context,
    List<Map<String, dynamic>>? membersData,
  ) {
    if (membersData == null || membersData.isEmpty) {
      return Container(
        height: 250,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.textTertiary.withValues(alpha: 0.2),
          ),
        ),
        child: Center(
          child: Text(
            'Nessun dato disponibile',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ),
      );
    }

    // Take top 10 members by expense
    final topMembers = membersData.take(10).toList();

    // Calculate max value for chart scaling
    final maxExpense = topMembers.isEmpty
        ? 0.0
        : (topMembers.first['total'] as num?)?.toDouble() ?? 0.0;

    // Build bar chart data
    final barGroups = topMembers.asMap().entries.map((entry) {
      final index = entry.key;
      final member = entry.value;
      final amount = ((member['total'] as num?)?.toDouble() ?? 0.0) / 100;

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: amount,
            color: AppColors.sageGreen,
            width: 16,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(6),
            ),
          ),
        ],
        showingTooltipIndicators: [0],
      );
    }).toList();

    return Container(
      height: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.textTertiary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spese per Membro',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (maxExpense / 100) * 1.1, // Add 10% padding
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    direction: TooltipDirection.top,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final member = topMembers[group.x.toInt()];
                      final name = member['name'] as String?;
                      final amount =
                          ((member['total'] as num?)?.toDouble() ?? 0.0) /
                              100;
                      final formatted = NumberFormat.currency(
                        locale: 'it_IT',
                        symbol: '€',
                      ).format(amount);

                      return BarTooltipItem(
                        '$name\n$formatted',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index >= topMembers.length) {
                          return const SizedBox.shrink();
                        }

                        final member = topMembers[index];
                        final name = (member['name'] as String?) ?? '';

                        return Text(
                          name.length > 8
                              ? name.substring(0, 8)
                              : name,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textTertiary,
                          ),
                        );
                      },
                      reservedSize: 30,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '€${value.toInt()}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textTertiary,
                          ),
                        );
                      },
                      reservedSize: 40,
                    ),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: barGroups,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
