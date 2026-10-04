import 'package:drift/native.dart';
import 'package:family_expense_tracker/app/session_cleanup.dart';
import 'package:family_expense_tracker/features/auth/presentation/providers/auth_provider.dart';
import 'package:family_expense_tracker/features/auth/domain/entities/user_entity.dart';
import 'package:family_expense_tracker/features/groups/data/datasources/group_remote_datasource.dart';
import 'package:family_expense_tracker/features/offline/data/datasources/offline_expense_local_datasource.dart';
import 'package:family_expense_tracker/features/offline/data/local/offline_database.dart';
import 'package:family_expense_tracker/features/widget/data/datasources/widget_local_datasource.dart';
import 'package:flutter_test/flutter_test.dart';

// Issue #64 AC1 + AC2: the session cleanup removes group/widget data but
// never touches the unsynced expenses (Drift pending + sync queue).

class _FakeGroupDs implements GroupRemoteDataSource {
  final List<String?> cleared = [];
  bool throwOnClear = false;

  @override
  Future<void> clearCachedGroup({String? userId}) async {
    cleared.add(userId);
    if (throwOnClear) throw Exception('boom');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWidgetDs implements WidgetLocalDataSource {
  int clearCalls = 0;

  @override
  Future<void> clearWidgetData() async => clearCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late OfflineDatabase db;
  late OfflineExpenseLocalDataSourceImpl offline;

  setUp(() {
    db = OfflineDatabase.forTesting(NativeDatabase.memory());
    offline = OfflineExpenseLocalDataSourceImpl(database: db);
  });

  tearDown(() async => db.close());

  test('clearUserScopedData keeps pending expenses and the sync queue', () async {
    await offline.createOfflineExpense(
      userId: 'A',
      amount: 10,
      date: DateTime(2026, 10, 1),
      categoryId: 'cat-1',
    );
    final pendingBefore = await offline.getPendingExpenses('A');
    final countBefore = await offline.getPendingSyncCount('A');
    expect(pendingBefore, hasLength(1));
    expect(countBefore, greaterThan(0));

    final groupDs = _FakeGroupDs();
    final widgetDs = _FakeWidgetDs();
    await SessionCleanup(groupDs: groupDs, widgetDs: widgetDs)
        .clearUserScopedData('A');

    expect(groupDs.cleared, ['A']);
    expect(widgetDs.clearCalls, 1);
    final pendingAfter = await offline.getPendingExpenses('A');
    expect(pendingAfter.map((e) => e.id), pendingBefore.map((e) => e.id));
    expect(await offline.getPendingSyncCount('A'), countBefore);
    // B does not see A's pending expenses
    expect(await offline.getPendingExpenses('B'), isEmpty);
  });

  test('a failing group cleanup does not stop the widget cleanup', () async {
    final groupDs = _FakeGroupDs()..throwOnClear = true;
    final widgetDs = _FakeWidgetDs();
    await SessionCleanup(groupDs: groupDs, widgetDs: widgetDs)
        .clearUserScopedData('A');
    expect(widgetDs.clearCalls, 1);
  });

  test('SyncTrigger select yields null -> A on logout then login of same user',
      () {
    const a = UserEntity(id: 'A', email: 'a@x.it');
    final sequence = <AuthState>[
      const AuthState(status: AuthStatus.authenticated, user: a),
      // logout keeps the user in state (copyWith is sticky)
      const AuthState(status: AuthStatus.unauthenticated, user: a),
      const AuthState(status: AuthStatus.loading, user: a),
      const AuthState(status: AuthStatus.authenticated, user: a),
    ];
    expect(sequence.map(authenticatedUserId).toList(), ['A', null, null, 'A']);
  });
}
