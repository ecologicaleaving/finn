import 'package:drift/native.dart';
import 'package:family_expense_tracker/features/budgets/data/datasources/budget_local_datasource.dart';
import 'package:family_expense_tracker/features/budgets/data/datasources/budget_remote_datasource.dart';
import 'package:family_expense_tracker/features/budgets/data/models/income_source_model.dart';
import 'package:family_expense_tracker/features/budgets/data/repositories/budget_repository_impl.dart';
import 'package:family_expense_tracker/features/offline/data/local/offline_database.dart';
import 'package:flutter_test/flutter_test.dart';

// Issue #65 / AC5: an income source deleted on another device must disappear
// from the local cache once the server list is fetched.

class _FakeBudgetRemote implements BudgetRemoteDataSource {
  List<IncomeSourceModel> sources = [];
  Object? error;

  @override
  Future<List<IncomeSourceModel>> fetchIncomeSources(String userId) async {
    if (error != null) throw error!;
    return sources.where((s) => s.userId == userId).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

IncomeSourceModel _src(String id, String userId, int amount) => IncomeSourceModel(
      id: id,
      userId: userId,
      type: 'salary',
      amount: amount,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

void main() {
  late OfflineDatabase db;
  late BudgetLocalDataSourceImpl local;
  late _FakeBudgetRemote remote;
  late BudgetRepositoryImpl repo;

  setUp(() {
    db = OfflineDatabase.forTesting(NativeDatabase.memory());
    local = BudgetLocalDataSourceImpl(db);
    remote = _FakeBudgetRemote();
    repo = BudgetRepositoryImpl(remoteDataSource: remote, localDataSource: local);
  });

  tearDown(() async => db.close());

  Future<List<String>> localIds(String userId) async =>
      (await local.getLocalIncomeSources(userId)).map((m) => m.id).toList()..sort();

  test('foreground (empty cache): fetched list is cached', () async {
    remote.sources = [_src('a', 'u1', 100), _src('b', 'u1', 200)];

    final result = await repo.getIncomeSources('u1');

    expect(result.getOrElse(() => []).length, 2);
    expect(await localIds('u1'), ['a', 'b']);
  });

  test('background sync: a source deleted on the server leaves the cache', () async {
    await local.upsertLocalIncomeSources([_src('a', 'u1', 100), _src('gone', 'u1', 50)]);
    remote.sources = [_src('a', 'u1', 150)];

    final first = await repo.getIncomeSources('u1');
    // Local data is returned immediately (stale), the sync runs in background.
    expect(first.getOrElse(() => []).length, 2);
    await repo.lastIncomeSourcesSync;

    expect(await localIds('u1'), ['a']);
    final second = await repo.getIncomeSources('u1');
    expect(second.getOrElse(() => []).map((e) => e.id), ['a']);
    expect((await local.getLocalIncomeSource('a'))!.amount, 150);
  });

  test('an empty server list empties the cache of the user', () async {
    await local.upsertLocalIncomeSources([_src('a', 'u1', 100)]);
    remote.sources = [];

    await repo.getIncomeSources('u1');
    await repo.lastIncomeSourcesSync;

    expect(await localIds('u1'), isEmpty);
  });

  test('sources of another user are untouched', () async {
    await local.upsertLocalIncomeSources([
      _src('a', 'u1', 100),
      _src('other', 'u2', 300),
    ]);
    remote.sources = [];

    await repo.getIncomeSources('u1');
    await repo.lastIncomeSourcesSync;

    expect(await localIds('u1'), isEmpty);
    expect(await localIds('u2'), ['other']);
  });

  test('a remote error leaves the cache intact', () async {
    await local.upsertLocalIncomeSources([_src('a', 'u1', 100), _src('b', 'u1', 200)]);
    remote.error = Exception('SocketException');

    final result = await repo.getIncomeSources('u1');
    await repo.lastIncomeSourcesSync;

    expect(result.isRight(), isTrue);
    expect(await localIds('u1'), ['a', 'b']);
  });

  test('foreground remote error on an empty cache returns a failure', () async {
    remote.error = Exception('offline');

    final result = await repo.getIncomeSources('u1');

    expect(result.isLeft(), isTrue);
    expect(await localIds('u1'), isEmpty);
  });
}
