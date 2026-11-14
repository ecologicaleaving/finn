import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:family_expense_tracker/core/errors/failures.dart';
import 'package:family_expense_tracker/features/auth/domain/entities/user_entity.dart';
import 'package:family_expense_tracker/features/auth/domain/repositories/auth_repository.dart';
import 'package:family_expense_tracker/features/auth/presentation/providers/auth_provider.dart';
import 'package:family_expense_tracker/features/auth/presentation/screens/home_screen.dart';
import 'package:family_expense_tracker/features/auth/presentation/screens/main_navigation_screen.dart';
import 'package:family_expense_tracker/features/groups/domain/entities/family_group_entity.dart';
import 'package:family_expense_tracker/features/groups/domain/entities/invite_entity.dart';
import 'package:family_expense_tracker/features/groups/domain/entities/member_entity.dart';
import 'package:family_expense_tracker/features/groups/domain/repositories/group_repository.dart';
import 'package:family_expense_tracker/features/groups/presentation/providers/group_provider.dart';
import 'package:family_expense_tracker/features/groups/presentation/screens/no_group_screen.dart';
import 'package:family_expense_tracker/features/widget/domain/repositories/widget_repository.dart';
import 'package:family_expense_tracker/features/widget/presentation/services/widget_update_service.dart';

const _userA =
    UserEntity(id: 'A', email: 'a@example.test', displayName: 'Anna');
const _userB =
    UserEntity(id: 'B', email: 'b@example.test', displayName: 'Bruno');
const _groupA =
    FamilyGroupEntity(id: 'g-A', name: 'Famiglia A', createdBy: 'A');
const _groupB =
    FamilyGroupEntity(id: 'g-B', name: 'Famiglia B', createdBy: 'B');
typedef _GroupResult = Either<Failure, FamilyGroupEntity>;

class _Auth extends AuthRepository {
  _Auth({Future<Either<Failure, UserEntity>>? initial, this.load})
      : initial = initial ?? Future.value(const Right(_userA));
  final Future<Either<Failure, UserEntity>> initial;
  final Future<Either<Failure, UserEntity>> Function()? load;
  @override
  Future<Either<Failure, UserEntity>> getCurrentUser() =>
      load?.call() ?? initial;
  @override
  Future<Either<Failure, UserEntity>> signInWithEmail(
          {required String email, required String password}) async =>
      const Right(_userB);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Groups extends GroupRepository {
  _Groups(this.load);
  final Future<_GroupResult> Function() load;
  int calls = 0;
  @override
  Future<_GroupResult> getCurrentGroup() {
    calls++;
    return load();
  }

  @override
  Future<Either<Failure, List<MemberEntity>>> getGroupMembers(
          {required String groupId}) async =>
      const Right([]);
  @override
  Future<Either<Failure, InviteEntity>> getActiveInvite() async =>
      const Left(InviteFailure.invalidCode);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container(_Auth auth, _Groups groups) =>
    ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      groupRepositoryProvider.overrideWithValue(groups),
    ]);

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _UnusedWidgetRepository implements WidgetRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuietWidgetService extends WidgetUpdateService {
  _QuietWidgetService() : super(_UnusedWidgetRepository());
  @override
  Future<void> triggerUpdate() async {}
}

void main() {
  test(
      'mounted provider waits for the profile then loads the group automatically',
      () async {
    final profile = Completer<Either<Failure, UserEntity>>();
    final groups = _Groups(() async => const Right(_groupA));
    final container = _container(_Auth(initial: profile.future), groups);
    addTearDown(container.dispose);
    container.listen(groupProvider, (_, __) {});
    await _flush();
    expect(groups.calls, 0);
    expect(container.read(groupProvider).isLoading, isTrue);

    profile.complete(const Right(_userA));
    await container.pump();
    await _flush();
    expect(groups.calls, 1);
    expect(container.read(groupProvider).group, _groupA);
    // ExpenseRepository observes this profile, not only the group widget.
    expect(container.read(currentUserProvider)!.groupId, 'g-A');
  });

  testWidgets(
      '/main first frame waits for the profile without reading a missing user id',
      (tester) async {
    final profile = Completer<Either<Failure, UserEntity>>();
    final groups = _Groups(() async => const Right(_groupA));
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(_Auth(initial: profile.future)),
      groupRepositoryProvider.overrideWithValue(groups),
      widgetUpdateServiceProvider.overrideWithValue(_QuietWidgetService()),
    ]);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MainNavigationScreen()),
    ));
    await tester.pump();
    expect(find.text('Caricamento profilo...'), findsOneWidget);
    expect(groups.calls, 0);
    expect(tester.takeException(), isNull);
  });

  test('no-session auth failure stays unauthenticated', () async {
    final notifier = AuthNotifier(
        _Auth(initial: Future.value(const Left(AuthFailure.notAuthenticated))));
    addTearDown(notifier.dispose);
    await _flush();
    expect(notifier.state.status, AuthStatus.unauthenticated);
  });

  test('a late initial profile cannot replace a later signed-in user',
      () async {
    final profile = Completer<Either<Failure, UserEntity>>();
    final notifier = AuthNotifier(_Auth(initial: profile.future));
    addTearDown(notifier.dispose);
    await notifier.signInWithEmail(email: 'b@example.test', password: 'test');
    profile.complete(const Right(_userA));
    await _flush();
    expect(notifier.state.user!.id, 'B');
  });

  test('request errors remain retryable and do not mean no membership',
      () async {
    _GroupResult response = const Left(ServerFailure('timeout'));
    final notifier = GroupNotifier(_Groups(() async => response));
    addTearDown(notifier.dispose);
    await notifier.loadCurrentGroup();
    expect(notifier.state.status, GroupStatus.error);
    expect(notifier.state.hasGroup, isFalse);
    response = const Right(_groupA);
    await notifier.loadCurrentGroup();
    expect(notifier.state.status, GroupStatus.loaded);
    expect(notifier.state.group, _groupA);
  });

  test('refresh failure keeps the group; authoritative absence clears it',
      () async {
    _GroupResult response = const Right(_groupA);
    final notifier = GroupNotifier(_Groups(() async => response));
    addTearDown(notifier.dispose);
    await notifier.loadCurrentGroup();
    response = const Left(ServerFailure('unavailable'));
    await notifier.loadCurrentGroup();
    expect(notifier.state.status, GroupStatus.error);
    expect(notifier.state.group, _groupA);
    response = const Left(GroupFailure.noGroup);
    await notifier.loadCurrentGroup();
    expect(notifier.state.status, GroupStatus.noGroup);
    expect(notifier.state.group, isNull);
    expect(notifier.state.members, isEmpty);
  });

  test('concurrent loads share a request and a disposed result is ignored',
      () async {
    final result = Completer<_GroupResult>();
    final groups = _Groups(() => result.future);
    var callbackCalled = false;
    final notifier =
        GroupNotifier(groups, onMembershipLoaded: (_) => callbackCalled = true);
    final first = notifier.loadCurrentGroup();
    final second = notifier.loadCurrentGroup();
    expect(identical(first, second), isTrue);
    expect(groups.calls, 1);
    notifier.dispose();
    result.complete(const Right(_groupA));
    await first;
    expect(callbackCalled, isFalse);
  });

  test('late result from A cannot update B or B profile membership', () async {
    final resultA = Completer<_GroupResult>();
    final resultB = Completer<_GroupResult>();
    late ProviderContainer container;
    final groups = _Groups(() => container.read(currentUserProvider)?.id == 'A'
        ? resultA.future
        : resultB.future);
    container = _container(_Auth(), groups);
    addTearDown(container.dispose);
    container.listen(groupProvider, (_, __) {});
    await _flush();
    final notifierA = container.read(groupProvider.notifier);
    await container
        .read(authProvider.notifier)
        .signInWithEmail(email: 'b@example.test', password: 'test');
    await _flush();
    expect(container.read(groupProvider.notifier), isNot(same(notifierA)));
    resultA.complete(const Right(_groupA));
    await _flush();
    expect(container.read(groupProvider).group, isNull);
    expect(container.read(currentUserProvider)!.groupId, isNull);
    resultB.complete(const Right(_groupB));
    await _flush();
    expect(container.read(groupProvider).group, _groupB);
    expect(container.read(currentUserProvider)!.groupId, 'g-B');
  });

  Future<ProviderContainer> mount(WidgetTester tester, _Groups groups,
      {String initialLocation = '/no-group', _Auth? auth}) async {
    final container = _container(auth ?? _Auth(), groups);
    final router = GoRouter(initialLocation: initialLocation, routes: [
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/no-group', builder: (_, __) => const NoGroupScreen()),
      GoRoute(
          path: '/main',
          builder: (_, __) => const Scaffold(body: Text('Gruppo aperto'))),
      GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('Login'))),
    ]);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      container.dispose();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));
    return container;
  }

  testWidgets(
      'reloading /no-group waits, reports a read error and recovers on retry',
      (tester) async {
    final result = Completer<_GroupResult>();
    late _Groups groups;
    groups = _Groups(() =>
        groups.calls == 1 ? result.future : Future.value(const Right(_groupA)));
    final container = await mount(tester, groups);
    await tester.pump();
    expect(find.text('Caricamento gruppo...'), findsOneWidget);
    expect(find.text('Crea nuovo gruppo'), findsNothing);
    result.complete(const Left(ServerFailure('network')));
    await tester.pumpAndSettle();
    expect(
        find.text('Impossibile caricare il gruppo. Riprova.'), findsOneWidget);
    expect(find.text('Unisciti con codice'), findsNothing);
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('Gruppo aperto'), findsOneWidget);
    expect(container.read(currentUserProvider)!.groupId, 'g-A');
  });

  testWidgets(
      'profile failure on home retries successfully then loads membership',
      (tester) async {
    var attempts = 0;
    final auth = _Auth(
        load: () async => attempts++ == 0
            ? const Left(ServerFailure('profile unavailable'))
            : const Right(_userA));
    final groups = _Groups(() async => const Right(_groupA));
    final container =
        await mount(tester, groups, initialLocation: '/', auth: auth);
    await tester.pumpAndSettle();
    expect(
        find.text('Impossibile caricare il profilo. Riprova.'), findsOneWidget);
    expect(find.text('Login'), findsNothing);
    expect(groups.calls, 0);
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('Gruppo aperto'), findsOneWidget);
    expect(groups.calls, 1);
    expect(container.read(currentUserProvider)!.groupId, 'g-A');
  });

  testWidgets(
      '/main profile failure exposes a read-only retry instead of an endless spinner',
      (tester) async {
    var attempts = 0;
    final groups = _Groups(() async => const Right(_groupA));
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(_Auth(load: () async {
        attempts++;
        return const Left(ServerFailure('profile unavailable'));
      })),
      groupRepositoryProvider.overrideWithValue(groups),
      widgetUpdateServiceProvider.overrideWithValue(_QuietWidgetService()),
    ]);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MainNavigationScreen())));
    await tester.pumpAndSettle();
    expect(
        find.text('Impossibile caricare il profilo. Riprova.'), findsOneWidget);
    expect(find.text('Caricamento profilo...'), findsNothing);
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(groups.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home verifies membership when the cached profile has no group',
      (tester) async {
    final groups = _Groups(() async => const Right(_groupA));
    final container = await mount(tester, groups, initialLocation: '/');
    await tester.pumpAndSettle();
    expect(find.text('Gruppo aperto'), findsOneWidget);
    expect(find.text('Crea nuovo gruppo'), findsNothing);
    expect(container.read(currentUserProvider)!.groupId, 'g-A');
  });

  testWidgets(
      'only confirmed absence offers create/join and clears the profile group',
      (tester) async {
    final groups = _Groups(() async => const Left(GroupFailure.noGroup));
    final container = await mount(tester, groups,
        auth: _Auth(
            initial:
                Future.value(Right(_userA.copyWith(groupId: 'old-group')))));
    await tester.pumpAndSettle();
    expect(find.text('Crea nuovo gruppo'), findsOneWidget);
    expect(find.text('Unisciti con codice'), findsOneWidget);
    expect(container.read(currentUserProvider)!.groupId, isNull);
  });
}
