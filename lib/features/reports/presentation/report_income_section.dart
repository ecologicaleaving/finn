import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/routes.dart';
import '../domain/group_report.dart';
import 'report_visuals.dart';

String _money(int cents) =>
    NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 2)
        .format(cents / 100);

class ReportBalanceSummary extends StatelessWidget {
  const ReportBalanceSummary({super.key, required this.report, this.scope});
  final GroupReport report;
  final Object? scope;
  @override
  Widget build(BuildContext context) {
    final ink = ReportVisuals.ink(context);
    Widget metric(String label, int cents, IconData icon) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 20, color: ReportVisuals.muted(context))),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: ink))),
          const SizedBox(width: 12),
          Flexible(
              child: ReportMoney(cents,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: ink, fontWeight: FontWeight.w700))),
        ]));
    return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            color: ReportVisuals.surface(context),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: ReportVisuals.line(context))),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Bilancio del periodo',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 18),
          Text('Saldo del periodo',
              style: TextStyle(color: ReportVisuals.muted(context))),
          const SizedBox(height: 4),
          ReportMoney(report.balanceCents,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontSize: 36, fontWeight: FontWeight.w700, color: ink)),
          const SizedBox(height: 8),
          Text('Entrate + rimborsi ricevuti − spese lorde',
              style: TextStyle(color: ReportVisuals.muted(context))),
          const Divider(height: 28),
          metric('Spese lorde', report.totalCents, Icons.arrow_upward),
          metric(
              'Entrate registrate', report.incomeCents, Icons.arrow_downward),
          metric('Rimborsi ricevuti', report.receivedReimbursementCents,
              Icons.replay),
          const Divider(height: 28),
          LayoutBuilder(
              builder: (context, constraints) =>
                  Wrap(spacing: 16, runSpacing: 16, children: [
                    SizedBox(
                        width: (constraints.maxWidth - 16) / 2,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Numero di spese',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: ReportVisuals.muted(context))),
                              const SizedBox(height: 6),
                              Text('${report.count}',
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                            ])),
                    SizedBox(
                        width: (constraints.maxWidth - 16) / 2,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Importo medio',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: ReportVisuals.muted(context))),
                              const SizedBox(height: 6),
                              ReportMoney(report.averageCents,
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                            ])),
                  ])),
          const SizedBox(height: 20),
          Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: ReportVisuals.canvas(context),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    metric('Rimborsi attesi', report.pendingReimbursementCents,
                        Icons.schedule),
                    Text(
                        'Esclusi dal saldo · solo spese del periodo oggi da rimborsare',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: ReportVisuals.muted(context))),
                  ])),
          ExpansionTile(
              key: PageStorageKey((
                'report-balance-notes',
                scope ?? report.period.start,
                report.period.mode
              )),
              tilePadding: EdgeInsets.zero,
              title: const Text('Cosa include il bilancio'),
              children: const [
                Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                        'Solo movimenti di gruppo sincronizzati. Movimenti personali e fonti di reddito previste esclusi. '
                        'I rimborsi sono integrali e contati alla data di marcatura, anche per spese precedenti. '
                        'Le spese rimborsate restano nelle uscite lorde. Il saldo del periodo non è il saldo bancario '
                        'o il budget disponibile.'))
              ]),
        ]));
  }
}

enum _InflowFilter { all, income, reimbursements }

class ReportInflowDetails extends StatefulWidget {
  const ReportInflowDetails(
      {super.key,
      required this.report,
      required this.members,
      this.scope,
      this.onOpenOriginal});
  final GroupReport report;
  final List<ReportMember> members;
  final Object? scope;
  final Future<void> Function(String id)? onOpenOriginal;
  @override
  State<ReportInflowDetails> createState() => _ReportInflowDetailsState();
}

class _ReportInflowDetailsState extends State<ReportInflowDetails> {
  String _query = '';
  _InflowFilter _filter = _InflowFilter.all;
  int _page = 0;
  static const _pageSize = 20;
  String _person(ReportInflow entry) {
    for (final member in widget.members) {
      if (member.id == entry.expense.payerId && member.name.trim().isNotEmpty) {
        return member.name.trim();
      }
    }
    return entry.expense.payerName;
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filtered = widget.report.inflows.where((entry) {
      if (_filter == _InflowFilter.income &&
          entry.kind != ReportInflowKind.income) {
        return false;
      }
      if (_filter == _InflowFilter.reimbursements &&
          entry.kind != ReportInflowKind.reimbursement) {
        return false;
      }
      return query.isEmpty ||
          [entry.expense.title, entry.expense.category, _person(entry)]
              .any((text) => text.toLowerCase().contains(query));
    }).toList();
    final total = filtered.fold<int>(0, (sum, row) => sum + row.cents);
    final lastPage = filtered.isEmpty ? 0 : (filtered.length - 1) ~/ _pageSize;
    final page = _page.clamp(0, lastPage);
    final pageRows = filtered.skip(page * _pageSize).take(_pageSize).toList();
    final ink = ReportVisuals.ink(context);
    return Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        color: ReportVisuals.surface(context),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: ReportVisuals.line(context))),
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Dettaglio entrate e rimborsi',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 48),
                              foregroundColor: ink,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12)),
                          onPressed: () => context.push(AppRoutes.addIncome),
                          icon: const Icon(Icons.add),
                          label: const Text('Aggiungi entrata'))),
                  const SizedBox(height: 18),
                  TextField(
                      decoration: InputDecoration(
                          labelText: 'Cerca entrate e rimborsi',
                          hintText: 'Descrizione, categoria o persona',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: ReportVisuals.canvas(context),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14))),
                      onChanged: (value) => setState(() {
                            _query = value;
                            _page = 0;
                          })),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final filter in _InflowFilter.values)
                      ChoiceChip(
                          key: ValueKey('income-filter-${filter.name}'),
                          label: Text(filter == _InflowFilter.all
                              ? 'Tutte'
                              : filter == _InflowFilter.income
                                  ? 'Entrate'
                                  : 'Rimborsi'),
                          selected: _filter == filter,
                          selectedColor: ReportVisuals.forest,
                          backgroundColor: ReportVisuals.canvas(context),
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                              color: _filter == filter ? Colors.white : ink),
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          onSelected: (_) => setState(() {
                                _filter = filter;
                                _page = 0;
                              })),
                  ]),
                  const SizedBox(height: 18),
                  Text(
                      'Totale filtrato: ${_money(total)} · ${filtered.length} movimenti',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: ink, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (filtered.isEmpty)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(widget.report.inflows.isEmpty
                            ? 'Nessuna entrata o rimborso ricevuto nel periodo.'
                            : 'Nessun movimento corrisponde alla ricerca.')),
                  for (final entry in pageRows)
                    InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => widget.onOpenOriginal != null
                            ? widget.onOpenOriginal!(entry.expense.id)
                            : context.push(
                                '/expense/${Uri.encodeComponent(entry.expense.id)}'),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  LayoutBuilder(
                                      builder: (context, constraints) {
                                    final badge = Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 7),
                                        decoration: BoxDecoration(
                                            color: (entry.kind == ReportInflowKind.income
                                                    ? ReportVisuals.forest
                                                    : ReportVisuals.petrol)
                                                .withValues(
                                                    alpha: ReportVisuals.dark(context)
                                                        ? .25
                                                        : .09),
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        child: Text(
                                            entry.kind == ReportInflowKind.income
                                                ? 'Entrata'
                                                : 'Rimborso ricevuto',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(color: ink, fontWeight: FontWeight.w700)));
                                    final amount = Text(_money(entry.cents),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                                color: ink,
                                                fontWeight: FontWeight.w700));
                                    if (MediaQuery.textScalerOf(context)
                                                .scale(1) >
                                            1.2 ||
                                        constraints.maxWidth < 300) {
                                      return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Align(
                                                alignment: Alignment.centerLeft,
                                                child: badge),
                                            const SizedBox(height: 10),
                                            amount,
                                          ]);
                                    }
                                    return Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                              child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: badge)),
                                          const SizedBox(width: 12),
                                          Flexible(child: amount),
                                        ]);
                                  }),
                                  const SizedBox(height: 10),
                                  Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                            child: Text(entry.expense.title,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(color: ink))),
                                        const SizedBox(width: 8),
                                        Icon(Icons.chevron_right, color: ink),
                                      ]),
                                  const SizedBox(height: 7),
                                  Text(
                                      DateFormat('d MMM yyyy', 'it_IT')
                                          .format(entry.date),
                                      style: TextStyle(
                                          color: ReportVisuals.muted(context))),
                                  const SizedBox(height: 4),
                                  Text('Categoria: ${entry.expense.category}',
                                      style: TextStyle(
                                          color: ReportVisuals.muted(context))),
                                  Text('Persona associata: ${_person(entry)}',
                                      style: TextStyle(
                                          color: ReportVisuals.muted(context))),
                                  const Divider(height: 20),
                                ]))),
                  if (filtered.isNotEmpty)
                    Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                              '${page * _pageSize + 1}–${page * _pageSize + pageRows.length} di ${filtered.length} movimenti'),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                                tooltip: 'Movimenti precedenti',
                                constraints: const BoxConstraints(
                                    minWidth: 48, minHeight: 48),
                                onPressed: page == 0
                                    ? null
                                    : () => setState(() => _page = page - 1),
                                icon: const Icon(Icons.chevron_left)),
                            IconButton(
                                tooltip: 'Altri movimenti',
                                constraints: const BoxConstraints(
                                    minWidth: 48, minHeight: 48),
                                onPressed: page >= lastPage
                                    ? null
                                    : () => setState(() => _page = page + 1),
                                icon: const Icon(Icons.chevron_right)),
                          ]),
                        ]),
                  ExpansionTile(
                      key: PageStorageKey((
                        'income-reimbursement-notes',
                        widget.scope ?? widget.report.period.start,
                        widget.report.period.mode
                      )),
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Cosa sapere sui rimborsi'),
                      children: const [
                        Padding(
                            padding: EdgeInsets.only(bottom: 16),
                            child: Text(
                                'Un’entrata separata non è collegata allo stato rimborso della spesa: registra lo stesso incasso una sola volta. '
                                'I rimborsi sono integrali e attribuiti alla data in cui vengono marcati come ricevuti.'))
                      ]),
                ])));
  }
}
