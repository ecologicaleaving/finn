import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/routes.dart';
import '../../../shared/widgets/error_display.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../../groups/presentation/providers/group_provider.dart';
import '../domain/group_report.dart';
import 'report_provider.dart';

String _money(int cents) =>
    NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 2)
        .format(cents / 100);
String _date(DateTime date) => DateFormat('d MMM yyyy', 'it_IT').format(date);
String _interval(DateTime start, DateTime end) =>
    '${_date(start)} – ${_date(end)}';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key, this.active = true});
  final bool active;
  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  DateTime? _selectedMonth;
  ReportRequest? _lastRequest;

  @override
  void didUpdateWidget(covariant ReportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && _lastRequest != null) {
      ref.invalidate(groupReportProvider(_lastRequest!));
    }
  }

  @override
  Widget build(BuildContext context) {
    // IndexedStack keeps the month, but inactive tabs neither read nor fetch data.
    if (!widget.active) return const SizedBox.shrink();
    final user = ref.watch(currentUserProvider);
    final groupState = ref.watch(groupProvider);
    Widget gate(Widget child) =>
        Scaffold(appBar: AppBar(title: const Text('Report')), body: child);
    if (user == null || groupState.isLoading) {
      return gate(const LoadingIndicator(message: 'Caricamento gruppo...'));
    }
    if (groupState.hasError) {
      return gate(ErrorDisplay(
        message: groupState.errorMessage ?? 'Impossibile caricare il gruppo.',
        onRetry: () => ref.read(groupProvider.notifier).loadCurrentGroup(),
      ));
    }
    final group = groupState.group;
    if (group == null) {
      return gate(Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.group_outlined, size: 48),
          const SizedBox(height: 16),
          const Text('Entra in un gruppo per vedere i suoi report.'),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: () => context.go(AppRoutes.noGroup),
              child: const Text('Vai al gruppo')),
        ]),
      )));
    }
    final today = reportDay(ref.watch(reportClockProvider)());
    final period = ReportPeriod(_selectedMonth ?? today, today);
    final request =
        (userId: user.id, groupId: group.id, month: period.month, today: today);
    _lastRequest = request;
    final report = ref.watch(groupReportProvider(request));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report'),
        actions: [
          IconButton(
              tooltip: 'Aggiorna report',
              onPressed: () => ref.invalidate(groupReportProvider(request)),
              icon: const Icon(Icons.refresh))
        ],
      ),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(children: [
              Text(group.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center),
              Row(children: [
                IconButton(
                    tooltip: 'Mese precedente',
                    onPressed: () => setState(
                        () => _selectedMonth = reportMonth(period.month, -1)),
                    icon: const Icon(Icons.chevron_left)),
                Expanded(
                    child: Text(
                        DateFormat('MMMM yyyy', 'it_IT').format(period.month),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                    tooltip: 'Mese successivo',
                    onPressed: period.isCurrent
                        ? null
                        : () => setState(() =>
                            _selectedMonth = reportMonth(period.month, 1)),
                    icon: const Icon(Icons.chevron_right)),
              ]),
            ])),
        Expanded(
            child: report.when(
          loading: () =>
              const LoadingIndicator(message: 'Caricamento report completo...'),
          error: (_, __) => ErrorDisplay(
            message:
                'Impossibile caricare tutte le spese. Riprova per un report completo.',
            onRetry: () => ref.invalidate(groupReportProvider(request)),
          ),
          data: (value) => _ReportBody(report: value),
        )),
      ]),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report});
  final GroupReport report;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final period = report.period;
    return SingleChildScrollView(
      key: const PageStorageKey('report-scroll'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
      child: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(period.isCurrent ? 'Il mese finora' : 'Il mese in numeri',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(_interval(period.month, period.end)),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth >= 650
                ? (constraints.maxWidth - 24) / 3
                : constraints.maxWidth;
            return Wrap(spacing: 12, runSpacing: 12, children: [
              _Kpi(width, 'Spesa totale', _money(report.totalCents),
                  Icons.payments_outlined),
              _Kpi(width, 'Numero di spese', '${report.count}',
                  Icons.receipt_long_outlined),
              _Kpi(width, 'Importo medio', _money(report.averageCents),
                  Icons.analytics_outlined),
            ]);
          }),
          if (report.count == 0) ...[
            const SizedBox(height: 16),
            const _Panel(
                title: 'Nessuna spesa nel periodo',
                child: Text(
                    'Lo storico degli altri mesi resta disponibile qui sotto.')),
          ],
          const SizedBox(height: 16),
          _Comparison(report: report),
          const SizedBox(height: 16),
          _Trend(report: report),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth >= 800
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(spacing: 16, runSpacing: 16, children: [
              SizedBox(
                  width: width,
                  child: _Breakdown(
                      title: 'Dove avete speso',
                      subtitle: 'Spese per categoria',
                      slices: report.categories,
                      total: report.totalCents,
                      chart: true)),
              SizedBox(
                  width: width,
                  child: _Breakdown(
                      title: 'Chi ha pagato',
                      subtitle: 'Quote pagate, non debiti o conguagli',
                      slices: report.payers,
                      total: report.totalCents)),
            ]);
          }),
          if (report.count > 0) ...[
            const SizedBox(height: 16),
            _Insights(report: report),
          ],
          const SizedBox(height: 20),
          Text(
              'Solo spese di gruppo sincronizzate. Entrate e spese personali escluse. '
              'Le spese rimborsate sono incluse: questi importi descrivono le spese registrate, '
              'non il budget disponibile.',
              style: theme.textTheme.bodySmall),
        ]),
      )),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!)
                  ],
                  const SizedBox(height: 16),
                  child,
                ])),
      );
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.width, this.label, this.value, this.icon);
  final double width;
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Card(
            margin: EdgeInsets.zero,
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 12),
                      Text(label),
                      const SizedBox(height: 4),
                      Text(value,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ]))),
      );
}

class _Comparison extends StatelessWidget {
  const _Comparison({required this.report});
  final GroupReport report;
  @override
  Widget build(BuildContext context) {
    final period = report.period;
    final change = report.changePercent;
    return _Panel(
      title: 'Rispetto al mese precedente',
      subtitle: period.isCurrent
          ? 'Confronto sullo stesso numero di giorni'
          : 'Confronto tra mesi completi',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            '${_interval(period.month, period.comparisonEnd)}: ${_money(report.comparisonCents)}'),
        const SizedBox(height: 8),
        Text(
            '${_interval(period.previousMonth, period.previousEnd)}: ${_money(report.previousCents)}'),
        const SizedBox(height: 12),
        Text(
            change == null
                ? 'Il totale del periodo precedente è zero: la variazione percentuale non è disponibile.'
                : '${change > 0 ? '+' : ''}${NumberFormat('0.0', 'it_IT').format(change)}% di spesa nei periodi indicati',
            style: Theme.of(context).textTheme.titleSmall),
        if (period.comparisonEnd != period.end) ...[
          const SizedBox(height: 8),
          const Text(
              'Il totale del mese include anche i giorni successivi all’intervallo di confronto.'),
        ],
      ]),
    );
  }
}

class _Trend extends StatelessWidget {
  const _Trend({required this.report});
  final GroupReport report;
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return _Panel(
      title: 'Andamento degli ultimi 6 mesi',
      subtitle: 'Spesa registrata per mese · importi in euro',
      child: Column(children: [
        SizedBox(
            height: 180,
            child: BarChart(BarChartData(
              maxY: math.max(
                  1,
                  report.trend.fold<int>(0, (m, e) => math.max(m, e.cents)) /
                      100 *
                      1.2),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
              barTouchData: BarTouchData(enabled: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) => Text(
                            DateFormat('MMM', 'it_IT')
                                .format(report.trend[value.toInt()].month)))),
              ),
              barGroups: [
                for (var i = 0; i < report.trend.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: math.max(0, report.trend[i].cents / 100),
                      width: 22,
                      color: report.trend[i].partial
                          ? color.withValues(alpha: 0.55)
                          : color,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(5)),
                    )
                  ])
              ],
            ))),
        const SizedBox(height: 16),
        for (final month in report.trend)
          _AmountRow(
              label:
                  '${DateFormat('MMM yyyy', 'it_IT').format(month.month)}${month.partial ? ' · parziale' : ''}',
              amount: _money(month.cents)),
      ]),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown(
      {required this.title,
      required this.subtitle,
      required this.slices,
      required this.total,
      this.chart = false});
  final String title, subtitle;
  final List<ReportSlice> slices;
  final int total;
  final bool chart;
  static const colors = [
    Color(0xFF2D4A3E),
    Color(0xFFB77945),
    Color(0xFF689F8C),
    Color(0xFF8A79A9),
    Color(0xFFB3A05E),
    Color(0xFF5D8BA8)
  ];
  @override
  Widget build(BuildContext context) => _Panel(
        title: title,
        subtitle: subtitle,
        child: slices.isEmpty
            ? const Text('Nessuna spesa nel periodo.')
            : Column(children: [
                if (chart && total > 0) ...[
                  SizedBox(
                      height: 150,
                      child: PieChart(PieChartData(
                        centerSpaceRadius: 38,
                        sectionsSpace: 3,
                        pieTouchData: PieTouchData(enabled: false),
                        sections: [
                          for (var i = 0; i < slices.length; i++)
                            if (slices[i].cents > 0)
                              PieChartSectionData(
                                  value: slices[i].cents.toDouble(),
                                  color: colors[i % colors.length],
                                  showTitle: false,
                                  radius: 28)
                        ],
                      ))),
                  const SizedBox(height: 12),
                ],
                for (var i = 0; i < slices.length; i++)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(children: [
                        _AmountRow(
                            label:
                                '${slices[i].label}${slices.where((s) => s.label == slices[i].label).length > 1 ? ' (${i + 1})' : ''}',
                            amount: _money(slices[i].cents),
                            color: chart ? colors[i % colors.length] : null),
                        const SizedBox(height: 4),
                        Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                                '${slices[i].count} spese${total > 0 ? ' · ${NumberFormat('0.0', 'it_IT').format(slices[i].cents / total * 100)}%' : ''}')),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                            value: total > 0
                                ? (slices[i].cents / total).clamp(0, 1)
                                : 0,
                            color: chart ? colors[i % colors.length] : null),
                      ])),
              ]),
      );
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.label, required this.amount, this.color});
  final String label, amount;
  final Color? color;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (color != null) ...[
            Padding(
                padding: const EdgeInsets.only(top: 5),
                child: CircleAvatar(radius: 4, backgroundColor: color)),
            const SizedBox(width: 8)
          ],
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Text(amount, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}

class _Insights extends StatelessWidget {
  const _Insights({required this.report});
  final GroupReport report;
  @override
  Widget build(BuildContext context) {
    final category = report.categories.first;
    final day = report.days.first;
    final largest = report.largestExpense!;
    return _Panel(
        title: 'Uno sguardo alle spese',
        child: Column(children: [
          _AmountRow(
              label: 'Categoria principale · ${category.label}',
              amount: _money(category.cents)),
          const Divider(height: 24),
          _AmountRow(
              label: 'Giorno con più spese · ${_date(DateTime.parse(day.id))}',
              amount: _money(day.cents)),
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('La spesa maggiore'),
            subtitle: Text(
                '${largest.title}\n${_date(largest.date)} · Pagato da: ${largest.payerName}'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () =>
                context.push('/expense/${Uri.encodeComponent(largest.id)}'),
          ),
          Align(
              alignment: Alignment.centerLeft,
              child: Text(_money(largest.cents),
                  style: Theme.of(context).textTheme.titleMedium)),
        ]));
  }
}
