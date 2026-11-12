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
import 'report_income_section.dart';

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
  int? _selectedYear;
  ReportMode _mode = ReportMode.month;
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
    final selection = _mode == ReportMode.year
        ? DateTime.utc(_selectedYear ?? today.year)
        : (_selectedMonth ?? today);
    final period = ReportPeriod(selection, today, mode: _mode);
    final request = (
      userId: user.id,
      groupId: group.id,
      month: period.start,
      mode: _mode,
      today: today
    );
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
              const SizedBox(height: 12),
              SegmentedButton<ReportMode>(
                segments: const [
                  ButtonSegment(
                      value: ReportMode.month,
                      label: Text('Mese'),
                      icon: Icon(Icons.calendar_view_month)),
                  ButtonSegment(
                      value: ReportMode.year,
                      label: Text('Anno'),
                      icon: Icon(Icons.date_range)),
                ],
                selected: {_mode},
                onSelectionChanged: (value) =>
                    setState(() => _mode = value.single),
              ),
              Row(children: [
                IconButton(
                    tooltip:
                        period.isYear ? 'Anno precedente' : 'Mese precedente',
                    onPressed: () => setState(() {
                          if (period.isYear) {
                            _selectedYear = period.start.year - 1;
                          } else {
                            _selectedMonth = reportMonth(period.start, -1);
                          }
                        }),
                    icon: const Icon(Icons.chevron_left)),
                Expanded(
                    child: Text(
                        period.isYear
                            ? '${period.start.year}'
                            : DateFormat('MMMM yyyy', 'it_IT')
                                .format(period.start),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                    tooltip:
                        period.isYear ? 'Anno successivo' : 'Mese successivo',
                    onPressed: period.isCurrent
                        ? null
                        : () => setState(() {
                              if (period.isYear) {
                                _selectedYear = period.start.year + 1;
                              } else {
                                _selectedMonth = reportMonth(period.start, 1);
                              }
                            }),
                    icon: const Icon(Icons.chevron_right)),
              ]),
            ])),
        Expanded(
            child: report.when(
          loading: () =>
              const LoadingIndicator(message: 'Caricamento report completo...'),
          error: (_, __) => ErrorDisplay(
            message:
                'Impossibile caricare tutti i movimenti. Riprova per un report completo.',
            onRetry: () => ref.invalidate(groupReportProvider(request)),
          ),
          data: (value) => _ReportBody(
              key: ValueKey(request),
              report: value,
              onOpenOriginal: (id) async {
                final before = ref.read(groupReportProvider(request));
                await context.push('/expense/${Uri.encodeComponent(id)}');
                if (!mounted ||
                    _lastRequest != request ||
                    ref.read(currentUserProvider)?.id != request.userId ||
                    ref.read(groupProvider).group?.id != request.groupId) {
                  return;
                }
                if (identical(before, ref.read(groupReportProvider(request)))) {
                  ref.invalidate(groupReportProvider(request));
                }
              },
              members: [
                for (final member in groupState.members)
                  if (member.groupId == group.id)
                    ReportMember(member.userId, member.displayName),
              ]),
        )),
      ]),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody(
      {super.key,
      required this.report,
      required this.members,
      required this.onOpenOriginal});
  final GroupReport report;
  final List<ReportMember> members;
  final Future<void> Function(String id) onOpenOriginal;
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
          Text(
              period.isYear
                  ? (period.isCurrent ? 'L’anno finora' : 'L’anno in numeri')
                  : (period.isCurrent ? 'Il mese finora' : 'Il mese in numeri'),
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(_interval(period.start, period.end)),
          const SizedBox(height: 16),
          Text('Spese lorde', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
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
          const SizedBox(height: 20),
          ReportBalanceSummary(report: report),
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
                  child: _MemberPayments(
                      payments: report.memberPayments(members),
                      total: report.totalCents)),
            ]);
          }),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth >= 800
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            final names = {
              for (final member in members) member.id: member.name
            };
            return Wrap(spacing: 16, runSpacing: 16, children: [
              SizedBox(
                  width: width,
                  child: _Breakdown(
                      title: 'Entrate registrate per categoria',
                      subtitle:
                          'Categorie originali dei movimenti, inclusi gli aiuti registrati.',
                      slices: report.incomeCategories,
                      total: report.incomeCents,
                      emptyMessage: 'Nessuna entrata registrata nel periodo.',
                      countLabel: 'entrate')),
              SizedBox(
                  width: width,
                  child: _Breakdown(
                      title: 'Entrate per persona associata',
                      subtitle:
                          'Persona registrata nel movimento, senza dedurre beneficiari.',
                      slices: [
                        for (final slice in report.incomePeople)
                          ReportSlice(
                              slice.id,
                              names[slice.id]?.trim().isNotEmpty == true
                                  ? names[slice.id]!.trim()
                                  : slice.label,
                              slice.cents,
                              slice.count)
                      ],
                      total: report.incomeCents,
                      emptyMessage: 'Nessuna entrata registrata nel periodo.',
                      countLabel: 'entrate')),
            ]);
          }),
          const SizedBox(height: 16),
          ReportInflowDetails(
              report: report, members: members, onOpenOriginal: onOpenOriginal),
          if (report.count > 0) ...[
            const SizedBox(height: 16),
            _Insights(report: report, onOpenOriginal: onOpenOriginal),
          ],
          const SizedBox(height: 20),
          Text(
              'Solo movimenti di gruppo sincronizzati. Movimenti personali e fonti di reddito '
              'previste escluse. Le spese rimborsate restano incluse nelle spese lorde. '
              'Il saldo del periodo non rappresenta il saldo bancario o il budget disponibile.',
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
      title: period.isYear
          ? 'Spese lorde rispetto all’anno precedente'
          : 'Spese lorde rispetto al mese precedente',
      subtitle: period.isYear
          ? (period.isCurrent
              ? 'Confronto fino alla stessa data di calendario'
              : 'Confronto tra anni completi')
          : (period.isCurrent
              ? 'Confronto sullo stesso numero di giorni'
              : 'Confronto tra mesi completi'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            '${_interval(period.start, period.comparisonEnd)}: ${_money(report.comparisonCents)}'),
        const SizedBox(height: 8),
        Text(
            '${_interval(period.previousStart, period.previousEnd)}: ${_money(report.previousCents)}'),
        const SizedBox(height: 12),
        Text(
            change == null
                ? 'Il totale del periodo precedente è zero: la variazione percentuale non è disponibile.'
                : '${change > 0 ? '+' : ''}${NumberFormat('0.0', 'it_IT').format(change)}% di spesa nei periodi indicati',
            style: Theme.of(context).textTheme.titleSmall),
        if (period.comparisonEnd != period.end) ...[
          const SizedBox(height: 8),
          Text(
              'Il totale ${period.isYear ? 'dell’anno' : 'del mese'} include anche i giorni successivi all’intervallo di confronto.'),
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
    final inflowColor = Theme.of(context).colorScheme.tertiary;
    return _Panel(
      title: report.period.isYear
          ? 'Andamento dei 12 mesi'
          : 'Andamento degli ultimi 6 mesi',
      subtitle: 'Uscite lorde ed entrate + rimborsi · importi in euro',
      child: Column(children: [
        Wrap(spacing: 20, runSpacing: 8, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, color: color, size: 10),
            const SizedBox(width: 6),
            const Text('Uscite lorde')
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, color: inflowColor, size: 10),
            const SizedBox(width: 6),
            const Text('Entrate + rimborsi')
          ]),
        ]),
        const SizedBox(height: 16),
        SizedBox(
            height: 180,
            child: BarChart(BarChartData(
              maxY: math.max(
                  1,
                  report.trend.fold<int>(
                          0,
                          (m, e) =>
                              math.max(m, math.max(e.cents, e.inflowCents))) /
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
                      width: report.period.isYear ? 7 : 14,
                      color: report.trend[i].partial
                          ? color.withValues(alpha: 0.55)
                          : color,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(5)),
                    ),
                    BarChartRodData(
                        toY: math.max(0, report.trend[i].inflowCents / 100),
                        width: report.period.isYear ? 7 : 14,
                        color: report.trend[i].partial
                            ? inflowColor.withValues(alpha: 0.55)
                            : inflowColor,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(5))),
                  ])
              ],
            ))),
        const SizedBox(height: 16),
        for (final month in report.trend) ...[
          _AmountRow(
              label:
                  '${DateFormat('MMM yyyy', 'it_IT').format(month.month)}${month.future ? ' · Non ancora trascorso' : (month.partial ? ' · parziale' : '')}',
              amount: month.future ? '—' : _money(month.cents)),
          if (!month.future)
            Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 8),
                child: _AmountRow(
                    label: 'Entrate + rimborsi',
                    amount: _money(month.inflowCents))),
        ],
      ]),
    );
  }
}

class _MemberPayments extends StatelessWidget {
  const _MemberPayments({required this.payments, required this.total});
  final List<ReportPayment> payments;
  final int total;
  String _name(ReportPayment payment, int index) {
    final homonym = payments.where((p) => p.label == payment.label).length > 1;
    return '${payment.label}${homonym ? ' (${index + 1})' : ''}';
  }

  String _percent(ReportPayment payment) =>
      '${NumberFormat('0.0', 'it_IT').format(payment.sharePercent)}%';
  Widget _bar(ReportPayment payment) => LinearProgressIndicator(
      value: total > 0 ? (payment.cents / total).clamp(0, 1) : 0);
  @override
  Widget build(BuildContext context) => _Panel(
        title: 'Chi ha pagato',
        subtitle:
            'Importi pagati e percentuali sul totale · nessun debito o conguaglio',
        child: payments.isEmpty
            ? const Text('Nessun componente o pagamento disponibile.')
            : LayoutBuilder(builder: (context, constraints) {
                if (constraints.maxWidth >= 500) {
                  Widget cell(Widget child, {bool numeric = false}) => Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 4),
                      child: Align(
                          alignment: numeric
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: child));
                  return Table(
                    columnWidths: const {
                      0: FlexColumnWidth(2.4),
                      1: FlexColumnWidth(1.5),
                      2: FlexColumnWidth(1),
                      3: FlexColumnWidth(0.7)
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      TableRow(children: [
                        cell(const Text('Componente')),
                        cell(const Text('Pagato'), numeric: true),
                        cell(const Text('Quota'), numeric: true),
                        cell(const Text('Spese'), numeric: true),
                      ]),
                      for (var i = 0; i < payments.length; i++)
                        TableRow(children: [
                          cell(Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_name(payments[i], i)),
                                const SizedBox(height: 8),
                                _bar(payments[i]),
                              ])),
                          cell(Text(_money(payments[i].cents)), numeric: true),
                          cell(Text(_percent(payments[i])), numeric: true),
                          cell(Text('${payments[i].count}'), numeric: true),
                        ]),
                    ],
                  );
                }
                return Column(children: [
                  for (var i = 0; i < payments.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _AmountRow(
                                label: _name(payments[i], i),
                                amount: _money(payments[i].cents)),
                            Text(
                                '${_percent(payments[i])} del totale · ${payments[i].count} spese'),
                            const SizedBox(height: 8),
                            _bar(payments[i]),
                          ]),
                    ),
                ]);
              }),
      );
}

class _Breakdown extends StatelessWidget {
  const _Breakdown(
      {required this.title,
      required this.subtitle,
      required this.slices,
      required this.total,
      this.chart = false,
      this.emptyMessage = 'Nessuna spesa nel periodo.',
      this.countLabel = 'spese'});
  final String title, subtitle;
  final List<ReportSlice> slices;
  final int total;
  final bool chart;
  final String emptyMessage, countLabel;
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
            ? Text(emptyMessage)
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
                                '${slices[i].count} $countLabel${total > 0 ? ' · ${NumberFormat('0.0', 'it_IT').format(slices[i].cents / total * 100)}%' : ''}')),
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
  const _Insights({required this.report, required this.onOpenOriginal});
  final GroupReport report;
  final Future<void> Function(String id) onOpenOriginal;
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
          if (report.period.isYear && report.busiestMonth != null) ...[
            const Divider(height: 24),
            _AmountRow(
                label:
                    'Mese più oneroso · ${DateFormat('MMMM yyyy', 'it_IT').format(report.busiestMonth!.month)}',
                amount: _money(report.busiestMonth!.cents)),
          ],
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
            onTap: () => onOpenOriginal(largest.id),
          ),
          Align(
              alignment: Alignment.centerLeft,
              child: Text(_money(largest.cents),
                  style: Theme.of(context).textTheme.titleMedium)),
        ]));
  }
}
