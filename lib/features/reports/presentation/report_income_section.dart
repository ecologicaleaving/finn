import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/routes.dart';
import '../domain/group_report.dart';

String _money(int cents) =>
    NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 2)
        .format(cents / 100);

class ReportBalanceSummary extends StatelessWidget {
  const ReportBalanceSummary({super.key, required this.report});
  final GroupReport report;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Bilancio del periodo',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth >= 900
                ? (constraints.maxWidth - 36) / 4
                : constraints.maxWidth >= 600
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;
            Widget value(String label, int cents, String note,
                    {bool balance = false}) =>
                SizedBox(
                  width: width,
                  child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label,
                                  style:
                                      Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 8),
                              Text(_money(cents),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: balance && cents < 0
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .error
                                              : null)),
                              const SizedBox(height: 8),
                              Text(note),
                            ]),
                      )),
                );
            return Wrap(spacing: 12, runSpacing: 12, children: [
              value('Entrate registrate', report.incomeCents,
                  'Movimenti di gruppo effettivamente registrati.'),
              value('Rimborsi ricevuti', report.receivedReimbursementCents,
                  'Rimborsi integrali alla data di marcatura, anche per spese precedenti.'),
              value('Saldo del periodo', report.balanceCents,
                  'Entrate + rimborsi ricevuti − spese lorde. Non è il saldo bancario.',
                  balance: true),
              value('Rimborsi attesi', report.pendingReimbursementCents,
                  'Solo spese del periodo oggi da rimborsare. Esclusi dal saldo.'),
            ]);
          }),
        ],
      );
}

enum _InflowFilter { all, income, reimbursements }

class ReportInflowDetails extends StatefulWidget {
  const ReportInflowDetails(
      {super.key,
      required this.report,
      required this.members,
      this.onOpenOriginal});
  final GroupReport report;
  final List<ReportMember> members;
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
    return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Dettaglio entrate e rimborsi',
                style: Theme.of(context).textTheme.titleLarge),
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    onPressed: () => context.push(AppRoutes.addIncome),
                    icon: const Icon(Icons.add),
                    label: const Text('Aggiungi entrata'))),
            const Text(
                'Un’entrata separata non è collegata allo stato rimborso della spesa: '
                'registra lo stesso incasso una sola volta. I rimborsi sono integrali '
                'e attribuiti alla data in cui vengono marcati come ricevuti.'),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                  labelText: 'Cerca entrate e rimborsi',
                  hintText: 'Descrizione, categoria o persona',
                  prefixIcon: Icon(Icons.search)),
              onChanged: (value) => setState(() {
                _query = value;
                _page = 0;
              }),
            ),
            const SizedBox(height: 12),
            SegmentedButton<_InflowFilter>(
              segments: const [
                ButtonSegment(value: _InflowFilter.all, label: Text('Tutte')),
                ButtonSegment(
                    value: _InflowFilter.income, label: Text('Entrate')),
                ButtonSegment(
                    value: _InflowFilter.reimbursements,
                    label: Text('Rimborsi')),
              ],
              selected: {_filter},
              onSelectionChanged: (value) => setState(() {
                _filter = value.single;
                _page = 0;
              }),
            ),
            const SizedBox(height: 16),
            Text(
                'Totale filtrato: ${_money(total)} · ${filtered.length} movimenti',
                style: Theme.of(context).textTheme.titleSmall),
            if (filtered.isEmpty)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(widget.report.inflows.isEmpty
                      ? 'Nessuna entrata o rimborso ricevuto nel periodo.'
                      : 'Nessun movimento corrisponde alla ricerca.')),
            for (final entry in pageRows)
              InkWell(
                onTap: () => widget.onOpenOriginal != null
                    ? widget.onOpenOriginal!(entry.expense.id)
                    : context.push(
                        '/expense/${Uri.encodeComponent(entry.expense.id)}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: Text(entry.expense.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall)),
                              const SizedBox(width: 12),
                              Text(_money(entry.cents)),
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right, size: 18),
                            ]),
                        const SizedBox(height: 6),
                        Text(
                            '${entry.kind == ReportInflowKind.income ? 'Entrata' : 'Rimborso ricevuto'} · '
                            '${DateFormat('d MMM yyyy', 'it_IT').format(entry.date)}'),
                        Text('Categoria: ${entry.expense.category}'),
                        Text('Persona associata: ${_person(entry)}'),
                      ]),
                ),
              ),
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
                          onPressed: page == 0
                              ? null
                              : () => setState(() => _page = page - 1),
                          icon: const Icon(Icons.chevron_left)),
                      IconButton(
                          tooltip: 'Altri movimenti',
                          onPressed: page >= lastPage
                              ? null
                              : () => setState(() => _page = page + 1),
                          icon: const Icon(Icons.chevron_right)),
                    ]),
                  ]),
          ]),
        ));
  }
}
