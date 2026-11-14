import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/member_balance.dart';

String reportMoney(int cents) =>
    NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 2)
        .format(cents / 100);

class ReportVisuals {
  static const forest = Color(0xFF2D4A3E);
  static const petrol = Color(0xFF285F6B);
  static bool dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
  static Color canvas(BuildContext context) =>
      dark(context) ? const Color(0xFF17231E) : const Color(0xFFF6F5EF);
  static Color surface(BuildContext context) =>
      dark(context) ? const Color(0xFF22322A) : const Color(0xFFFFFEFA);
  static Color ink(BuildContext context) =>
      dark(context) ? const Color(0xFFEDF3EF) : const Color(0xFF223A2E);
  static Color muted(BuildContext context) =>
      dark(context) ? const Color(0xFFCAD8CF) : const Color(0xFF53635A);
  static Color line(BuildContext context) =>
      dark(context) ? const Color(0xFF54685B) : const Color(0xFFD8E0D7);
}

/// Two distinct identities, stable when the displayed pair is reversed.
Color reportPersonColor(String id, Iterable<String> pair, {bool dark = false}) {
  final ids = pair.toSet().toList()..sort();
  return id == ids.first
      ? (dark ? const Color(0xFFA5D1B4) : ReportVisuals.forest)
      : (dark ? const Color(0xFF9BCDD4) : ReportVisuals.petrol);
}

/// A visual axis in cents; never derives a share from a net/total ratio.
class NetComparisonScale {
  NetComparisonScale(Iterable<PersonBalance> people, {required bool complete}) {
    final values = <int>[0];
    for (final person in people) {
      values.add(person.netCents);
      if (complete) values.add(person.targetCents);
    }
    minCents = values.reduce(math.min).toDouble();
    maxCents = values.reduce(math.max).toDouble();
    if (minCents == maxCents) {
      minCents = -1;
      maxCents = 1;
    }
  }
  late double minCents, maxCents;
  double position(int cents) => (cents - minCents) / (maxCents - minCents);
}

class ReportMoney extends StatelessWidget {
  const ReportMoney(this.cents,
      {super.key, this.style, this.signed = false, this.textKey});
  final int cents;
  final TextStyle? style;
  final bool signed;
  final Key? textKey;
  @override
  Widget build(BuildContext context) => ReportFormattedAmount(
      '${signed && cents > 0 ? '+' : ''}${reportMoney(cents)}',
      style: style,
      textKey: textKey);
}

class ReportFormattedAmount extends StatelessWidget {
  const ReportFormattedAmount(this.text, {super.key, this.style, this.textKey});
  final String text;
  final TextStyle? style;
  final Key? textKey;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final painter = TextPainter(
            text: TextSpan(
                text: text, style: style ?? DefaultTextStyle.of(context).style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context))
          ..layout();
        final visible = painter.width > constraints.maxWidth
            ? text.replaceAll('.', '.\u200B')
            : text;
        painter.dispose();
        return Text(visible,
            key: textKey, semanticsLabel: text, style: style, softWrap: true);
      });
}

class BalanceResultHero extends StatelessWidget {
  const BalanceResultHero(
      {super.key,
      required this.balance,
      required this.names,
      required this.onAssign});
  final MemberBalance? balance;
  final Map<String, String> names;
  final VoidCallback onAssign;
  @override
  Widget build(BuildContext context) {
    final value = balance;
    final transfer = value?.transfer;
    final verdict = transfer == null
        ? 'Totale in equilibrio'
        : 'Per pareggiare il periodo: '
            '${names[transfer.fromId]} → ${names[transfer.toId]} ${reportMoney(transfer.cents)}.';
    return Container(
      key: const ValueKey('balance-result-hero'),
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 24 : 32),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2D4A3E), Color(0xFF203B30)])),
      child: DefaultTextStyle(
          style: Theme.of(context)
              .textTheme
              .bodyMedium!
              .copyWith(color: const Color(0xFFEDF3EC)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Icon(Icons.balance, color: Colors.white, size: 18),
                  Text('Confronto 50/50 · Solo gruppo',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                ]),
            const SizedBox(height: 24),
            if (value == null) ...[
              Text('Scegli le due persone',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(color: Colors.white)),
              const SizedBox(height: 8),
              const Text(
                  'Seleziona due persone distinte. Con più di due componenti la coppia non viene scelta automaticamente.'),
            ] else if (value.events.isEmpty) ...[
              Text('Nessun movimento nel periodo',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(color: Colors.white)),
              const SizedBox(height: 8),
              const Text(
                  'Il confronto apparirà con le spese e le entrate registrate.'),
            ] else if (!value.isComplete) ...[
              Text('Confronto da completare',
                  key: const ValueKey('balance-incomplete'),
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(color: Colors.white)),
              const SizedBox(height: 10),
              Text(
                  '${value.unassigned.length} movimenti da attribuire. La compensazione totale non è calcolabile.'),
              const SizedBox(height: 20),
              Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                      onPressed: onAssign,
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: ReportVisuals.forest,
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14)),
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Attribuisci movimenti'))),
            ] else
              Semantics(
                  key: const ValueKey('balance-total-verdict'),
                  label: verdict,
                  container: true,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (transfer != null) ...[
                          const Text('Per pareggiare il periodo'),
                          const SizedBox(height: 6),
                          ReportMoney(transfer.cents,
                              textKey: const ValueKey('balance-hero-amount'),
                              style: Theme.of(context)
                                  .textTheme
                                  .displaySmall
                                  ?.copyWith(
                                      color: Colors.white,
                                      fontSize:
                                          MediaQuery.sizeOf(context).width < 600
                                              ? 40
                                              : 48,
                                      height: 1.15,
                                      fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          Text(
                              '${names[transfer.fromId]} → ${names[transfer.toId]}',
                              key: const ValueKey('balance-hero-direction'),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                        ] else ...[
                          Text('Totale in equilibrio',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(color: Colors.white)),
                          const SizedBox(height: 8),
                          Text(value.offsettingCategoryCount > 0
                              ? '${value.offsettingCategoryCount} categorie con scostamenti che si compensano.'
                              : 'Nel totale non c’è nulla da pareggiare nel periodo.'),
                        ],
                      ])),
          ])),
    );
  }
}

class PersonBalanceSummary extends StatelessWidget {
  const PersonBalanceSummary(
      {super.key,
      required this.name,
      required this.value,
      required this.pair,
      required this.complete});
  final String name;
  final PersonBalance value;
  final Iterable<String> pair;
  final bool complete;
  @override
  Widget build(BuildContext context) {
    final color = reportPersonColor(value.personId, pair,
        dark: ReportVisuals.dark(context));
    final ink = ReportVisuals.ink(context);
    Widget chip(String label, int cents, {bool delta = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(10)),
        child: Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(label, style: TextStyle(color: ink)),
              Text('${delta && cents > 0 ? '+' : ''}${reportMoney(cents)}',
                  key: delta
                      ? ValueKey('balance-total-${value.personId}-delta')
                      : null,
                  style: TextStyle(color: ink, fontWeight: FontWeight.w700)),
            ]));
    return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: ReportVisuals.surface(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: .35))),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(radius: 5, backgroundColor: color),
            const SizedBox(width: 10),
            Expanded(
                child: Text(name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: ink, fontWeight: FontWeight.w700)))
          ]),
          const SizedBox(height: 16),
          Text(complete ? 'Costo netto' : 'Netto attribuito · Parziale',
              style: TextStyle(color: ReportVisuals.muted(context))),
          const SizedBox(height: 4),
          LayoutBuilder(builder: (context, constraints) {
            final style = Theme.of(context).textTheme.headlineMedium!.copyWith(
                color: ink, fontSize: 30, fontWeight: FontWeight.w700);
            final measure = TextPainter(
                text: TextSpan(text: reportMoney(value.netCents), style: style),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context))
              ..layout();
            final fontSize =
                (30 * constraints.maxWidth / measure.width).clamp(18.0, 30.0);
            measure.dispose();
            return ReportMoney(value.netCents,
                textKey: ValueKey('balance-total-${value.personId}-net'),
                style: style.copyWith(fontSize: fontSize));
          }),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            chip('Pagato', value.paidCents),
            chip('Ricevuto', value.receivedCents),
            if (value.deltaCents != null)
              chip(
                  value.deltaCents! > 0
                      ? 'Sopra quota'
                      : value.deltaCents! < 0
                          ? 'Sotto quota'
                          : 'In quota',
                  value.deltaCents!,
                  delta: true)
            else
              Text('Scostamento non calcolabile',
                  key: ValueKey('balance-total-${value.personId}-delta'),
                  style: TextStyle(color: ReportVisuals.muted(context))),
          ]),
        ]));
  }
}

class NetComparisonChart extends StatelessWidget {
  const NetComparisonChart(
      {super.key,
      required this.people,
      required this.names,
      required this.complete,
      this.compact = false});
  final List<PersonBalance> people;
  final Map<String, String> names;
  final bool complete, compact;
  @override
  Widget build(BuildContext context) {
    final scale = NetComparisonScale(people, complete: complete);
    final pair = people.map((p) => p.personId);
    final muted = ReportVisuals.muted(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!compact) ...[
        Text(
            complete
                ? 'Netto e quota, a confronto'
                : 'Netti attribuiti · Parziale',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        if (complete)
          Wrap(spacing: 12, runSpacing: 6, children: [
            Text('Barra: costo netto', style: TextStyle(color: muted)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.diamond, size: 11, color: ReportVisuals.ink(context)),
              const SizedBox(width: 5),
              Text('Tacca: quota 50%', style: TextStyle(color: muted)),
            ]),
          ])
        else
          Text('Le quote si confrontano dopo le attribuzioni mancanti.',
              style: TextStyle(color: muted)),
        const SizedBox(height: 16),
      ],
      for (final person in people)
        Padding(
          padding: EdgeInsets.only(bottom: compact ? 10 : 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: CircleAvatar(
                      radius: 4,
                      backgroundColor: reportPersonColor(person.personId, pair,
                          dark: ReportVisuals.dark(context)))),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(names[person.personId] ?? 'Componente',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: ReportVisuals.ink(context)))),
              const SizedBox(width: 12),
              Flexible(
                  child: ReportMoney(person.netCents,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: ReportVisuals.ink(context),
                          fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, constraints) {
              final zero = scale.position(0) * constraints.maxWidth;
              final point =
                  scale.position(person.netCents) * constraints.maxWidth;
              final target =
                  scale.position(person.targetCents) * constraints.maxWidth;
              return SizedBox(
                  height: compact ? 18 : 24,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned.fill(
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: ReportVisuals.line(context)
                                    .withValues(alpha: .45),
                                borderRadius: BorderRadius.circular(5)))),
                    Positioned(
                        left: math.min(zero, point),
                        width: (point - zero).abs(),
                        top: 3,
                        bottom: 3,
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: reportPersonColor(person.personId, pair,
                                    dark: ReportVisuals.dark(context)),
                                borderRadius: BorderRadius.circular(3)))),
                    Positioned(
                        key: ValueKey('net-zero-axis:${person.personId}'),
                        left: zero.clamp(0, constraints.maxWidth - 1),
                        width: 1,
                        top: -3,
                        bottom: -3,
                        child: ColoredBox(color: ReportVisuals.muted(context))),
                    if (complete)
                      Positioned(
                          key: ValueKey('net-quota-marker:${person.personId}'),
                          left: target - 5,
                          top: -3,
                          bottom: -3,
                          width: 10,
                          child: Column(children: [
                            Icon(Icons.diamond,
                                size: 10, color: ReportVisuals.ink(context)),
                            Expanded(
                                child: Container(
                                    width: 2,
                                    color: ReportVisuals.ink(context)))
                          ])),
                  ]));
            }),
          ]),
        ),
      if (!compact)
        Text(
            'Scala comune: ${reportMoney(scale.minCents.round())} → '
            '${reportMoney(scale.maxCents.round())} · linea verticale = zero',
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
    ]);
  }
}
