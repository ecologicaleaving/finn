import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:family_expense_tracker/features/reports/domain/group_report.dart';
import 'package:family_expense_tracker/features/reports/presentation/member_balance_section.dart';

const _members = [ReportMember('A', 'Anna'), ReportMember('G', 'Giovanna')];
ReportExpense _row(String id, int cents,
        {String? payer = 'A',
        String category = 'Cibo',
        String categoryId = 'food',
        String? type,
        bool refund = false}) =>
    ReportExpense(
      id: id,
      groupId: 'g',
      date: refund ? DateTime.utc(2020) : DateTime.utc(2026, 11, 2),
      cents: cents,
      createdBy: 'A',
      paidBy: payer,
      paidByName: payer == 'G' ? 'Giovanna' : 'Anna',
      categoryId: categoryId,
      categoryName: category,
      notes: id,
      transactionType: type,
      reimbursementStatus: refund ? 'reimbursed' : 'none',
      reimbursedAt: refund ? DateTime(2026, 11, 5, 10).toUtc() : null,
    );
GroupReport _report(List<ReportExpense> rows,
        {ReportMode mode = ReportMode.month}) =>
    GroupReport.calculate(
        groupId: 'g',
        period: ReportPeriod(DateTime(2026, 11), DateTime(2026, 11, 12),
            mode: mode),
        rows: rows);
GroupReport _example(
        {int refundCents = 4000, ReportMode mode = ReportMode.month}) =>
    _report([
      _row('a', 10000),
      _row('g', 10000, payer: 'G'),
      _row('refund', refundCents, refund: true),
    ], mode: mode);
Widget _screen(GroupReport report,
        {List<ReportMember> members = _members,
        Object scope = 'user-A:group-g',
        Future<void> Function(String)? open}) =>
    MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(
              child: MemberBalanceSection(
        key: const ValueKey('comparison'),
        report: report,
        members: members,
        scope: scope,
        onOpenOriginal: open ?? (_) async {},
      ))),
    );
Future<void> _choose(WidgetTester tester, String key, String label) async {
  final picker = find.byKey(ValueKey(key));
  await tester.ensureVisible(picker);
  await tester.tap(picker);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('it_IT'));
  for (final width in [390.0, 1440.0]) {
    testWidgets(
        'explicit different refund recipient and category figures fit $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_screen(_example()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('balance-incomplete')), findsOneWidget);
      expect(find.byKey(const ValueKey('balance-total-verdict')), findsNothing);
      expect(find.textContaining('Pagante originale: Anna.'), findsOneWidget);
      await _choose(tester, 'balance-assign:reimbursement:refund', 'Giovanna');
      expect(
          find.byWidgetPredicate((w) =>
              w is Semantics &&
              w.properties.label ==
                  'Per pareggiare il periodo: Giovanna → Anna 20,00 €.'),
          findsOneWidget);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('balance-total-A-net')))
              .data,
          contains('100,00'));
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('balance-total-G-net')))
              .data,
          contains('60,00'));
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('balance-total-A-delta')))
              .data,
          startsWith('+20,00'));
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('balance-total-G-delta')))
              .data,
          startsWith('-20,00'));
      await tester
          .ensureVisible(find.byKey(const ValueKey('balance-categories')));
      await tester.tap(find.text('Tutte le categorie (1)'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Per pareggiare questa categoria: Giovanna → Anna 20,00 €.'),
          findsOneWidget);
      expect(find.text('Cibo'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester
          .ensureVisible(find.byTooltip('Inverti ordine delle persone'));
      await tester.tap(find.byTooltip('Inverti ordine delle persone'));
      await tester.pumpAndSettle();
      expect(
          find.byWidgetPredicate((w) =>
              w is Semantics &&
              w.properties.label ==
                  'Per pareggiare il periodo: Giovanna → Anna 20,00 €.'),
          findsOneWidget);
    });
  }

  testWidgets(
      'bulk confirmation is explicit and only uses valid selected original payers',
      (tester) async {
    await tester.pumpWidget(_screen(_example()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('balance-incomplete')), findsOneWidget);
    final button = find.text('Conferma 1 rimborsi ai paganti originali');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate((w) =>
            w is Semantics &&
            w.properties.label ==
                'Per pareggiare il periodo: Anna → Giovanna 20,00 €.'),
        findsOneWidget);
  });

  testWidgets(
      'a three-member roster requires a deliberate pair; outsider stays unassigned',
      (tester) async {
    final members = [..._members, const ReportMember('child', 'Figlia')];
    await tester.pumpWidget(_screen(
        _report([
          _row('a', 10000),
          _row('g', 10000, payer: 'G'),
          _row('third', 1000, payer: 'child'),
        ]),
        members: members));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<DropdownButton<String>>(
                find.byKey(const ValueKey('balance-first-person')))
            .value,
        isNull);
    expect(find.byKey(const ValueKey('balance-total-verdict')), findsNothing);
    await _choose(tester, 'balance-first-person', 'Anna');
    await _choose(tester, 'balance-second-person', 'Giovanna');
    expect(find.byKey(const ValueKey('balance-incomplete')), findsOneWidget);
    expect(find.textContaining('Figlia (fuori dalla coppia)'), findsOneWidget);
    await _choose(tester, 'balance-assign:expense:third', 'Anna');
    expect(find.byKey(const ValueKey('balance-incomplete')), findsNothing);
    expect(find.byKey(const ValueKey('balance-total-verdict')), findsOneWidget);
  });

  testWidgets(
      'total balance calls out category differences that offset each other',
      (tester) async {
    await tester.pumpWidget(_screen(_report([
      _row('food-a', 12000),
      _row('food-g', 8000, payer: 'G'),
      _row('home-a', 8000, category: 'Casa', categoryId: 'home'),
      _row('home-g', 12000, payer: 'G', category: 'Casa', categoryId: 'home'),
    ])));
    await tester.pumpAndSettle();
    expect(find.text('Totale in equilibrio'), findsOneWidget);
    expect(find.text('2 categorie con scostamenti che si compensano.'),
        findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const ValueKey('balance-categories')));
    await tester.tap(find.text('Tutte le categorie (2)'));
    await tester.pumpAndSettle();
    expect(
        find.text('Per pareggiare questa categoria: Giovanna → Anna 20,00 €.'),
        findsOneWidget);
    expect(
        find.text('Per pareggiare questa categoria: Anna → Giovanna 20,00 €.'),
        findsOneWidget);
  });

  testWidgets(
      'source changes, account scope and year switch clear local refund confirmations',
      (tester) async {
    await tester.pumpWidget(_screen(_example()));
    await tester.pumpAndSettle();
    await _choose(tester, 'balance-assign:reimbursement:refund', 'Giovanna');
    expect(find.byKey(const ValueKey('balance-total-verdict')), findsOneWidget);
    await tester.pumpWidget(_screen(_example(refundCents: 5000)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('balance-incomplete')), findsOneWidget);
    await _choose(tester, 'balance-assign:reimbursement:refund', 'Giovanna');
    await tester.pumpWidget(
        _screen(_example(refundCents: 5000), scope: 'other-account:group-g'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('balance-incomplete')), findsOneWidget);
    await _choose(tester, 'balance-assign:reimbursement:refund', 'Giovanna');
    await tester.pumpWidget(_screen(
        _example(refundCents: 5000, mode: ReportMode.year),
        scope: 'other-account:group-g'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('balance-incomplete')), findsOneWidget);
  });

  testWidgets(
      'scope reset clears chosen pair even with the same empty snapshot',
      (tester) async {
    final members = [..._members, const ReportMember('child', 'Figlia')];
    await tester.pumpWidget(_screen(_report([]), members: members));
    await tester.pumpAndSettle();
    await _choose(tester, 'balance-first-person', 'Anna');
    await _choose(tester, 'balance-second-person', 'Giovanna');
    expect(find.text('Nessun movimento nel periodo'), findsOneWidget);
    await tester.pumpWidget(
        _screen(_report([]), members: members, scope: 'new-account:new-group'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<DropdownButton<String>>(
                find.byKey(const ValueKey('balance-first-person')))
            .value,
        isNull);
    expect(find.byKey(const ValueKey('balance-total-verdict')), findsNothing);
  });

  testWidgets(
      'incomplete total keeps an unrelated complete category available and opens originals',
      (tester) async {
    String? opened;
    await tester.pumpWidget(_screen(
        _report([
          _row('a', 12000),
          _row('g', 8000, payer: 'G'),
          _row('missing', 1000,
              payer: null, categoryId: 'unknown', category: 'Altro'),
        ]),
        open: (id) async => opened = id));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('balance-total-verdict')), findsNothing);
    expect(find.textContaining('Pagante registrato: Non registrato'),
        findsOneWidget);
    await tester.ensureVisible(find.text('Apri originale'));
    await tester.tap(find.text('Apri originale'));
    await tester.pumpAndSettle();
    expect(opened, 'missing');
    await tester
        .ensureVisible(find.byKey(const ValueKey('balance-categories')));
    await tester.tap(find.text('Tutte le categorie (2)'));
    await tester.pumpAndSettle();
    expect(
        find.text('Per pareggiare questa categoria: Giovanna → Anna 20,00 €.'),
        findsOneWidget);
    expect(find.textContaining('Categoria incompleta:'), findsOneWidget);
  });
}
