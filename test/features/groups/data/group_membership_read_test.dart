import 'dart:async';
import 'dart:convert';

import 'package:family_expense_tracker/core/errors/exceptions.dart';
import 'package:family_expense_tracker/features/groups/data/datasources/group_remote_datasource.dart';
import 'package:family_expense_tracker/features/groups/data/models/family_group_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _groupA = FamilyGroupModel(id: 'g-A', name: 'Famiglia A', createdBy: 'A');
const _groupB = FamilyGroupModel(id: 'g-B', name: 'Famiglia B', createdBy: 'B');
http.Response _json(Object body,
        [int status = 200, Map<String, String>? extra]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json', ...?extra});

String _session(String userId) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final exp =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;
  return jsonEncode({
    'access_token': '${encode({'alg': 'HS256'})}.${encode({
          'sub': userId,
          'exp': exp
        })}.test',
    'refresh_token': 'test-refresh',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': userId,
      'aud': 'authenticated',
      'app_metadata': {},
      'user_metadata': {},
      'created_at': '2026-01-01T00:00:00Z'
    },
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};
  setUp(() {
    store.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = (call.arguments as Map).cast<String, dynamic>();
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read':
            return store[key];
          case 'write':
            store[key!] = args['value'] as String;
            return null;
          case 'delete':
            store.remove(key);
            return null;
          case 'containsKey':
            return store.containsKey(key);
          case 'readAll':
            return Map<String, String>.from(store);
          default:
            throw StateError('Unexpected storage operation ${call.method}');
        }
      },
    );
  });

  Future<(SupabaseClient, GroupRemoteDataSourceImpl)> source(
      Future<http.Response> Function(http.Request) handle,
      {String userId = 'A'}) async {
    final transport = MockClient((request) async {
      expect(
          request.method, 'GET'); // These tests must never change membership.
      final response = await handle(request);
      // Postgrest inspects response.request.method when decoding single/count.
      return http.Response.bytes(response.bodyBytes, response.statusCode,
          headers: response.headers, request: request);
    });
    final client = SupabaseClient('https://finn-test.invalid', 'test-anon',
        httpClient: transport,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    addTearDown(client.dispose);
    await client.auth.setInitialSession(_session(userId));
    return (client, GroupRemoteDataSourceImpl(supabaseClient: client));
  }

  void cache(String userId, FamilyGroupModel group) {
    store['cached_group_id_$userId'] = group.id;
    store['cached_group_data_$userId'] = group.toJsonString();
  }

  test('explicit null membership clears only that user group cache', () async {
    cache('A', _groupA);
    cache('B', _groupB);
    store['cached_group_data'] = _groupA.toJsonString();
    store['access_token'] = 'keep';
    final (_, ds) = await source((_) async => _json({'group_id': null}));
    expect(await ds.getCurrentGroup(), isNull);
    expect(store.containsKey('cached_group_id_A'), isFalse);
    expect(store.containsKey('cached_group_data_A'), isFalse);
    expect(store['cached_group_data_B'], _groupB.toJsonString());
    expect(store['access_token'], 'keep');
  });

  for (final failure in [
    (code: 'PGRST116', status: 406),
    (code: 'PGRST301', status: 401)
  ]) {
    test('family group ${failure.code} remains an error even with cached data',
        () async {
      cache('A', _groupA);
      final (_, ds) = await source((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return _json({'group_id': 'g-A'});
        }
        return _json({
          'code': failure.code,
          'message': 'Group unavailable',
          'details': null,
          'hint': null
        }, failure.status);
      });
      await expectLater(
          ds.getCurrentGroup(),
          throwsA(isA<ServerException>()
              .having((e) => e.code, 'code', failure.code)));
    });
  }

  test('an inaccessible profile row is an error even when the user has a cache',
      () async {
    cache('A', _groupA);
    final (_, ds) = await source((_) async => _json({
          'code': 'PGRST116',
          'message': 'Profile unavailable',
          'details': null,
          'hint': null
        }, 406));
    await expectLater(
        ds.getCurrentGroup(),
        throwsA(
            isA<ServerException>().having((e) => e.code, 'code', 'PGRST116')));
    expect(store['cached_group_data_A'], _groupA.toJsonString());
  });

  test('a genuine transport outage can use the same user cached group',
      () async {
    cache('A', _groupA);
    final (_, ds) =
        await source((_) async => throw http.ClientException('offline'));
    expect((await ds.getCurrentGroup())!.id, 'g-A');
  });

  test('neither another user cache nor unowned legacy data is a fallback',
      () async {
    cache('A', _groupA);
    store['cached_group_data'] = _groupA.toJsonString();
    final (_, ds) = await source(
        (_) async => throw http.ClientException('offline'),
        userId: 'B');
    await expectLater(ds.getCurrentGroup(), throwsA(isA<ServerException>()));
    expect(store['cached_group_data_A'], _groupA.toJsonString());
  });

  test(
      'known new membership prevents old group cache on this and later retries',
      () async {
    cache('A', _groupA);
    var profileAvailable = true;
    final (_, ds) = await source((request) async {
      if (profileAvailable && request.url.path.endsWith('/profiles')) {
        return _json({'group_id': 'g-new'});
      }
      throw http.ClientException('offline');
    });
    await expectLater(ds.getCurrentGroup(), throwsA(isA<ServerException>()));
    profileAvailable = false;
    await expectLater(ds.getCurrentGroup(), throwsA(isA<ServerException>()));
    expect(store['cached_group_id_A'], 'g-new');
  });

  test(
      'late profile response from A cannot write B cache after session changes',
      () async {
    final profile = Completer<http.Response>();
    cache('B', _groupB);
    final (client, ds) = await source((_) => profile.future);
    final load = ds.getCurrentGroup();
    await client.auth.setInitialSession(_session('B'));
    profile.complete(_json({'group_id': 'g-A'}));
    await expectLater(load, throwsA(isA<AppAuthException>()));
    expect(store['cached_group_data_B'], _groupB.toJsonString());
    expect(store['cached_group_id_B'], 'g-B');
    expect(store.containsKey('cached_group_data_A'), isFalse);
  });

  test('a failed optional member count does not hide a loaded group', () async {
    final (_, ds) = await source((request) async {
      if (request.url.path.endsWith('/family_groups')) {
        return _json(_groupA.toJson());
      }
      if (request.url.queryParameters.containsKey('id')) {
        return _json({'group_id': 'g-A'});
      }
      throw TimeoutException('count unavailable');
    });
    expect((await ds.getCurrentGroup())!.id, 'g-A');
  });
}
