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
import 'package:family_expense_tracker/features/groups/domain/repositories/group_repository.dart';
import 'package:family_expense_tracker/features/groups/presentation/providers/group_provider.dart';
import 'package:family_expense_tracker/features/reports/data/report_loader.dart';
import 'package:family_expense_tracker/features/reports/domain/group_report.dart';
import 'package:family_expense_tracker/features/reports/presentation/report_provider.dart';
import 'package:family_expense_tracker/features/reports/presentation/report_screen.dart';
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
  final calls = <({String user, String group, DateTime month})>[];
  @override
  Future<List<ReportExpense>> load(
      {required String userId,
      required String groupId,
      required ReportPeriod period}) {
    calls.add((user: userId, group: groupId, month: period.month));
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

ProviderContainer _container(_Loader loader,
        {GroupState group =
            const GroupState(status: GroupStatus.loaded, group: _group)}) =>
    ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) => ref.watch(_users)),
      groupProvider.overrideWith((ref) => _GroupControl(group)),
      reportLoaderProvider.overrideWithValue(loader),
      reportClockProvider.overrideWithValue(() => DateTime(2026, 11, 11)),
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

void main() {
  setUpAll(() => initializeDateFormatting('it_IT'));

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
    expect(find.text('Spesa totale'), findsNothing);
    pending.completeError(StateError('second page failed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Impossibile caricare tutte le spese'),
        findsOneWidget);
    expect(find.text('Spesa totale'), findsNothing);
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
      expect(find.text('Spesa totale'), findsOneWidget);
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
      expect(find.text('nov 2026 · parziale'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Chi ha pagato'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.byType(PieChart), findsOneWidget);
      expect(find.text('Quote pagate, non debiti o conguagli'), findsOneWidget);
      expect(find.text('Anna'), findsOneWidget);
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
    expect(find.text('Spesa totale'), findsNothing);
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
