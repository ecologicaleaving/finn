import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/group_report.dart';
import '../domain/member_balance.dart';
import 'report_visuals.dart';

String _money(int cents) =>
    NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 2)
        .format(cents / 100);
String _signed(int cents) => '${cents > 0 ? '+' : ''}${_money(cents)}';

class MemberBalanceSection extends StatefulWidget {
  const MemberBalanceSection(
      {super.key,
      required this.report,
      required this.members,
      required this.scope,
      required this.onOpenOriginal});
  final GroupReport report;
  final List<ReportMember> members;
  final Object scope;
  final Future<void> Function(String id) onOpenOriginal;
  @override
  State<MemberBalanceSection> createState() => _MemberBalanceSectionState();
}

class _MemberBalanceSectionState extends State<MemberBalanceSection> {
  String? _first, _second;
  late String _snapshot;
  final _attributions = <String, BalanceAttribution>{};
  int _assignmentPage = 0;
  final _assignmentAnchor = GlobalKey();
  final _assignmentController = ExpansibleController();

  @override
  void dispose() {
    _assignmentController.dispose();
    super.dispose();
  }

  List<ReportMember> get _members => {
        for (final member in widget.members)
          if (member.id.trim().isNotEmpty) member.id: member,
      }.values.toList()
        ..sort((a, b) => a.id.compareTo(b.id));

  @override
  void initState() {
    super.initState();
    _snapshot = MemberBalance.snapshotOf(widget.report);
    _syncPair();
  }

  void _syncPair() {
    final members = _members;
    final ids = members.map((member) => member.id).toSet();
    if ((_first != null && !ids.contains(_first)) ||
        (_second != null && !ids.contains(_second))) {
      _attributions.clear();
      if (!ids.contains(_first)) _first = null;
      if (!ids.contains(_second)) _second = null;
    }
    if (members.length == 2 && (_first == null || _second == null)) {
      _first = members.first.id;
      _second = members.last.id;
    }
  }

  @override
  void didUpdateWidget(covariant MemberBalanceSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final snapshot = MemberBalance.snapshotOf(widget.report);
    if (widget.scope != oldWidget.scope) {
      _first = null;
      _second = null;
    }
    if (widget.scope != oldWidget.scope || snapshot != _snapshot) {
      _attributions.clear();
      _assignmentPage = 0;
    }
    _snapshot = snapshot;
    _syncPair();
  }

  String _name(String id) {
    final members = _members;
    final member = members.firstWhere((member) => member.id == id);
    final name = member.name.trim().isEmpty ? 'Componente' : member.name.trim();
    final duplicates =
        members.where((m) => m.name.trim() == member.name.trim()).length;
    return duplicates > 1
        ? '$name (persona ${members.indexOf(member) + 1})'
        : name;
  }

  Widget _picker(bool first) => InputDecorator(
        decoration: InputDecoration(
            labelText: first ? 'Prima persona' : 'Seconda persona'),
        child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
          key: ValueKey(
              first ? 'balance-first-person' : 'balance-second-person'),
          isExpanded: true,
          itemHeight: null,
          value: first ? _first : _second,
          hint: const Text('Scegli una persona'),
          items: [
            for (final member in _members)
              if (member.id != (first ? _second : _first))
                DropdownMenuItem(
                    value: member.id, child: Text(_name(member.id)))
          ],
          onChanged: (value) => setState(() {
            if (first) {
              _first = value;
            } else {
              _second = value;
            }
            _attributions.clear();
            _assignmentPage = 0;
          }),
        )),
      );

  @override
  Widget build(BuildContext context) {
    final validPair = _first != null && _second != null && _first != _second;
    final balance = validPair
        ? MemberBalance.calculate(
            report: widget.report,
            firstId: _first!,
            secondId: _second!,
            attributions: _attributions)
        : null;
    final names = {for (final member in _members) member.id: _name(member.id)};
    final ordered =
        balance == null ? <CategoryBalance>[] : [...balance.categories]
          ..sort((a, b) {
            if (a.isComplete != b.isComplete) return a.isComplete ? 1 : -1;
            final difference = (b.people.values.first.deltaCents?.abs() ?? 0)
                .compareTo(a.people.values.first.deltaCents?.abs() ?? 0);
            return difference == 0 ? a.key.compareTo(b.key) : difference;
          });
    final hasAssigned = balance?.people.values
            .any((p) => p.paidCents != 0 || p.receivedCents != 0) ??
        false;
    final sideBySide = MediaQuery.sizeOf(context).width >= 1256 &&
        MediaQuery.textScalerOf(context).scale(16) <= 16 &&
        balance != null &&
        balance.events.isNotEmpty &&
        (balance.isComplete || hasAssigned);
    Widget hero() => BalanceResultHero(
        balance: balance, names: names, onAssign: _showAttributions);
    Widget chart() => NetComparisonChart(
        people: [balance!.people[_first]!, balance.people[_second]!],
        names: names,
        complete: balance.isComplete);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (sideBySide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 4, child: hero()),
          const SizedBox(width: 16),
          Expanded(
              flex: 6,
              child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                      color: ReportVisuals.surface(context),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: ReportVisuals.line(context))),
                  child: chart())),
        ])
      else
        hero(),
      const SizedBox(height: 16),
      Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: ReportVisuals.surface(context),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: ReportVisuals.line(context))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (balance != null && balance.events.isNotEmpty) ...[
              if (balance.isComplete || hasAssigned) ...[
                if (!sideBySide) ...[chart(), const SizedBox(height: 22)],
                LayoutBuilder(builder: (context, constraints) {
                  final width = constraints.maxWidth >= 650
                      ? (constraints.maxWidth - 16) / 2
                      : constraints.maxWidth;
                  return Wrap(spacing: 16, runSpacing: 12, children: [
                    for (final id in [_first!, _second!])
                      SizedBox(
                          width: width,
                          child: PersonBalanceSummary(
                              name: names[id]!,
                              value: balance.people[id]!,
                              pair: [_first!, _second!],
                              complete: balance.isComplete)),
                  ]);
                }),
              ] else
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                        'Attribuisci i movimenti per vedere i costi netti.')),
              const SizedBox(height: 16),
            ],
            Row(children: [
              Expanded(
                  child: Text('Persone confrontate',
                      style: Theme.of(context).textTheme.titleMedium)),
              if (validPair)
                IconButton(
                    tooltip: 'Inverti ordine delle persone',
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: const Icon(Icons.swap_horiz),
                    onPressed: () => setState(() {
                          final first = _first;
                          _first = _second;
                          _second = first;
                        })),
            ]),
            ExpansionTile(
              key: PageStorageKey(('balance-people', widget.scope)),
              tilePadding: EdgeInsets.zero,
              initiallyExpanded: !validPair,
              title: Text(validPair
                  ? '${names[_first]} e ${names[_second]}'
                  : 'Scegli le due persone'),
              subtitle: const Text('Cambia le persone del confronto'),
              children: [
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: LayoutBuilder(builder: (context, constraints) {
                      final width = constraints.maxWidth >= 650
                          ? (constraints.maxWidth - 16) / 2
                          : constraints.maxWidth;
                      return Wrap(spacing: 16, runSpacing: 12, children: [
                        SizedBox(width: width, child: _picker(true)),
                        SizedBox(width: width, child: _picker(false)),
                      ]);
                    }))
              ],
            ),
            if (balance != null) ...[
              _assignmentControls(context, balance),
              if (balance.events.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Dove cambia l’equilibrio',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                    'Prima le categorie da completare, poi gli scostamenti maggiori.',
                    style: TextStyle(color: ReportVisuals.muted(context))),
                const SizedBox(height: 14),
                for (final category in ordered.take(4))
                  _categoryPreview(context, category, names),
                KeyedSubtree(
                    key: const ValueKey('balance-categories'),
                    child: ExpansionTile(
                        key: PageStorageKey((
                          'balance-categories',
                          widget.scope,
                          _snapshot.hashCode
                        )),
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                            'Tutte le categorie (${balance.categories.length})'),
                        subtitle: const Text('Pagato, ricevuto, netto, quota e scostamento'),
                        children: [
                          for (final category in balance.categories)
                            _category(context, category)
                        ])),
                ExpansionTile(
                    key: PageStorageKey(
                        ('balance-figures', widget.scope, _snapshot.hashCode)),
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Valori completi del confronto'),
                    children: [
                      Text(
                          'Netto complessivo: ${_money(balance.netTotalCents)}'),
                      for (final id in [_first!, _second!])
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: _PersonFigures(
                                name: names[id]!,
                                value: balance.people[id]!,
                                figureKey: 'balance-full-total-$id')),
                    ]),
              ],
            ],
            ExpansionTile(
                key: PageStorageKey(('balance-how', widget.scope)),
                tilePadding: EdgeInsets.zero,
                title: const Text('Come viene calcolato'),
                leading: const Icon(Icons.info_outline),
                children: const [
                  Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                          'Per ogni categoria e per il totale: netto = pagato − entrate ricevute '
                          '− rimborsi ricevuti. La quota è il 50% del netto. '
                          'Scostamento +: sopra quota; scostamento −: sotto quota. '
                          'Le quote e gli scostamenti sono ripartiti al centesimo. '
                          'Le attribuzioni valgono solo per questo confronto e non cambiano i movimenti. '
                          'Entrate e rimborsi incidono sulla categoria in cui sono registrati. '
                          'Il calcolo considera solo i movimenti del periodo. '
                          'Eventuali conguagli già scambiati e saldi precedenti vanno considerati a parte.'))
                ]),
          ])),
    ]);
  }

  void _showAttributions() {
    _assignmentController.expand();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _assignmentAnchor.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(target,
            duration: const Duration(milliseconds: 250), alignment: .05);
      }
    });
  }

  Widget _categoryPreview(BuildContext context, CategoryBalance category,
      Map<String, String> names) {
    final transfer = category.transfer;
    return Container(
        key: ValueKey('balance-preview:${category.key}'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: ReportVisuals.canvas(context),
            borderRadius: BorderRadius.circular(16)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(category.label,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
              !category.isComplete
                  ? 'Parziale · ${category.unassigned.length} da attribuire'
                  : transfer == null
                      ? 'Categoria in equilibrio'
                      : '${names[transfer.fromId]} → ${names[transfer.toId]} · ${_money(transfer.cents)}',
              style: TextStyle(color: ReportVisuals.muted(context))),
          const SizedBox(height: 12),
          NetComparisonChart(
              people: [category.people[_first]!, category.people[_second]!],
              names: names,
              complete: category.isComplete,
              compact: true),
        ]));
  }

  Widget _verdict(BuildContext context, BalanceTransfer? transfer,
      {required bool total}) {
    final text = transfer == null
        ? (total ? 'Totale in equilibrio' : 'Categoria in equilibrio')
        : 'Per pareggiare ${total ? 'il periodo' : 'questa categoria'}: '
            '${_name(transfer.fromId)} → ${_name(transfer.toId)} ${_money(transfer.cents)}.';
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text,
            key: total ? const ValueKey('balance-total-verdict') : null,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)));
  }

  Widget _category(BuildContext context, CategoryBalance category) => Padding(
        key: ValueKey('balance-category:${category.key}'),
        padding: const EdgeInsets.symmetric(vertical: 14),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(category.label, style: Theme.of(context).textTheme.titleMedium),
          Text('Netto categoria: ${_money(category.netTotalCents)}'),
          if (category.isComplete)
            _verdict(context, category.transfer, total: false)
          else
            Text(
                'Categoria incompleta: ${category.unassigned.length} movimenti da attribuire. '
                'Scostamenti non calcolabili.'),
          LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth >= 780) {
              Widget cell(String text) => Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Text(text));
              return Table(columnWidths: const {
                0: FlexColumnWidth(1.5)
              }, children: [
                TableRow(children: [
                  for (final title in [
                    'Persona',
                    'Pagato',
                    'Ricevuto',
                    'Netto',
                    'Quota 50%',
                    'Scostamento'
                  ])
                    cell(title)
                ]),
                for (final id in [_first!, _second!])
                  TableRow(children: [
                    cell(_name(id)),
                    cell(_money(category.people[id]!.paidCents)),
                    cell(_money(category.people[id]!.receivedCents)),
                    cell(_money(category.people[id]!.netCents)),
                    cell(_money(category.people[id]!.targetCents)),
                    cell(category.people[id]!.deltaCents == null
                        ? 'Non calcolabile'
                        : _signed(category.people[id]!.deltaCents!)),
                  ]),
              ]);
            }
            return Column(children: [
              for (final id in [_first!, _second!])
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: _PersonFigures(
                        name: _name(id),
                        value: category.people[id]!,
                        figureKey: 'balance-${category.key}-$id'))
            ]);
          }),
        ]),
      );

  Widget _assignmentControls(BuildContext context, MemberBalance balance) {
    final pair = [_first!, _second!];
    final controls = balance.events
        .where((event) =>
            event.cents != 0 &&
            (event.kind == BalanceEventKind.reimbursement ||
                !pair.contains(event.explicitPersonId) ||
                _attributions.containsKey(event.key)))
        .toList();
    if (controls.isEmpty) return const SizedBox.shrink();
    final bulk = balance.unassigned
        .where((event) =>
            event.kind == BalanceEventKind.reimbursement &&
            pair.contains(event.explicitPersonId))
        .toList();
    final page = math.min(_assignmentPage, (controls.length - 1) ~/ 10);
    final visible = controls.skip(page * 10).take(10).toList();
    String originalPerson(BalanceEvent event) {
      final id = event.explicitPersonId;
      if (id == null) return 'Non registrato';
      final known = _members.any((member) => member.id == id);
      final name = known
          ? _name(id)
          : event.source.paidByName?.trim().isNotEmpty == true
              ? event.source.paidByName!.trim()
              : 'Persona non riconosciuta';
      return '$name${pair.contains(id) ? '' : ' (fuori dalla coppia)'}';
    }

    return Container(
        key: _assignmentAnchor,
        child: KeyedSubtree(
            key: const ValueKey('balance-attributions'),
            child: ExpansionTile(
                controller: _assignmentController,
                key: PageStorageKey(
                    ('balance-attributions', widget.scope, _snapshot.hashCode)),
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: !balance.isComplete,
                title: Text(
                    'Attribuzioni del confronto (${balance.unassigned.length} da attribuire)'),
                children: [
                  const Text(
                      'Il destinatario di un rimborso non è registrato: scegli chi lo ha ricevuto. '
                      'Per paganti mancanti o fuori dalla coppia, attribuisci il movimento solo per questo confronto '
                      'oppure apri l’originale. Le scelte valgono solo per questo confronto.'),
                  if (bulk.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: OutlinedButton(
                            onPressed: () => setState(() {
                                  for (final event in bulk) {
                                    _attributions[event.key] =
                                        BalanceAttribution.forEvent(
                                            event.explicitPersonId!, event);
                                  }
                                }),
                            child: Text(
                                'Conferma ${bulk.length} rimborsi ai paganti originali'))),
                  for (final event in visible)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                  '${event.kind == BalanceEventKind.expense ? 'Spesa' : event.kind == BalanceEventKind.income ? 'Entrata' : 'Rimborso'} · '
                                  '${event.source.title} · ${_money(event.cents)}'),
                              Text(
                                  '${event.categoryLabel} · ${DateFormat('d MMM yyyy', 'it_IT').format(event.date)}'),
                              Text(event.kind == BalanceEventKind.reimbursement
                                  ? 'Pagante originale: ${originalPerson(event)}. Destinatario del rimborso da confermare.'
                                  : '${event.kind == BalanceEventKind.expense ? 'Pagante registrato' : 'Persona associata registrata'}: ${originalPerson(event)}'),
                              DropdownButton<String>(
                                  key: ValueKey('balance-assign:${event.key}'),
                                  isExpanded: true,
                                  itemHeight: null,
                                  value: MemberBalance.assignedPerson(
                                      event, pair, _attributions),
                                  hint: const Text(
                                      'Da attribuire: scegli persona'),
                                  items: [
                                    const DropdownMenuItem(
                                        value: null,
                                        child: Text('Da attribuire')),
                                    for (final id in pair)
                                      DropdownMenuItem(
                                          value: id, child: Text(_name(id)))
                                  ],
                                  onChanged: (id) => setState(() {
                                        if (id == null) {
                                          _attributions.remove(event.key);
                                        } else {
                                          _attributions[event.key] =
                                              BalanceAttribution.forEvent(
                                                  id, event);
                                        }
                                      })),
                              Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                      onPressed: () => widget
                                          .onOpenOriginal(event.source.id),
                                      icon: const Icon(Icons.open_in_new,
                                          size: 16),
                                      label: const Text('Apri originale'))),
                            ])),
                  Text(
                      '${page * 10 + 1}–${page * 10 + visible.length} di ${controls.length} movimenti da verificare'),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    IconButton(
                        tooltip: 'Attribuzioni precedenti',
                        onPressed: page == 0
                            ? null
                            : () => setState(() => _assignmentPage = page - 1),
                        icon: const Icon(Icons.chevron_left)),
                    IconButton(
                        tooltip: 'Altre attribuzioni',
                        onPressed: (page + 1) * 10 >= controls.length
                            ? null
                            : () => setState(() => _assignmentPage = page + 1),
                        icon: const Icon(Icons.chevron_right)),
                  ]),
                ])));
  }
}

class _PersonFigures extends StatelessWidget {
  const _PersonFigures(
      {required this.name, required this.value, required this.figureKey});
  final String name, figureKey;
  final PersonBalance value;
  @override
  Widget build(BuildContext context) {
    Widget row(String label, String amount, String field) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Text(amount,
              key: ValueKey('$figureKey-$field'),
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ]));
    final delta = value.deltaCents;
    return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(12)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(name, style: Theme.of(context).textTheme.titleMedium),
          row('Pagato', _money(value.paidCents), 'paid'),
          row('Ricevuto (entrate + rimborsi)', _money(value.receivedCents),
              'received'),
          row('Netto attribuito', _money(value.netCents), 'net'),
          row('Quota 50%', _money(value.targetCents), 'target'),
          row('Scostamento', delta == null ? 'Non calcolabile' : _signed(delta),
              'delta'),
          if (delta != null)
            Text(delta > 0
                ? 'Sopra quota'
                : delta < 0
                    ? 'Sotto quota'
                    : 'In quota'),
        ]));
  }
}
