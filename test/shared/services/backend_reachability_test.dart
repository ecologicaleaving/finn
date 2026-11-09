import 'dart:async';

import 'package:family_expense_tracker/shared/services/backend_reachability.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('first visit before login probes public settings without a user token',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://finn.test/auth/v1/settings');
      expect(request.headers['apikey'], 'public-client-key');
      expect(request.headers.containsKey('authorization'), isFalse);
      return http.Response('{"external":{"email":true}}', 200);
    });
    addTearDown(client.close);
    expect(
      await checkBackendReachability(
        supabaseUrl: 'https://finn.test/',
        anonKey: 'public-client-key',
        client: client,
      ),
      isTrue,
    );
  });

  test('an unavailable backend remains offline', () async {
    final client = MockClient((_) async => http.Response('unavailable', 503));
    addTearDown(client.close);
    expect(
      await checkBackendReachability(
        supabaseUrl: 'https://finn.test',
        anonKey: 'public-client-key',
        client: client,
      ),
      isFalse,
    );
  });

  test('network failure remains offline', () async {
    final client =
        MockClient((_) async => throw http.ClientException('offline'));
    addTearDown(client.close);
    expect(
      await checkBackendReachability(
        supabaseUrl: 'https://finn.test',
        anonKey: 'public-client-key',
        client: client,
      ),
      isFalse,
    );
  });

  test('a stalled request times out instead of blocking startup', () async {
    final pending = Completer<http.Response>();
    final client = MockClient((_) => pending.future);
    addTearDown(client.close);
    expect(
      await checkBackendReachability(
        supabaseUrl: 'https://finn.test',
        anonKey: 'public-client-key',
        client: client,
        timeout: const Duration(milliseconds: 5),
      ),
      isFalse,
    );
    pending.complete(http.Response('{}', 200));
  });
}
