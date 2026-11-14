import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:family_expense_tracker/features/reports/domain/group_report.dart';
import 'package:family_expense_tracker/features/reports/domain/member_balance.dart';
import 'package:family_expense_tracker/features/reports/presentation/member_balance_section.dart';
import 'package:family_expense_tracker/features/reports/presentation/report_visuals.dart';

const _members = [ReportMember('A', 'Anna'), ReportMember('G', 'Giovanna')];
ReportExpense _row(String id, int cents,
        {String? person = 'A',
        String category = 'food',
        bool income = false}) =>
    ReportExpense(
        id: id,
        groupId: 'g',
        date: DateTime.utc(2026, 11, 2),
        cents: cents,
        createdBy: 'creator',
        paidBy: person,
        categoryId: category,
        categoryName: category,
        transactionType: income ? 'income' : null);
GroupReport _report(List<ReportExpense> rows) => GroupReport.calculate(
    groupId: 'g',
    period: ReportPeriod(DateTime(2026, 11), DateTime(2026, 11, 13)),
    rows: rows);
MemberBalance _balance(List<ReportExpense> rows) => MemberBalance.calculate(
    report: _report(rows), firstId: 'A', secondId: 'G', attributions: {});
Widget _host(Widget child, {bool dark = false, double scale = 1}) =>
    MaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: Padding(
                        padding: const EdgeInsets.all(20), child: child)))));

void main() {
  setUpAll(() => initializeDateFormatting('it_IT'));
  testWidgets('hero distinguishes transfer, balanced, empty and unknown',
      (tester) async {
    final cases = [
      _balance([_row('a', 10000), _row('g', 6000, person: 'G')]),
      _balance([_row('a', 10000), _row('g', 10000, person: 'G')]),
      _balance([]),
      _balance([_row('unknown', 10000, person: null)]),
    ];
    for (var i = 0; i < cases.length; i++) {
      await tester.pumpWidget(_host(BalanceResultHero(
          balance: cases[i],
          names: const {'A': 'Anna', 'G': 'Giovanna'},
          onAssign: () {})));
      await tester.pumpAndSettle();
      expect(find.text('Confronto 50/50 · Solo gruppo'), findsOneWidget);
      expect(find.byKey(const ValueKey('balance-incomplete')),
          i == 3 ? findsOneWidget : findsNothing);
      expect(find.text('Totale in equilibrio'),
          i == 1 ? findsOneWidget : findsNothing);
      expect(find.text('Nessun movimento nel periodo'),
          i == 2 ? findsOneWidget : findsNothing);
      if (i == 0) {
        final verdict = tester.widget<Semantics>(
            find.byKey(const ValueKey('balance-total-verdict')));
        expect(verdict.properties.label, contains('Giovanna → Anna 20,00'));
      }
      if (i == 3) {
        final button = find.ancestor(
            of: find.text('Attribuisci movimenti'),
            matching: find.byWidgetPredicate((w) => w is FilledButton));
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        expect(
            find.byKey(const ValueKey('balance-total-verdict')), findsNothing);
      }
    }
  });

  testWidgets(
      'negative net chart has one common zero axis and gated quota markers',
      (tester) async {
    final balance = _balance([
      _row('income-a', 7000, income: true),
      _row('income-g', 3000, person: 'G', income: true),
    ]);
    final scale = NetComparisonScale(balance.people.values, complete: true);
    expect(scale.minCents, -7000);
    expect(scale.maxCents, 0);
    expect(scale.position(-3000), greaterThan(scale.position(-7000)));
    for (final complete in [true, false]) {
      await tester.pumpWidget(_host(NetComparisonChart(
          people: balance.people.values.toList(),
          names: const {'A': 'Anna', 'G': 'Giovanna'},
          complete: complete)));
      await tester.pumpAndSettle();
      final a = find.byKey(const ValueKey('net-zero-axis:A'));
      final g = find.byKey(const ValueKey('net-zero-axis:G'));
      expect(tester.getTopLeft(a).dx, tester.getTopLeft(g).dx);
      expect(find.byKey(const ValueKey('net-quota-marker:A')),
          complete ? findsOneWidget : findsNothing);
      expect(find.text('-70,00\u00A0€'), findsOneWidget);
      expect(find.textContaining('-30,00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  test('identity colors survive pair swap and have accessible text contrast',
      () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
    }

    for (final dark in [false, true]) {
      for (final id in ['A', 'G']) {
        final color = reportPersonColor(id, ['A', 'G'], dark: dark);
        expect(color, reportPersonColor(id, ['G', 'A'], dark: dark));
        expect(
            contrast(color,
                dark ? const Color(0xFF22322A) : const Color(0xFFFFFEFA)),
            greaterThanOrEqualTo(4.5));
      }
    }
    expect(reportPersonColor('A', ['A', 'G']),
        isNot(reportPersonColor('G', ['A', 'G'])));
    expect(contrast(Colors.white, ReportVisuals.forest),
        greaterThanOrEqualTo(4.5));
  });

  testWidgets(
      'ranked preview preserves every category and complete figures behind expanders',
      (tester) async {
    await tester.pumpWidget(_host(MemberBalanceSection(
        report: _report([
          for (var i = 1; i <= 6; i++)
            _row('row$i', i * 100, category: 'category$i')
        ]),
        members: _members,
        scope: 'scope',
        onOpenOriginal: (_) async {})));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('balance-preview:id:category6')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('balance-preview:id:category1')),
        findsNothing);
    final all = find.text('Tutte le categorie (6)');
    await tester.ensureVisible(all);
    await tester.tap(all);
    await tester.pumpAndSettle();
    for (var i = 1; i <= 6; i++) {
      expect(find.byKey(ValueKey('balance-category:id:category$i')),
          findsOneWidget);
    }
    final figures = find.text('Valori completi del confronto');
    await tester.ensureVisible(figures);
    await tester.tap(figures);
    await tester.pumpAndSettle();
    expect(find.textContaining('Netto complessivo: 21,00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final tile
        in tester.widgetList<ExpansionTile>(find.byType(ExpansionTile))) {
      expect(tile.key, isA<PageStorageKey>());
    }
  });

  for (final width in [390.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets(
          'large signed net remains complete at scale1.5 width$width dark$dark',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final value = _balance([_row('large', 79999992)]).people['A']!;
        await tester.pumpWidget(_host(
            PersonBalanceSummary(
                name: 'Anna dal nome molto lungo',
                value: value,
                pair: const ['A', 'G'],
                complete: true),
            dark: dark,
            scale: 1.5));
        await tester.pumpAndSettle();
        final amount = tester
            .widget<Text>(find.byKey(const ValueKey('balance-total-A-net')));
        expect(amount.semanticsLabel, contains('799.999,92'));
        expect(amount.data!.replaceAll('\u200B', ''), contains('799.999,92'));
        expect(amount.overflow, isNot(TextOverflow.ellipsis));
        expect(amount.style!.fontSize, greaterThanOrEqualTo(18));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
