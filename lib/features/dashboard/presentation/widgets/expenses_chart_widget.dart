import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/currency_utils.dart';

import '../../../../app/app_theme.dart';
enum ChartPeriod { week, month, year }

/// Provider per le spese raggruppate per periodo
final expensesByPeriodProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, ExpenseChartParams>((ref, params) async {
  final supabase = Supabase.instance.client;
  final now = DateTime.now();

  DateTime startDate;
  DateTime endDate;

  switch (params.period) {
    case ChartPeriod.week:
      // Settimana corrente + offset
      final weekDay = now.weekday;
      final currentWeekStart = now.subtract(Duration(days: weekDay - 1));
      startDate = currentWeekStart.add(Duration(days: params.offset * 7));
      endDate = startDate.add(const Duration(days: 6));
      break;
    case ChartPeriod.month:
      // Mese corrente + offset
      // Use DateTime overflow handling to correctly handle month/year boundaries
      final targetDate = DateTime(now.year, now.month + params.offset, 1);
      final targetYear = targetDate.year;
      final normalizedMonth = targetDate.month;
      startDate = DateTime(targetYear, normalizedMonth, 1);
      endDate = DateTime(targetYear, normalizedMonth + 1, 0);
      break;
    case ChartPeriod.year:
      // Anno corrente + offset
      final targetYear = now.year + params.offset;
      startDate = DateTime(targetYear, 1, 1);
      endDate = DateTime(targetYear, 12, 31);
      break;
  }

  // Query spese nel periodo
  var query = supabase
      .from('expenses')
      .select('amount, date')
      .gte('date', startDate.toIso8601String().split('T')[0])
      .lte('date', endDate.toIso8601String().split('T')[0]);

  if (params.isPersonalView) {
    // Use paid_by instead of created_by to include expenses created by admin on behalf of user
    query = query.eq('paid_by', params.userId).eq('is_group_expense', false);
  } else {
    query = query.eq('group_id', params.groupId).eq('is_group_expense', true);
  }

  final expenses = await query as List;

  // Raggruppa per data/periodo
  final Map<String, int> grouped = {};

  for (final expense in expenses) {
    final date = DateTime.parse(expense['date'] as String);
    final amount = (expense['amount'] as num).toDouble();
    final amountCents = (amount * 100).round();

    String key;
    switch (params.period) {
      case ChartPeriod.week:
      case ChartPeriod.month:
        key = DateFormat('yyyy-MM-dd').format(date);
        break;
      case ChartPeriod.year:
        key = DateFormat('yyyy-MM').format(date);
        break;
    }

    grouped[key] = (grouped[key] ?? 0) + amountCents;
  }

  // Converti in lista ordinata
  final List<Map<String, dynamic>> result = [];

  if (params.period == ChartPeriod.week) {
    // Settimana: 7 giorni
    for (int i = 0; i < 7; i++) {
      final date = startDate.add(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(date);
      result.add({
        'label': DateFormat('E', 'it').format(date), // Lun, Mar, ...
        'value': grouped[key] ?? 0,
        'date': date,
      });
    }
  } else if (params.period == ChartPeriod.month) {
    // Mese: tutti i giorni
    final daysInMonth = endDate.day;
    for (int i = 1; i <= daysInMonth; i++) {
      final date = DateTime(startDate.year, startDate.month, i);
      final key = DateFormat('yyyy-MM-dd').format(date);
      result.add({
        'label': i.toString(),
        'value': grouped[key] ?? 0,
        'date': date,
      });
    }
  } else {
    // Anno: 12 mesi
    for (int i = 1; i <= 12; i++) {
      final date = DateTime(startDate.year, i, 1);
      final key = DateFormat('yyyy-MM').format(date);
      result.add({
        'label': DateFormat('MMM', 'it').format(date), // Gen, Feb, ...
        'value': grouped[key] ?? 0,
        'date': date,
      });
    }
  }

  return result;
});

class ExpenseChartParams {
  final String groupId;
  final String userId;
  final ChartPeriod period;
  final bool isPersonalView;
  final int offset; // 0 = corrente, -1 = precedente, +1 = successivo

  ExpenseChartParams({
    required this.groupId,
    required this.userId,
    required this.period,
    required this.isPersonalView,
    this.offset = 0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpenseChartParams &&
          runtimeType == other.runtimeType &&
          groupId == other.groupId &&
          userId == other.userId &&
          period == other.period &&
          isPersonalView == other.isPersonalView &&
          offset == other.offset;

  @override
  int get hashCode =>
      groupId.hashCode ^ userId.hashCode ^ period.hashCode ^ isPersonalView.hashCode ^ offset.hashCode;
}

/// Widget grafico spese
class ExpensesChartWidget extends ConsumerStatefulWidget {
  const ExpensesChartWidget({
    super.key,
    required this.groupId,
    required this.userId,
    required this.isPersonalView,
  });

  final String groupId;
  final String userId;
  final bool isPersonalView;

  @override
  ConsumerState<ExpensesChartWidget> createState() => _ExpensesChartWidgetState();
}

class _ExpensesChartWidgetState extends ConsumerState<ExpensesChartWidget> {
  ChartPeriod _selectedPeriod = ChartPeriod.week;
  int _offset = 0;

  void _changePeriod(ChartPeriod newPeriod) {
    setState(() {
      _selectedPeriod = newPeriod;
      _offset = 0; // Reset to current when changing period
    });
  }

  String _getPeriodLabel() {
    final now = DateTime.now();

    switch (_selectedPeriod) {
      case ChartPeriod.week:
        final weekDay = now.weekday;
        final currentWeekStart = now.subtract(Duration(days: weekDay - 1));
        final targetWeekStart = currentWeekStart.add(Duration(days: _offset * 7));
        final targetWeekEnd = targetWeekStart.add(const Duration(days: 6));
        return '${DateFormat('d MMM', 'it').format(targetWeekStart)} - ${DateFormat('d MMM', 'it').format(targetWeekEnd)}';
      case ChartPeriod.month:
        final targetLabelDate = DateTime(now.year, now.month + _offset, 1);
        final date = DateTime(targetLabelDate.year, targetLabelDate.month);
        return DateFormat('MMMM yyyy', 'it').format(date);
      case ChartPeriod.year:
        return (now.year + _offset).toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final params = ExpenseChartParams(
      groupId: widget.groupId,
      userId: widget.userId,
      period: _selectedPeriod,
      isPersonalView: widget.isPersonalView,
      offset: _offset,
    );
    final dataAsync = ref.watch(expensesByPeriodProvider(params));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bar_chart,
                  color: AppColors.terracotta,
                ),
                const SizedBox(width: 8),
                Text(
                  'Andamento Spese',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Selector periodo
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PeriodChip(
                  label: 'Settimana',
                  isSelected: _selectedPeriod == ChartPeriod.week,
                  onTap: () => _changePeriod(ChartPeriod.week),
                ),
                const SizedBox(width: 8),
                _PeriodChip(
                  label: 'Mese',
                  isSelected: _selectedPeriod == ChartPeriod.month,
                  onTap: () => _changePeriod(ChartPeriod.month),
                ),
                const SizedBox(width: 8),
                _PeriodChip(
                  label: 'Anno',
                  isSelected: _selectedPeriod == ChartPeriod.year,
                  onTap: () => _changePeriod(ChartPeriod.year),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Navigation controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() => _offset--),
                  tooltip: 'Precedente',
                ),
                Expanded(
                  child: Text(
                    _getPeriodLabel(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _offset < 0 ? () => setState(() => _offset++) : null,
                  tooltip: 'Successivo',
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Chart
            dataAsync.when(
              data: (data) => SizedBox(
                height: 200,
                child: data.isEmpty
                    ? Center(
                        child: Text(
                          'Nessuna spesa nel periodo',
                          style: theme.textTheme.bodySmall,
                        ),
                      )
                    : BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: _getMaxY(data),
                          barTouchData: BarTouchData(
                            enabled: true,
                            touchTooltipData: BarTouchTooltipData(
                              tooltipBgColor: Colors.black87,
                              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                final amount = rod.toY.round();
                                return BarTooltipItem(
                                  CurrencyUtils.formatCents(amount),
                                  const TextStyle(color: Colors.white),
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
                                  if (index < 0 || index >= data.length) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      data[index]['label'],
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  );
                                },
                              ),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 50,
                                getTitlesWidget: (value, meta) {
                                  if (value == 0) return const SizedBox.shrink();
                                  return Text(
                                    '€${(value / 100).toStringAsFixed(0)}',
                                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                                  );
                                },
                              ),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: _getMaxY(data) / 5,
                          ),
                          borderData: FlBorderData(show: false),
                          barGroups: data
                              .asMap()
                              .entries
                              .map(
                                (entry) => BarChartGroupData(
                                  x: entry.key,
                                  barRods: [
                                    BarChartRodData(
                                      toY: entry.value['value'].toDouble(),
                                      color: AppColors.terracotta,
                                      width: _selectedPeriod == ChartPeriod.month ? 6 : 16,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(4),
                                        topRight: Radius.circular(4),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      ),
              ),
              loading: () => const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    'Errore caricamento dati',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _getMaxY(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return 100;
    final maxValue = data.map((e) => e['value'] as int).reduce((a, b) => a > b ? a : b);
    if (maxValue == 0) return 100;
    // Arrotonda al multiplo di 10 superiore
    return ((maxValue / 100).ceil() * 10).toDouble() * 10;
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.terracotta : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.cream : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
