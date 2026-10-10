import 'package:family_expense_tracker/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:family_expense_tracker/features/expenses/domain/entities/expense_entity.dart';
import 'package:family_expense_tracker/features/expenses/domain/utils/expense_ordering.dart';
import 'package:family_expense_tracker/shared/services/connectivity_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'expense_test_support.dart';

// Issue #65 / AC1, AC2: pagination must show every expense exactly once, in a
// deterministic order, even with pending local expenses and equal dates.

void main() {
  const pageSize = 20;

  late List<ExpenseEntity> synced;
  late List<ExpenseEntity> pending;
  late FakeServer server;
  late FakeCache cache;

  setUp(() {
    // 45 synced expenses; groups of 3 share the same date and createdAt.
    synced = [
      for (var i = 0; i < 45; i++)
        makeExpense(
          'e${i.toString().padLeft(2, '0')}',
          date: DateTime(2026, 8, 1).add(Duration(days: i ~/ 3)),
          createdAt: DateTime(2026, 8, 1).add(Duration(days: i ~/ 3)),
          isGroupExpense: i % 5 != 0,
        ),
    ];
    pending = [
      makeExpense('p-group', date: DateTime(2026, 8, 10), isGroupExpense: true, syncStatus: 'pending'),
      makeExpense('p-personal', date: DateTime(2026, 8, 12), isGroupExpense: false, syncStatus: 'failed'),
      makeExpense('p-old', date: DateTime(2026, 1, 1), isGroupExpense: true, syncStatus: 'syncing'),
    ];
    server = FakeServer(synced);
    cache = FakeCache(pending);
  });

  ExpenseRepositoryImpl repo(NetworkStatus status) => ExpenseRepositoryImpl(
        remoteDataSource: server,
        localCacheDataSource: cache,
        offlineLocalDataSource: FakeOffline(),
        currentUser: testUser,
        networkStatusGetter: () => status,
      );

  /// Pages like ExpenseListNotifier: the offset counts only synced items.
  Future<List<List<ExpenseEntity>>> browse(
    ExpenseRepositoryImpl r, {
    bool? isGroupExpense,
  }) async {
    final pages = <List<ExpenseEntity>>[];
    var loaded = <ExpenseEntity>[];
    for (var guard = 0; guard < 20; guard++) {
      final result = await r.getExpenses(
        isGroupExpense: isGroupExpense,
        limit: pageSize,
        offset: loaded.where((e) => !e.isPendingSync).length,
      );
      final page = result.getOrElse(() => []);
      pages.add(page);
      loaded = [...loaded, ...page];
      if (page.where((e) => !e.isPendingSync).length < pageSize) break;
    }
    return pages;
  }

  void expectCompleteAndOrdered(
    List<List<ExpenseEntity>> pages,
    Set<String> expectedIds,
  ) {
    final all = pages.expand((p) => p).toList();
    final ids = all.map((e) => e.id).toList();
    expect(ids.length, ids.toSet().length, reason: 'no duplicates');
    expect(ids.toSet(), expectedIds, reason: 'no gaps');
    // Synced items keep the total order across pages.
    final syncedOnly = all.where((e) => !e.isPendingSync).toList();
    final sorted = [...syncedOnly]..sort(compareExpensesNewestFirst);
    expect(syncedOnly.map((e) => e.id), sorted.map((e) => e.id));
  }

  test('online: pending appear exactly once, remote pages have no gaps or duplicates', () async {
    final pages = await browse(repo(NetworkStatus.online));
    expect(pages.length, 3);

    final expected = {...synced.map((e) => e.id), ...pending.map((e) => e.id)};
    expectCompleteAndOrdered(pages, expected);

    // Pending only in the first page.
    expect(pages[0].where((e) => e.isPendingSync).length, 3);
    expect(pages[1].where((e) => e.isPendingSync), isEmpty);
    expect(pages[2].where((e) => e.isPendingSync), isEmpty);
  });

  test('online: a personal pending expense does not leak into the group tab', () async {
    final pages = await browse(repo(NetworkStatus.online), isGroupExpense: true);
    final ids = pages.expand((p) => p).map((e) => e.id).toSet();
    expect(ids.contains('p-personal'), isFalse);
    expect(ids.contains('p-group'), isTrue);
    expect(ids.contains('p-old'), isTrue);
    final groupSynced =
        synced.where((e) => e.isGroupExpense).map((e) => e.id).toSet();
    expect(ids, {...groupSynced, 'p-group', 'p-old'});
  });

  test('online: a group pending expense does not leak into the personal tab', () async {
    final pages = await browse(repo(NetworkStatus.online), isGroupExpense: false);
    final ids = pages.expand((p) => p).map((e) => e.id).toSet();
    final personalSynced =
        synced.where((e) => !e.isGroupExpense).map((e) => e.id).toSet();
    expect(ids, {...personalSynced, 'p-personal'});
  });

  test('offline: same contract served from the cache', () async {
    cache = FakeCache([...pending, ...synced]);
    final pages = await browse(repo(NetworkStatus.offline));
    final expected = {...synced.map((e) => e.id), ...pending.map((e) => e.id)};
    expectCompleteAndOrdered(pages, expected);
    expect(pages[0].where((e) => e.isPendingSync).length, 3);
    expect(pages.skip(1).expand((p) => p).where((e) => e.isPendingSync), isEmpty);
  });

  test('offline with filter: pending of the other tab excluded', () async {
    cache = FakeCache([...pending, ...synced]);
    final pages = await browse(repo(NetworkStatus.offline), isGroupExpense: true);
    final ids = pages.expand((p) => p).map((e) => e.id).toSet();
    final groupSynced =
        synced.where((e) => e.isGroupExpense).map((e) => e.id).toSet();
    expect(ids, {...groupSynced, 'p-group', 'p-old'});
  });

  test('network failure falls back to the cache with the same contract', () async {
    cache = FakeCache([...pending, ...synced]);
    server.error = Exception('SocketException: Failed host lookup');
    final pages = await browse(repo(NetworkStatus.online));
    final expected = {...synced.map((e) => e.id), ...pending.map((e) => e.id)};
    expectCompleteAndOrdered(pages, expected);
  });

  test('same date and createdAt: the id keeps the order stable across pages', () async {
    final all = [
      for (var i = 0; i < 30; i++)
        makeExpense('x${i.toString().padLeft(2, '0')}'),
    ];
    server = FakeServer(all);
    cache = FakeCache();
    final pages = await browse(repo(NetworkStatus.online));
    final ids = pages.expand((p) => p).map((e) => e.id).toList();
    expect(ids.length, 30);
    expect(ids.toSet().length, 30);
  });
}
