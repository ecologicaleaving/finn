import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:family_expense_tracker/core/errors/failures.dart';
import 'package:family_expense_tracker/features/auth/domain/entities/user_entity.dart';
import 'package:family_expense_tracker/features/auth/domain/repositories/auth_repository.dart';
import 'package:family_expense_tracker/features/auth/presentation/providers/auth_provider.dart';
import 'package:family_expense_tracker/features/auth/presentation/screens/main_navigation_screen.dart';
import 'package:family_expense_tracker/features/dashboard/presentation/providers/dashboard_refresh.dart';
import 'package:family_expense_tracker/features/groups/domain/entities/family_group_entity.dart';
import 'package:family_expense_tracker/features/groups/domain/entities/member_entity.dart';
import 'package:family_expense_tracker/features/groups/domain/repositories/group_repository.dart';
import 'package:family_expense_tracker/features/groups/presentation/providers/group_provider.dart';
import 'package:family_expense_tracker/features/reports/data/report_loader.dart';
import 'package:family_expense_tracker/features/reports/domain/group_report.dart';
import 'package:family_expense_tracker/features/reports/presentation/report_provider.dart';
import 'package:family_expense_tracker/features/reports/presentation/report_screen.dart';
import 'package:family_expense_tracker/features/reports/presentation/report_income_section.dart';
import 'package:family_expense_tracker/features/widget/domain/repositories/widget_repository.dart';
import 'package:family_expense_tracker/features/widget/presentation/services/widget_update_service.dart';

const _a = UserEntity(
    id: 'A', email: 'a@example.test', displayName: 'Anna', groupId: 'g');
const _b = UserEntity(
    id: 'B', email: 'b@example.test', displayName: 'Bruno', groupId: 'other');
const _group = FamilyGroupEntity(id: 'g', name: 'Casa nostra', createdBy: 'A');
final _users = StateProvider<UserEntity?>((ref) => _a);

class _UnusedGroups implements GroupRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GroupControl extends GroupNotifier {
  _GroupControl(GroupState initial) : super(_UnusedGroups()) {
    state = initial;
  }
  void show(GroupState value) => state = value;
}

class _Loader implements ReportLoader {
  _Loader(this.fetch);
  final Future<List<ReportExpense>> Function(
      String user, String group, ReportPeriod period) fetch;
  final calls =
      <({String user, String group, DateTime month, ReportMode mode})>[];
  @override
  Future<List<ReportExpense>> load(
      {required String userId,
      required String groupId,
      required ReportPeriod period}) {
    calls.add(
        (user: userId, group: groupId, month: period.start, mode: period.mode));
    return fetch(userId, groupId, period);
  }
}

class _Auth extends AuthRepository {
  @override
  Future<Either<Failure, UserEntity>> getCurrentUser() async => const Right(_a);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedWidgets implements WidgetRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuietWidgets extends WidgetUpdateService {
  _QuietWidgets() : super(_UnusedWidgets());
  @override
  Future<void> triggerUpdate() async {}
}

ReportExpense _expense(String id, DateTime date, int cents,
        {String group = 'g'}) =>
    ReportExpense(
      id: id,
      groupId: group,
      date: date,
      cents: cents,
      createdBy: 'A',
      categoryId: 'food',
      categoryName: 'Alimentari',
      notes: 'Spesa al mercato',
      paidBy: 'A',
      paidByName: 'Anna',
    );

ReportExpense _income(String id,
        {int cents = 30000, String? title, DateTime? date}) =>
    ReportExpense(
        id: id,
        groupId: 'g',
        date: date ?? DateTime.utc(2026, 11, 3),
        cents: cents,
        createdBy: 'A',
        transactionType: 'income',
        categoryId: 'support',
        categoryName: 'Aiuti statali',
        notes: title ?? 'Assegni familiari',
        paidBy: 'giovanna',
        paidByName: 'Nome precedente');

ReportExpense _refund(String id, {int cents = 10000}) => ReportExpense(
    id: id,
    groupId: 'g',
    date: DateTime.utc(2020, 1, 1),
    cents: cents,
    createdBy: 'A',
    paidBy: 'A',
    paidByName: 'Anna',
    notes: 'Visita precedente',
    categoryName: 'Salute',
    reimbursementStatus: 'reimbursed',
    reimbursedAt: DateTime(2026, 11, 4, 10).toUtc());

ProviderContainer _container(_Loader loader,
        {GroupState group =
            const GroupState(status: GroupStatus.loaded, group: _group),
        DateTime? today}) =>
    ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) => ref.watch(_users)),
      groupProvider.overrideWith((ref) => _GroupControl(group)),
      reportLoaderProvider.overrideWithValue(loader),
      reportClockProvider
          .overrideWithValue(() => today ?? DateTime(2026, 11, 11)),
      authRepositoryProvider.overrideWithValue(_Auth()),
      widgetUpdateServiceProvider.overrideWithValue(_QuietWidgets()),
    ]);

Future<void> _mount(WidgetTester tester, ProviderContainer container,
    {Widget screen = const ReportScreen(), GoRouter? router}) async {
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: router == null
          ? MaterialApp(home: screen)
          : MaterialApp.router(routerConfig: router)));
  await tester.pump();
}

MemberEntity _member(String id, String name, {String group = 'g'}) =>
    MemberEntity(
        userId: id,
        groupId: group,
        displayName: name,
        email: '$id@example.test',
        role: MemberRole.member);

void main() {
  setUpAll(() => initializeDateFormatting('it_IT'));

  testWidgets(
      '50/50 attribution does not fetch and is reset by the actual month/year report scope',
      (tester) async {
    final loader = _Loader((_, __, ___) async => [
          _expense('a-paid', DateTime.utc(2026, 11, 2), 10000),
          ReportExpense(
              id: 'g-paid',
              groupId: 'g',
              date: DateTime.utc(2026, 11, 2),
              cents: 10000,
              createdBy: 'A',
              paidBy: 'G',
              paidByName: 'Giovanna',
              categoryId: 'food',
              categoryName: 'Alimentari'),
          _refund('old', cents: 4000),
        ]);
    final container = _container(loader,
        group: GroupState(
            status: GroupStatus.loaded,
            group: _group,
            members: [_member('A', 'Anna'), _member('G', 'Giovanna')]));
    addTearDown(container.dispose);
    await _mount(tester, container);
    await tester.pumpAndSettle();
    final picker =
        find.byKey(const ValueKey('balance-assign:reimbursement:old'));
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Giovanna').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('balance-total-verdict')), findsOneWidget);
    expect(loader.calls.length, 1);
    await tester.tap(find.text('Anno'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('balance-incomplete')), findsOneWidget);
    expect(find.byKey(const ValueKey('balance-total-verdict')), findsNothing);
    expect(loader.calls.length, 2);
  });

  testWidgets(
      'adding income through the existing route refreshes the report on return',
      (tester) async {
    var saved = false;
    final loader =
        _Loader((_, __, ___) async => saved ? [_income('new-income')] : []);
    final container = _container(loader);
    addTearDown(container.dispose);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const ReportScreen()),
      GoRoute(
          path: '/add-income',
          builder: (context, _) => Scaffold(
              body: FilledButton(
                  onPressed: () {
                    saved = true;
                    invalidatePersonalDashboardProviders(container.invalidate);
                    context.pop();
                  },
                  child: const Text('Registra entrata')))),
    ]);
    addTearDown(router.dispose);
    await _mount(tester, container, router: router);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Aggiungi entrata'), 500,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Aggiungi entrata'));
    await tester.pumpAndSettle();
    expect(find.text('Registra entrata'), findsOneWidget);
    await tester.tap(find.text('Registra entrata'));
    await tester.pumpAndSettle();
    expect(loader.calls.length, 2);
    expect(find.text('Assegni familiari'), findsOneWidget);
    expect(find.text('Nessuna entrata o rimborso ricevuto nel periodo.'),
        findsNothing);
  });

  for (final width in [390.0, 1440.0]) {
    testWidgets(
        'balance, income search and original refund detail fit width $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final loader = _Loader((_, __, ___) async => [
            _expense('gross', DateTime.utc(2026, 11, 1), 100000),
            _income('income'),
            _refund('old-original'),
          ]);
      final container = _container(loader,
          group: GroupState(
              status: GroupStatus.loaded,
              group: _group,
              members: [
                _member('A', 'Anna'),
                _member('giovanna', 'Giovanna')
              ]));
      addTearDown(container.dispose);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const ReportScreen()),
        GoRoute(
            path: '/expense/:id',
            builder: (_, state) => Scaffold(
                body: Text('Originale ${state.pathParameters['id']}'))),
        GoRoute(
            path: '/add-income',
            builder: (_, __) => const Scaffold(body: Text('Nuova entrata'))),
      ]);
      addTearDown(router.dispose);
      await _mount(tester, container, router: router);
      await tester.pumpAndSettle();
      expect(find.text('Entrate registrate'), findsOneWidget);
      expect(find.text('Rimborsi ricevuti'), findsOneWidget);
      expect(find.text('Saldo del periodo'), findsOneWidget);
      expect(find.text('Rimborsi attesi'), findsOneWidget);
      expect(find.textContaining('-600,00'), findsOneWidget);
      expect(find.text('Spese lorde'), findsOneWidget);
      await tester.scrollUntilVisible(
          find.text('Andamento degli ultimi 6 mesi'), 500,
          scrollable: find.byType(Scrollable).first);
      expect(
          tester
              .widget<BarChart>(find.byType(BarChart))
              .data
              .barGroups
              .last
              .barRods
              .length,
          2);
      await tester.scrollUntilVisible(
          find.text('Entrate per persona associata'), 500,
          scrollable: find.byType(Scrollable).first);
      final personCard = find.ancestor(
          of: find.text('Entrate per persona associata'),
          matching: find.byType(Card));
      expect(find.descendant(of: personCard, matching: find.text('Giovanna')),
          findsOneWidget);
      await tester.scrollUntilVisible(find.byType(TextField), 500,
          scrollable: find.byType(Scrollable).first);
      final details = find.ancestor(
          of: find.byType(TextField), matching: find.byType(Card));
      await tester.enterText(find.byType(TextField), 'Giovanna');
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: details, matching: find.text('Assegni familiari')),
          findsOneWidget);
      expect(
          find.descendant(
              of: details, matching: find.text('Visita precedente')),
          findsNothing);
      expect(
          find.descendant(
              of: details,
              matching: find.textContaining('Totale filtrato: 300,00')),
          findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Aiuti statali');
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: details, matching: find.text('Assegni familiari')),
          findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Rimborsi'));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: details, matching: find.text('Assegni familiari')),
          findsNothing);
      expect(
          find.descendant(
              of: details, matching: find.text('Persona associata: Anna')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Visita precedente'));
      await tester.tap(find.text('Visita precedente'));
      await tester.pumpAndSettle();
      expect(find.text('Originale old-original'), findsOneWidget);
      expect(loader.calls.length, 1);
    });
  }

  for (final refundOnly in [false, true]) {
    testWidgets(
        'a period with only ${refundOnly ? 'refunds' : 'income'} keeps the balance and detail visible',
        (tester) async {
      final loader = _Loader((_, __, ___) async =>
          [refundOnly ? _refund('old') : _income('income')]);
      final container = _container(loader);
      addTearDown(container.dispose);
      await _mount(tester, container);
      await tester.pumpAndSettle();
      expect(find.text('Nessuna spesa nel periodo'), findsOneWidget);
      expect(find.text('Saldo del periodo'), findsOneWidget);
      await tester.scrollUntilVisible(find.byType(TextField), 500,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(refundOnly ? 'Visita precedente' : 'Assegni familiari'),
          findsOneWidget);
      expect(find.text('Dettaglio entrate e rimborsi'), findsOneWidget);
      await tester.ensureVisible(find.text('Cosa sapere sui rimborsi'));
      await tester.tap(find.text('Cosa sapere sui rimborsi'));
      await tester.pumpAndSettle();
      expect(find.textContaining('registra lo stesso incasso una sola volta'),
          findsOneWidget);
      if (refundOnly)
        expect(find.text('Nessuna entrata registrata nel periodo.'),
            findsNWidgets(2));
    });
  }

  testWidgets('income details page every movement and total the whole filter',
      (tester) async {
    final report = GroupReport.calculate(
        groupId: 'g',
        period: ReportPeriod(DateTime(2026, 11), DateTime(2026, 11, 11)),
        rows: List.generate(
            45,
            (i) => _income('income-${i.toString().padLeft(2, '0')}',
                cents: 100, title: 'Entrata ${i.toString().padLeft(2, '0')}')));
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
              body: SingleChildScrollView(
                  child: ReportInflowDetails(
                      report: report,
                      members: const [ReportMember('giovanna', 'Giovanna')])))),
      GoRoute(
          path: '/add-income',
          builder: (_, __) => const Scaffold(body: Text('Nuova entrata'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('1–20 di 45 movimenti'), findsOneWidget);
    expect(find.textContaining('Totale filtrato: 45,00'), findsOneWidget);
    expect(find.text('Entrata 00'), findsOneWidget);
    expect(find.text('Entrata 44'), findsNothing);
    await tester.ensureVisible(find.byTooltip('Altri movimenti'));
    await tester.tap(find.byTooltip('Altri movimenti'));
    await tester.pumpAndSettle();
    expect(find.text('21–40 di 45 movimenti'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Altri movimenti'));
    await tester.tap(find.byTooltip('Altri movimenti'));
    await tester.pumpAndSettle();
    expect(find.text('41–45 di 45 movimenti'), findsOneWidget);
    expect(find.text('Entrata 44'), findsOneWidget);
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Entrata 44');
    await tester.pumpAndSettle();
    expect(find.textContaining('Totale filtrato: 1,00'), findsOneWidget);
    await tester.tap(find.text('Rimborsi'));
    await tester.pumpAndSettle();
    expect(find.text('Nessun movimento corrisponde alla ricerca.'),
        findsOneWidget);
    await tester.ensureVisible(find.text('Aggiungi entrata'));
    await tester.tap(find.text('Aggiungi entrata'));
    await tester.pumpAndSettle();
    expect(find.text('Nuova entrata'), findsOneWidget);
  });

  testWidgets(
      'returning from a refund status change refreshes an otherwise unchanged report',
      (tester) async {
    var reimbursed = true;
    final loader =
        _Loader((_, __, ___) async => reimbursed ? [_refund('old')] : []);
    final container = _container(loader);
    addTearDown(container.dispose);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const ReportScreen()),
      GoRoute(
          path: '/expense/:id',
          builder: (context, _) => Scaffold(
              body: FilledButton(
                  onPressed: () {
                    reimbursed = false;
                    context.pop();
                  },
                  child: const Text('Annulla rimborso')))),
    ]);
    addTearDown(router.dispose);
    await _mount(tester, container, router: router);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Visita precedente'), 500,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Visita precedente'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla rimborso'));
    await tester.pumpAndSettle();
    expect(loader.calls.length, 2);
    expect(find.text('Visita precedente'), findsNothing);
    expect(find.text('Nessuna entrata o rimborso ricevuto nel periodo.'),
        findsOneWidget);
  });

  for (final width in [390.0, 1440.0]) {
    testWidgets('annual report and member payments fit width $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final loader = _Loader((_, __, ___) async => [
            _expense('jan', DateTime.utc(2026, 1, 10), 3000),
            _expense('nov', DateTime.utc(2026, 11, 10), 7000),
            ReportExpense(
                id: 'former',
                groupId: 'g',
                date: DateTime.utc(2026, 7, 10),
                cents: 2500,
                createdBy: 'A',
                paidBy: 'former',
                paidByName: 'Carlo',
                categoryName: 'Casa'),
          ]);
      final container = _container(loader,
          group: GroupState(
              status: GroupStatus.loaded,
              group: _group,
              members: [
                _member('A', 'Anna'),
                _member('zero', 'Giulia dal nome molto lungo')
              ]));
      addTearDown(container.dispose);
      await _mount(tester, container);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anno'));
      await tester.pumpAndSettle();
      expect(loader.calls.last.mode, ReportMode.year);
      expect(find.text('L’anno finora'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Andamento dei 12 mesi'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(
          tester.widget<BarChart>(find.byType(BarChart)).data.barGroups.length,
          12);
      await tester.ensureVisible(find.text('Valori mensili (12)'));
      await tester.tap(find.text('Valori mensili (12)'));
      await tester.pumpAndSettle();
      expect(find.text('dic 2026 · Non ancora trascorso'), findsOneWidget);
      expect(find.text('nov 2026 · parziale'), findsOneWidget);
      expect(find.text('feb 2026'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Chi ha pagato'), 300,
          scrollable: find.byType(Scrollable).first);
      final paymentsCard = find.ancestor(
          of: find.text('Chi ha pagato'), matching: find.byType(Card));
      expect(find.descendant(of: paymentsCard, matching: find.text('Anna')),
          findsOneWidget);
      expect(find.descendant(of: paymentsCard, matching: find.text('Carlo')),
          findsOneWidget);
      expect(
          find.descendant(
              of: paymentsCard,
              matching: find.text('Giulia dal nome molto lungo')),
          findsOneWidget);
      final memberCard = find.ancestor(
          of: find.text('Chi ha pagato'), matching: find.byType(Card));
      expect(
          find.descendant(
              of: memberCard, matching: find.textContaining('80,0%')),
          findsOneWidget);
      expect(
          find.descendant(
              of: memberCard, matching: find.textContaining('20,0%')),
          findsOneWidget);
      expect(find.byType(Table), width >= 1000 ? findsOneWidget : findsNothing);
      await tester.scrollUntilVisible(
          find.textContaining('Mese più oneroso'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('Mese più oneroso · novembre 2026'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'month and year selections are independent and future years disabled',
      (tester) async {
    final loader = _Loader((_, __, ___) async => []);
    final container = _container(loader);
    addTearDown(container.dispose);
    await _mount(tester, container);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mese precedente'));
    await tester.pumpAndSettle();
    expect(find.text('ottobre 2026'), findsOneWidget);
    await tester.tap(find.text('Anno'));
    await tester.pumpAndSettle();
    final next = find.byWidgetPredicate((widget) =>
        widget is IconButton && widget.tooltip == 'Anno successivo');
    expect(tester.widget<IconButton>(next).onPressed, isNull);
    await tester.tap(find.byTooltip('Anno precedente'));
    await tester.pumpAndSettle();
    expect(find.text('2025'), findsOneWidget);
    await tester.tap(find.text('Mese'));
    await tester.pumpAndSettle();
    expect(find.text('ottobre 2026'), findsOneWidget);
    await tester.tap(find.text('Anno'));
    await tester.pumpAndSettle();
    expect(find.text('2025'), findsOneWidget);
    expect(loader.calls.last.month, DateTime.utc(2025));
  });

  testWidgets(
      'roster changes update names and zero members without refetching expenses',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final loader = _Loader((_, __, ___) async =>
        [_expense('paid', DateTime.utc(2026, 11, 1), 1000)]);
    final container = _container(loader);
    addTearDown(container.dispose);
    await _mount(tester, container);
    await tester.pumpAndSettle();
    (container.read(groupProvider.notifier) as _GroupControl)
        .show(GroupState(status: GroupStatus.loaded, group: _group, members: [
      _member('A', 'Anna aggiornata'),
      _member('zero', 'Giulia'),
      _member('wrong-group', 'Non deve comparire', group: 'other')
    ]));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Chi ha pagato'), 300,
        scrollable: find.byType(Scrollable).first);
    final paymentsCard = find.ancestor(
        of: find.text('Chi ha pagato'), matching: find.byType(Card));
    expect(
        find.descendant(
            of: paymentsCard, matching: find.text('Anna aggiornata')),
        findsOneWidget);
    expect(find.descendant(of: paymentsCard, matching: find.text('Giulia')),
        findsOneWidget);
    expect(find.text('Non deve comparire'), findsNothing);
    expect(find.textContaining('0,0% del totale · 0 spese'), findsOneWidget);
    expect(loader.calls.length, 1);
  });

  testWidgets(
      'late monthly and current-year results cannot overwrite a historical year',
      (tester) async {
    final monthly = Completer<List<ReportExpense>>();
    final currentYear = Completer<List<ReportExpense>>();
    final loader = _Loader((_, __, period) => period.mode == ReportMode.month
        ? monthly.future
        : period.start.year == 2026
            ? currentYear.future
            : Future.value([_expense('past', DateTime.utc(2025, 7, 1), 100)]));
    final container = _container(loader, today: DateTime(2026, 1, 11));
    addTearDown(container.dispose);
    await _mount(tester, container);
    await tester.tap(find.text('Anno'));
    await tester.pump();
    await tester.tap(find.byTooltip('Anno precedente'));
    await tester.pumpAndSettle();
    monthly
        .complete([_expense('month-secret', DateTime.utc(2026, 1, 1), 999999)]);
    currentYear
        .complete([_expense('year-secret', DateTime.utc(2026, 1, 1), 999999)]);
    await tester.pumpAndSettle();
    expect(find.text('2025'), findsOneWidget);
    expect(find.text('L’anno in numeri'), findsOneWidget);
    expect(find.textContaining('9.999'), findsNothing);
    expect(loader.calls.last.mode, ReportMode.year);
    expect(loader.calls.last.month, DateTime.utc(2025));
    expect(loader.calls.take(2).map((call) => call.month),
        everyElement(DateTime.utc(2026)));
    expect(loader.calls.take(2).map((call) => call.mode),
        [ReportMode.month, ReportMode.year]);
  });

  testWidgets(
      'leap annual comparison shows calendar intervals without claiming equal day counts',
      (tester) async {
    final loader = _Loader((_, __, ___) async => []);
    final container = _container(loader, today: DateTime(2024, 2, 29));
    addTearDown(container.dispose);
    await _mount(tester, container);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anno'));
    await tester.pumpAndSettle();
    expect(find.text('1 gen 2024 – 29 feb 2024'), findsOneWidget);
    expect(find.textContaining('1 gen 2024 – 28 feb 2024:'), findsOneWidget);
    expect(find.textContaining('1 gen 2023 – 28 feb 2023:'), findsOneWidget);
    expect(find.text('Confronto fino alla stessa data di calendario'),
        findsOneWidget);
    expect(find.textContaining('stesso numero di giorni'), findsNothing);
  });

  test(
      'shared expense invalidation refreshes both monthly and annual report families',
      () async {
    var amount = 100;
    final loader = _Loader((_, __, ___) async =>
        [_expense('paid', DateTime.utc(2026, 11, 1), amount)]);
    final container = _container(loader);
    addTearDown(container.dispose);
    ReportRequest request(ReportMode mode) => (
          userId: 'A',
          groupId: 'g',
          month: DateTime.utc(2026, mode == ReportMode.year ? 1 : 11),
          mode: mode,
          today: DateTime.utc(2026, 11, 11)
        );
    final monthly = groupReportProvider(request(ReportMode.month));
    final annual = groupReportProvider(request(ReportMode.year));
    final monthSubscription = container.listen(monthly, (_, __) {});
    final yearSubscription = container.listen(annual, (_, __) {});
    addTearDown(monthSubscription.close);
    addTearDown(yearSubscription.close);
    expect((await container.read(monthly.future)).totalCents, 100);
    expect((await container.read(annual.future)).totalCents, 100);
    amount = 200;
    invalidatePersonalDashboardProviders(container.invalidate);
    expect((await container.read(monthly.future)).totalCents, 200);
    expect((await container.read(annual.future)).totalCents, 200);
    expect(loader.calls.length, 4);
  });

  testWidgets('loading, complete error and retry are distinct from empty data',
      (tester) async {
    final pending = Completer<List<ReportExpense>>();
    var attempt = 0;
    final loader = _Loader((_, __, ___) {
      attempt++;
      return attempt == 1 ? pending.future : Future.value([]);
    });
    final container = _container(loader);
    addTearDown(container.dispose);
    await _mount(tester, container);
    expect(find.text('Caricamento report completo...'), findsOneWidget);
    expect(find.text('Spese lorde'), findsNothing);
    pending.completeError(StateError('second page failed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Impossibile caricare tutti i movimenti'),
        findsOneWidget);
    expect(find.text('Spese lorde'), findsNothing);
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('Nessuna spesa nel periodo'), findsOneWidget);
    expect(loader.calls.length, 2);
  });

  for (final width in [390.0, 1440.0]) {
    testWidgets(
        'real report charts and legends fit width $width and open original expense',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var currentAmount = 2490;
      final loader = _Loader((_, __, ___) async => [
            _expense('original-id', DateTime.utc(2026, 11, 9), currentAmount),
            _expense('previous', DateTime.utc(2026, 10, 9), 1500),
          ]);
      final container = _container(loader);
      addTearDown(container.dispose);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const ReportScreen()),
        GoRoute(
            path: '/expense/:id',
            builder: (context, state) => Scaffold(
                    body: Column(children: [
                  Text('Dettaglio ${state.pathParameters['id']}'),
                  FilledButton(
                      onPressed: () {
                        currentAmount = 4990;
                        // Same invalidation helper used after real expense saves.
                        invalidatePersonalDashboardProviders(
                            container.invalidate);
                        context.pop();
                      },
                      child: const Text('Salva e torna')),
                ]))),
      ]);
      addTearDown(router.dispose);
      await _mount(tester, container, router: router);
      await tester.pumpAndSettle();
      expect(find.text('Casa nostra'), findsOneWidget);
      expect(find.text('Spese lorde'), findsOneWidget);
      expect(find.text('Numero di spese'), findsOneWidget);
      expect(find.text('Importo medio'), findsOneWidget);
      expect(
          tester
              .widget<IconButton>(find.byWidgetPredicate((widget) =>
                  widget is IconButton && widget.tooltip == 'Mese successivo'))
              .onPressed,
          isNull);
      await tester.scrollUntilVisible(
          find.text('Andamento degli ultimi 6 mesi'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.byType(BarChart), findsOneWidget);
      await tester.ensureVisible(find.text('Valori mensili (6)'));
      await tester.tap(find.text('Valori mensili (6)'));
      await tester.pumpAndSettle();
      expect(find.text('nov 2026 · parziale'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Chi ha pagato'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.byType(PieChart), findsNothing);
      expect(find.text('Alimentari'), findsWidgets);
      expect(
          find.text(
              'Importi pagati e percentuali sul totale · nessun debito o conguaglio'),
          findsOneWidget);
      expect(find.text('Anna'), findsWidgets);
      await tester.scrollUntilVisible(find.text('La spesa maggiore'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('Categoria principale'), findsOneWidget);
      expect(find.textContaining('Giorno con più spese'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('La spesa maggiore'));
      await tester.pumpAndSettle();
      expect(find.text('Dettaglio original-id'), findsOneWidget);
      await tester.tap(find.text('Salva e torna'));
      await tester.pumpAndSettle();
      expect(loader.calls.length, 2);
      expect(find.textContaining('49,90'), findsWidgets);
    });
  }

  testWidgets('empty month preserves historic chart and explains previous zero',
      (tester) async {
    final loader = _Loader((_, __, ___) async =>
        [_expense('old', DateTime.utc(2026, 8, 1), 4900)]);
    final container = _container(loader);
    addTearDown(container.dispose);
    await _mount(tester, container);
    await tester.pumpAndSettle();
    expect(find.text('Nessuna spesa nel periodo'), findsOneWidget);
    expect(find.textContaining('variazione percentuale non è disponibile'),
        findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Andamento degli ultimi 6 mesi'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.byType(BarChart), findsOneWidget);
    await tester.ensureVisible(find.text('Valori mensili (6)'));
    await tester.tap(find.text('Valori mensili (6)'));
    await tester.pumpAndSettle();
    expect(find.text('ago 2026'), findsOneWidget);
    expect(find.textContaining('NaN'), findsNothing);
    expect(find.textContaining('Infinity'), findsNothing);
  });

  testWidgets(
      'unknown group, group failure and confirmed absence never fetch report',
      (tester) async {
    final loader = _Loader((_, __, ___) async => []);
    final container = _container(loader, group: const GroupState());
    addTearDown(container.dispose);
    await _mount(tester, container);
    expect(find.text('Caricamento gruppo...'), findsOneWidget);
    final groups = container.read(groupProvider.notifier) as _GroupControl;
    groups.show(const GroupState(
        status: GroupStatus.error,
        group: _group,
        errorMessage: 'Gruppo non disponibile'));
    await tester.pumpAndSettle();
    expect(find.text('Gruppo non disponibile'), findsOneWidget);
    expect(find.text('Spese lorde'), findsNothing);
    groups.show(const GroupState(status: GroupStatus.noGroup));
    await tester.pumpAndSettle();
    expect(find.text('Entra in un gruppo per vedere i suoi report.'),
        findsOneWidget);
    expect(loader.calls, isEmpty);
  });

  testWidgets(
      'inactive report does not fetch; reopening keeps month and reads fresh data',
      (tester) async {
    final loader = _Loader((_, __, ___) async => []);
    final container = _container(loader);
    addTearDown(container.dispose);
    await _mount(tester, container, screen: const ReportScreen(active: false));
    await tester.pumpAndSettle();
    expect(loader.calls, isEmpty);
    await _mount(tester, container);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mese precedente'));
    await tester.pumpAndSettle();
    expect(loader.calls.last.month, DateTime.utc(2026, 10));
    await _mount(tester, container, screen: const ReportScreen(active: false));
    await tester.pumpAndSettle();
    final previousCalls = loader.calls.length;
    await _mount(tester, container);
    await tester.pumpAndSettle();
    expect(loader.calls.length, previousCalls + 1);
    expect(loader.calls.last.month, DateTime.utc(2026, 10));
    await tester.tap(find.byTooltip('Aggiorna report'));
    await tester.pumpAndSettle();
    expect(loader.calls.length, previousCalls + 2);
  });

  testWidgets('late A group response cannot appear in B report',
      (tester) async {
    final pending = Completer<List<ReportExpense>>();
    final loader = _Loader((user, _, __) => user == 'A'
        ? pending.future
        : Future.value([
            _expense('B-row', DateTime.utc(2026, 11, 1), 100, group: 'other')
          ]));
    final container = _container(loader);
    addTearDown(container.dispose);
    await _mount(tester, container);
    container.read(_users.notifier).state = _b;
    (container.read(groupProvider.notifier) as _GroupControl).show(
        const GroupState(
            status: GroupStatus.loaded,
            group: FamilyGroupEntity(
                id: 'other', name: 'Casa B', createdBy: 'B')));
    await tester.pumpAndSettle();
    pending.complete([_expense('A-secret', DateTime.utc(2026, 11, 1), 999999)]);
    await tester.pumpAndSettle();
    expect(find.text('Casa B'), findsOneWidget);
    expect(find.text('Casa nostra'), findsNothing);
    expect(find.textContaining('9.999'), findsNothing);
    expect(loader.calls.last.user, 'B');
  });

  testWidgets('late group response cannot appear after changing only the group',
      (tester) async {
    final pending = Completer<List<ReportExpense>>();
    final loader = _Loader((_, group, __) => group == 'g'
        ? pending.future
        : Future.value([
            _expense('new-row', DateTime.utc(2026, 11, 1), 100, group: 'other')
          ]));
    final container = _container(loader);
    addTearDown(container.dispose);
    await _mount(tester, container);
    (container.read(groupProvider.notifier) as _GroupControl).show(
        const GroupState(
            status: GroupStatus.loaded,
            group: FamilyGroupEntity(
                id: 'other', name: 'Nuovo gruppo', createdBy: 'A')));
    await tester.pumpAndSettle();
    pending
        .complete([_expense('old-secret', DateTime.utc(2026, 11, 1), 999999)]);
    await tester.pumpAndSettle();
    expect(find.text('Nuovo gruppo'), findsOneWidget);
    expect(find.textContaining('9.999'), findsNothing);
    expect(loader.calls.last.user, 'A');
    expect(loader.calls.last.group, 'other');
  });

  testWidgets(
      'shell URL and selected tab agree; no report fetch until navigation',
      (tester) async {
    final loader = _Loader((_, __, ___) async => []);
    final container = _container(loader);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/main?tab=3', routes: [
      GoRoute(
          path: '/main',
          pageBuilder: (_, state) => NoTransitionPage(
              key: const ValueKey('main-shell'),
              child: MainNavigationScreen(
                  initialIndex:
                      int.tryParse(state.uri.queryParameters['tab'] ?? '0') ??
                          0))),
      GoRoute(
          path: '/report',
          pageBuilder: (_, __) => const NoTransitionPage(
              key: ValueKey('main-shell'),
              child: MainNavigationScreen(initialIndex: 2))),
    ]);
    addTearDown(router.dispose);
    await _mount(tester, container, router: router);
    await tester.pumpAndSettle();
    expect(loader.calls, isEmpty);
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3);
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Report')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/report');
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2);
    expect(loader.calls.length, 1);
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.byTooltip('Mese precedente'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Impostazioni')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.toString(), '/main?tab=3');
    final calls = loader.calls.length;
    router.go('/report');
    await tester.pumpAndSettle();
    expect(loader.calls.length, calls + 1);
    expect(loader.calls.last.month, DateTime.utc(2026, 10));
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2);
    expect(tester.takeException(), isNull);
  });
}
