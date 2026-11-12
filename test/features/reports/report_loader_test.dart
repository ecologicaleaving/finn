import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:family_expense_tracker/features/reports/data/report_loader.dart';
import 'package:family_expense_tracker/features/reports/domain/group_report.dart';

String _session(String id) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final exp =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;
  return jsonEncode({
    'access_token':
        '${encode({'alg': 'HS256'})}.${encode({'sub': id, 'exp': exp})}.test',
    'refresh_token': 'test',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': id,
      'aud': 'authenticated',
      'app_metadata': {},
      'user_metadata': {},
      'created_at': '2026-01-01T00:00:00Z'
    },
  });
}

Map<String, Object?> _row(int i) => {
      'id': 'expense-${i.toString().padLeft(4, '0')}',
      'group_id': 'g',
      'amount': '0.10',
      'date': '2026-11-01',
      'created_at': '2026-11-01T12:00:00Z',
      'created_by': 'A',
      'is_group_expense': true,
      'transaction_type': null,
      'category_name': {'name': 'Cibo'},
    };

void main() {
  final period = ReportPeriod(DateTime(2026, 11), DateTime(2026, 11, 11));
  Future<SupabaseClient> client(
      Future<http.Response> Function(http.Request) handler) async {
    final transport = MockClient((request) async {
      expect(request.method, 'GET');
      final result = await handler(request);
      return http.Response.bytes(result.bodyBytes, result.statusCode,
          headers: result.headers, request: request);
    });
    final value = SupabaseClient('https://report-test.invalid', 'anon-test',
        httpClient: transport,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    addTearDown(value.dispose);
    await value.auth.setInitialSession(_session('A'));
    return value;
  }

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'});

  test('loads every page with stable order, range and complete read-only scope',
      () async {
    final offsets = <int>[];
    final database = List.generate(405, _row);
    final supabase = await client((request) async {
      final query = request.url.queryParameters;
      expect(request.url.path, '/rest/v1/expenses');
      expect(query['group_id'], 'eq.g');
      expect(query['is_group_expense'], 'eq.true');
      expect(query['or'],
          '(transaction_type.eq.expense,transaction_type.is.null)');
      expect(request.url.queryParametersAll['date'],
          containsAll(['gte.2026-06-01', 'lte.2026-11-11']));
      expect(query['order'],
          'date.asc.nullslast,created_at.asc.nullslast,id.asc.nullslast');
      expect(query['limit'], '200');
      final offset = int.parse(query['offset']!);
      offsets.add(offset);
      return json(database.skip(offset).take(200).toList());
    });
    final rows = await SupabaseReportLoader(supabase)
        .load(userId: 'A', groupId: 'g', period: period);
    expect(offsets, [0, 200, 400, 405]);
    expect(rows.length, 405);
    expect(rows.map((row) => row.id).toSet().length, 405);
    final report =
        GroupReport.calculate(groupId: 'g', period: period, rows: rows);
    expect(report.totalCents, 4050);
  });

  test('a lower server row cap cannot truncate a report', () async {
    final database = List.generate(405, _row);
    final offsets = <int>[];
    final supabase = await client((request) async {
      final offset = int.parse(request.url.queryParameters['offset']!);
      offsets.add(offset);
      return json(database.skip(offset).take(100).toList());
    });
    final rows = await SupabaseReportLoader(supabase)
        .load(userId: 'A', groupId: 'g', period: period);
    expect(offsets, [0, 100, 200, 300, 400, 405]);
    expect(rows.length, 405);
    expect(
        GroupReport.calculate(groupId: 'g', period: period, rows: rows)
            .totalCents,
        4050);
  });

  test(
      'second-page failure rejects the entire load, never returns a partial total',
      () async {
    var requests = 0;
    final supabase = await client((request) async {
      requests++;
      if (requests == 1) return json(List.generate(200, _row));
      return json({'code': '500', 'message': 'page failed'}, 500);
    });
    await expectLater(
        SupabaseReportLoader(supabase)
            .load(userId: 'A', groupId: 'g', period: period),
        throwsA(isA<PostgrestException>()));
    expect(requests, 2);
  });

  test('a late account A response after switching to B is rejected', () async {
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final supabase = await client((request) {
      started.complete();
      return pending.future;
    });
    final result = SupabaseReportLoader(supabase)
        .load(userId: 'A', groupId: 'g', period: period);
    final assertion = expectLater(result, throwsStateError);
    await started.future;
    await supabase.auth.setInitialSession(_session('B'));
    pending.complete(json([_row(1)]));
    await assertion;
  });
}
