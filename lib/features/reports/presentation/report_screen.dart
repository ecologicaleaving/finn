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
import 'member_balance_section.dart';
import 'report_visuals.dart';

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
      backgroundColor: ReportVisuals.canvas(context),
      appBar: AppBar(
        backgroundColor: ReportVisuals.canvas(context),
        foregroundColor: ReportVisuals.ink(context),
        elevation: 0,
        title: const Text('Report'),
        actions: [
          IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: 'Aggiorna report',
              onPressed: () => ref.invalidate(groupReportProvider(request)),
              icon: const Icon(Icons.refresh))
        ],
      ),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            child: Column(children: [
              Text(group.name,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: ReportVisuals.muted(context)),
                  textAlign: TextAlign.center),
              const SizedBox(height: 6),
              SegmentedButton<ReportMode>(
                style: ButtonStyle(
                    minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
                    foregroundColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.selected)
                            ? Colors.white
                            : ReportVisuals.ink(context)),
                    backgroundColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.selected)
                            ? ReportVisuals.forest
                            : ReportVisuals.surface(context))),
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
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
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
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
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
              balanceScope: request,
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
      required this.balanceScope,
      required this.onOpenOriginal});
  final GroupReport report;
  final List<ReportMember> members;
  final Object balanceScope;
  final Future<void> Function(String id) onOpenOriginal;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final period = report.period;
    return SingleChildScrollView(
        key: const PageStorageKey('report-scroll'),
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 104),
        child: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(_interval(period.start, period.end),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: ReportVisuals.muted(context))),
                      const SizedBox(height: 12),
                      MemberBalanceSection(
                          report: report,
                          members: members,
                          scope: balanceScope,
                          onOpenOriginal: onOpenOriginal),
                      const SizedBox(height: 30),
                      Text(
                          period.isYear
                              ? (period.isCurrent
                                  ? 'L’anno finora'
                                  : 'L’anno in numeri')
                              : (period.isCurrent
                                  ? 'Il mese finora'
                                  : 'Il mese in numeri'),
                          style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: ReportVisuals.ink(context))),
                      const SizedBox(height: 14),
                      ReportBalanceSummary(report: report, scope: balanceScope),
                      if (report.count == 0) ...[
                        const SizedBox(height: 16),
                        const _Panel(
                            title: 'Nessuna spesa nel periodo',
                            child: Text(
                                'Lo storico e gli eventuali incassi restano disponibili qui sotto.')),
                      ],
                      const SizedBox(height: 24),
                      _Trend(report: report, scope: balanceScope),
                      const SizedBox(height: 24),
                      _Comparison(report: report),
                      const SizedBox(height: 24),
                      LayoutBuilder(builder: (context, constraints) {
                        final width = constraints.maxWidth >= 800
                            ? (constraints.maxWidth - 20) / 2
                            : constraints.maxWidth;
                        return Wrap(spacing: 20, runSpacing: 20, children: [
                          SizedBox(
                              width: width,
                              child: _Breakdown(
                                  title: 'Dove avete speso',
                                  subtitle: 'Categorie ordinate per spesa',
                                  slices: report.categories,
                                  total: report.totalCents,
                                  chart: true,
                                  scope: balanceScope)),
                          SizedBox(
                              width: width,
                              child: _MemberPayments(
                                  payments: report.memberPayments(members),
                                  total: report.totalCents)),
                        ]);
                      }),
                      const SizedBox(height: 24),
                      LayoutBuilder(builder: (context, constraints) {
                        final width = constraints.maxWidth >= 800
                            ? (constraints.maxWidth - 20) / 2
                            : constraints.maxWidth;
                        final names = {
                          for (final member in members) member.id: member.name
                        };
                        return Wrap(spacing: 20, runSpacing: 20, children: [
                          SizedBox(
                              width: width,
                              child: _Breakdown(
                                  title: 'Entrate registrate per categoria',
                                  subtitle: 'Categorie originali dei movimenti',
                                  slices: report.incomeCategories,
                                  total: report.incomeCents,
                                  scope: balanceScope,
                                  emptyMessage:
                                      'Nessuna entrata registrata nel periodo.',
                                  countLabel: 'entrate')),
                          SizedBox(
                              width: width,
                              child: _Breakdown(
                                  title: 'Entrate per persona associata',
                                  subtitle:
                                      'La persona registrata, senza dedurre beneficiari',
                                  slices: [
                                    for (final slice in report.incomePeople)
                                      ReportSlice(
                                          slice.id,
                                          names[slice.id]?.trim().isNotEmpty ==
                                                  true
                                              ? names[slice.id]!.trim()
                                              : slice.label,
                                          slice.cents,
                                          slice.count)
                                  ],
                                  total: report.incomeCents,
                                  scope: balanceScope,
                                  extraLabel: 'persone',
                                  emptyMessage:
                                      'Nessuna entrata registrata nel periodo.',
                                  countLabel: 'entrate')),
                        ]);
                      }),
                      const SizedBox(height: 24),
                      ReportInflowDetails(
                          report: report,
                          members: members,
                          scope: balanceScope,
                          onOpenOriginal: onOpenOriginal),
                      if (report.count > 0) ...[
                        const SizedBox(height: 24),
                        _Insights(
                            report: report, onOpenOriginal: onOpenOriginal),
                      ],
                    ]))));
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
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      color: ReportVisuals.surface(context),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: ReportVisuals.line(context))),
      child: Padding(
          padding: const EdgeInsets.all(22),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: ReportVisuals.ink(context),
                    fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(subtitle!,
                  style: TextStyle(color: ReportVisuals.muted(context)))
            ],
            const SizedBox(height: 18),
            child,
          ])));
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
  const _Trend({required this.report, required this.scope});
  final GroupReport report;
  final Object scope;
  @override
  Widget build(BuildContext context) {
    final outColor = ReportVisuals.dark(context)
        ? const Color(0xFFA5D1B4)
        : ReportVisuals.forest;
    final inColor = ReportVisuals.dark(context)
        ? const Color(0xFF9BCDD4)
        : ReportVisuals.petrol;
    final maxCents = report.trend
        .fold<int>(0, (m, e) => math.max(m, math.max(e.cents, e.inflowCents)));
    final minCents = report.trend
        .fold<int>(0, (m, e) => math.min(m, math.min(e.cents, e.inflowCents)));
    return _Panel(
        title: report.period.isYear
            ? 'Andamento dei 12 mesi'
            : 'Andamento degli ultimi 6 mesi',
        subtitle: 'Movimenti registrati, mese per mese',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 20, runSpacing: 10, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.arrow_upward, color: outColor, size: 18),
              const SizedBox(width: 6),
              const Text('Uscite lorde')
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.arrow_downward, color: inColor, size: 18),
              const SizedBox(width: 6),
              const Text('Entrate + rimborsi')
            ]),
          ]),
          const SizedBox(height: 24),
          LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth < 700 && report.period.isYear;
            final currentIndex =
                report.trend.indexWhere((month) => month.partial);
            return SizedBox(
                height: constraints.maxWidth < 600 ? 210 : 260,
                child: BarChart(BarChartData(
                  minY: minCents / 100 * 1.15,
                  maxY: math.max(1, maxCents / 100 * 1.15),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 34,
                            getTitlesWidget: (value, _) {
                              final index = value.toInt();
                              if (index < 0 || index >= report.trend.length) {
                                return const SizedBox.shrink();
                              }
                              if (compact &&
                                  index != currentIndex &&
                                  (index % 3 != 0 ||
                                      (index - currentIndex).abs() <= 1)) {
                                return const SizedBox.shrink();
                              }
                              final month = report.trend[index];
                              return Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Text(
                                      '${DateFormat('MMM', 'it_IT').format(month.month)}${month.partial ? '*' : ''}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                              color: ReportVisuals.muted(
                                                  context))));
                            })),
                  ),
                  barGroups: [
                    for (var i = 0; i < report.trend.length; i++)
                      BarChartGroupData(
                          x: i,
                          barsSpace: report.period.isYear ? 4 : 6,
                          barRods: [
                            BarChartRodData(
                                toY: report.trend[i].cents / 100,
                                width: report.period.isYear ? 8 : 15,
                                color: report.trend[i].partial
                                    ? outColor.withValues(alpha: .65)
                                    : outColor,
                                borderRadius: BorderRadius.circular(5)),
                            BarChartRodData(
                                toY: report.trend[i].inflowCents / 100,
                                width: report.period.isYear ? 8 : 15,
                                color: report.trend[i].partial
                                    ? inColor.withValues(alpha: .65)
                                    : inColor,
                                borderRadius: BorderRadius.circular(5)),
                          ])
                  ],
                )));
          }),
          if (report.period.isCurrent)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                    report.period.isYear
                        ? '* Mese corrente parziale. I mesi futuri non sono ancora trascorsi.'
                        : '* Mese corrente parziale, fino alla data del periodo.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: ReportVisuals.muted(context)))),
          const SizedBox(height: 10),
          ExpansionTile(
              key: PageStorageKey(('report-trend-values', scope)),
              tilePadding: EdgeInsets.zero,
              title: Text('Valori mensili (${report.trend.length})'),
              subtitle:
                  const Text('Tutti gli importi, senza passare sul grafico'),
              children: [
                for (final month in report.trend)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                                '${DateFormat('MMM yyyy', 'it_IT').format(month.month)}${month.future ? ' · Non ancora trascorso' : month.partial ? ' · parziale' : ''}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                        color: ReportVisuals.ink(context))),
                            if (month.future)
                              const Text('—')
                            else ...[
                              _AmountRow(
                                  label: 'Uscite lorde',
                                  amount: _money(month.cents)),
                              _AmountRow(
                                  label: 'Entrate + rimborsi',
                                  amount: _money(month.inflowCents)),
                            ],
                            const Divider(height: 18),
                          ]))
              ]),
        ]));
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
                          cell(ReportMoney(payments[i].cents), numeric: true),
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
      required this.scope,
      this.chart = false,
      this.emptyMessage = 'Nessuna spesa nel periodo.',
      this.countLabel = 'spese',
      this.extraLabel = 'categorie'});
  final String title, subtitle, emptyMessage, countLabel, extraLabel;
  final List<ReportSlice> slices;
  final int total;
  final Object scope;
  final bool chart;
  @override
  Widget build(BuildContext context) {
    final color = chart ? ReportVisuals.forest : ReportVisuals.petrol;
    Widget row(int index) {
      final slice = slices[index];
      final label =
          '${slice.label}${slices.where((s) => s.label == slice.label).length > 1 ? ' (${index + 1})' : ''}';
      final unit = slice.count == 1
          ? (countLabel == 'spese'
              ? 'spesa'
              : countLabel == 'entrate'
                  ? 'entrata'
                  : countLabel)
          : countLabel;
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _AmountRow(label: label, amount: _money(slice.cents)),
            const SizedBox(height: 6),
            Text(
                '${slice.count} $unit${total > 0 ? ' · ${NumberFormat('0.0', 'it_IT').format(slice.cents / total * 100)}%' : ''}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: ReportVisuals.muted(context))),
            const SizedBox(height: 10),
            ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                    minHeight: 7,
                    value: total > 0 ? (slice.cents / total).clamp(0, 1) : 0,
                    color: ReportVisuals.dark(context)
                        ? const Color(0xFFA5D1B4)
                        : color,
                    backgroundColor:
                        ReportVisuals.line(context).withValues(alpha: .5))),
          ]));
    }

    return _Panel(
        title: title,
        subtitle: subtitle,
        child: slices.isEmpty
            ? Text(emptyMessage)
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < math.min(4, slices.length); i++) row(i),
                if (slices.length > 4)
                  ExpansionTile(
                      key:
                          PageStorageKey(('report-ranked-extra', title, scope)),
                      tilePadding: EdgeInsets.zero,
                      title: Text('Altre ${slices.length - 4} $extraLabel'),
                      subtitle: Text('${slices.length} in totale'),
                      children: [
                        for (var i = 4; i < slices.length; i++) row(i)
                      ]),
              ]));
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.label, required this.amount});
  final String label, amount;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
              child: ReportFormattedAmount(amount,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ReportVisuals.ink(context)))),
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
