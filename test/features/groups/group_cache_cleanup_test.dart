import 'package:family_expense_tracker/features/groups/data/datasources/group_remote_datasource.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Issue #64 AC1: the group cache in secure storage is removed at logout, only
// for the group keys (never deleteAll) and B's keys survive.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = <String, String>{};

  setUp(() {
    store
      ..clear()
      ..addAll({
        'cached_group_id': 'g-legacy',
        'cached_group_data': '{}',
        'cached_group_id_A': 'gA',
        'cached_group_data_A': '{}',
        'cached_group_id_B': 'gB',
        'cached_group_data_B': '{}',
        'access_token': 'keep-me',
      });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = (call.arguments as Map).cast<String, dynamic>();
        switch (call.method) {
          case 'write':
            store[args['key'] as String] = args['value'] as String;
            return null;
          case 'read':
            return store[args['key']];
          case 'delete':
            store.remove(args['key']);
            return null;
          case 'deleteAll':
            store.clear();
            return null;
          case 'containsKey':
            return store.containsKey(args['key']);
          case 'readAll':
            return Map<String, String>.from(store);
        }
        return null;
      },
    );
  });

  test('clearCachedGroup removes A and legacy keys, keeps B and foreign keys',
      () async {
    final ds = GroupRemoteDataSourceImpl(
      supabaseClient: SupabaseClient('http://localhost', 'anon'),
      secureStorage: const FlutterSecureStorage(),
    );

    await ds.clearCachedGroup(userId: 'A');

    expect(store.keys.toSet(), {
      'cached_group_id_B',
      'cached_group_data_B',
      'access_token',
    });
  });

  test('clearCachedGroup without user id removes only legacy keys', () async {
    final ds = GroupRemoteDataSourceImpl(
      supabaseClient: SupabaseClient('http://localhost', 'anon'),
      secureStorage: const FlutterSecureStorage(),
    );

    await ds.clearCachedGroup();

    expect(store.containsKey('cached_group_id'), isFalse);
    expect(store.containsKey('cached_group_data'), isFalse);
    expect(store.containsKey('cached_group_id_A'), isTrue);
    expect(store.containsKey('access_token'), isTrue);
  });
}
