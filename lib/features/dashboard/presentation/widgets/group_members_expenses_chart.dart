import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/app_theme.dart';
import '../../../../core/utils/currency_utils.dart';
import '../providers/dashboard_provider.dart';
import 'personal_dashboard_view.dart';

/// Widget per il grafico delle spese di gruppo per membro
/// Mostra un istogramma con le spese di ogni membro, ordinate decrescente
class GroupMembersExpensesChart extends ConsumerWidget {
  final String groupId;
  final DashboardPeriod period;
  final int offset;

  const GroupMembersExpensesChart({
    super.key,
    required this.groupId,
    required this.period,
    required this.offset,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = GroupMembersExpensesParams(
      groupId: groupId,
      period: period,
      offset: offset,
    );

    final membersAsync = ref.watch(groupMembersExpensesProvider(params));

    return membersAsync.when(
      data: (members) {
        if (members.isEmpty) {
          return SizedBox(
            height: 200,
            child: Center(
              child: Text(
                'Nessuna spesa di gruppo in questo periodo',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ),
          );
        }

        // Prendi top 10 membri per spesa
        final topMembers = members.take(10).toList();

        // Calcola il massimo per scalare l'asse Y
        final maxAmount = topMembers.isNotEmpty
            ? (topMembers.first['total'] as int).toDouble() / 100
            : 100.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Titolo
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'Spese per Membro',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Grafico
            SizedBox(
              height: 280,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceEvenly,
                    maxY: maxAmount * 1.2, // 20% di margine superiore
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        backgroundColor: Colors.black87,
                        textStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final member = topMembers[group.x.toInt()];
                          final name = member['name'] as String? ?? 'Sconosciuto';
                          final amount = rod.toY;

                          return BarTooltipItem(
                            '$name\n${CurrencyUtils.formatCurrency((amount * 100).round())}',
                            const TextStyle(color: Colors.white),
                          );
                        },
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalGridLine: (value) {
                        return FlLine(
                          color: Colors.grey[300]!,
                          strokeWidth: 0.5,
                        );
                      },
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= topMembers.length) {
                              return const SizedBox.shrink();
                            }

                            final member = topMembers[index];
                            final name = member['name'] as String? ?? 'Sconosciuto';

                            // Tronca il nome se troppo lungo
                            final displayName = name.length > 10
                                ? '${name.substring(0, 10)}...'
                                : name;

                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Transform.rotate(
                                  angle: -0.5, // Ruota il testo di ~30°
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              CurrencyUtils.formatCurrency((value * 100).toInt()),
                              style: const TextStyle(fontSize: 10),
                            );
                          },
                          reservedSize: 50,
                        ),
                      ),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    barGroups: List.generate(
                      topMembers.length,
                      (index) {
                        final member = topMembers[index];
                        final amount = (member['total'] as int).toDouble() / 100;

                        return BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: amount,
                              color: AppColors.terracotta,
                              width: 16,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      loading: () {
        return SizedBox(
          height: 280,
          child: Center(
            child: CircularProgressIndicator(
              color: AppColors.terracotta,
            ),
          ),
        );
      },
      error: (error, stackTrace) {
        return SizedBox(
          height: 280,
          child: Center(
            child: Text(
              'Errore nel caricamento del grafico',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.red[600],
              ),
            ),
          ),
        );
      },
    );
  }
}
