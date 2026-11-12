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
      Future<http.Response> Function(http.Request) handler,
      {bool includeReimbursements = false}) async {
    final transport = MockClient((request) async {
      expect(request.method, 'GET');
      final result = !includeReimbursements &&
              request.url.queryParameters.containsKey('reimbursement_status')
          ? http.Response('[]', 200,
              headers: {'content-type': 'application/json'})
          : await handler(request);
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
          '(transaction_type.eq.expense,transaction_type.is.null,transaction_type.eq.income)');
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

  for (final year in [2024, 2026]) {
    test('annual loader reads complete comparison window for $year', () async {
      final annual = ReportPeriod(DateTime(year), DateTime(2026, 11, 12),
          mode: ReportMode.year);
      final supabase = await client((request) async {
        expect(
            request.url.queryParametersAll['date'],
            containsAll([
              'gte.${year - 1}-01-01',
              'lte.$year-${year == 2026 ? '11-12' : '12-31'}',
            ]));
        expect(request.url.queryParameters['group_id'], 'eq.g');
        expect(request.url.queryParameters['is_group_expense'], 'eq.true');
        return json([]);
      });
      final rows = await SupabaseReportLoader(supabase)
          .load(userId: 'A', groupId: 'g', period: annual);
      expect(rows, isEmpty);
    });
  }

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

  test(
      'refund query is independently paged by local timestamp, deduplicated and scoped',
      () async {
    final refundedAt = DateTime(2026, 11, 5, 10).toUtc().toIso8601String();
    final refunds = List.generate(
        205,
        (i) => {
              ..._row(i),
              'date': i == 0 ? '2026-11-01' : '2020-01-01',
              'reimbursement_status': 'reimbursed',
              'reimbursed_at': refundedAt
            });
    final refundOffsets = <int>[];
    final supabase = await client((request) async {
      final query = request.url.queryParameters;
      expect(request.url.path, '/rest/v1/expenses');
      expect(query['group_id'], 'eq.g');
      expect(query['is_group_expense'], 'eq.true');
      final offset = int.parse(query['offset']!);
      if (!query.containsKey('reimbursement_status')) {
        if (offset > 0) return json([]);
        return json([
          refunds.first,
          {
            ..._row(999),
            'id': 'income',
            'amount': '10.00',
            'transaction_type': 'income'
          }
        ]);
      }
      expect(query['reimbursement_status'], 'eq.reimbursed');
      expect(query['or'],
          '(transaction_type.eq.expense,transaction_type.is.null)');
      expect(query.containsKey('date'), isFalse);
      expect(query['order'],
          'reimbursed_at.asc.nullslast,created_at.asc.nullslast,id.asc.nullslast');
      expect(
          request.url.queryParametersAll['reimbursed_at'],
          containsAll([
            'gte.${period.localHistoryStartUtc.toIso8601String()}',
            'lt.${period.localEndExclusiveUtc.toIso8601String()}',
          ]));
      refundOffsets.add(offset);
      return json(refunds.skip(offset).take(100).toList());
    }, includeReimbursements: true);
    final rows = await SupabaseReportLoader(supabase)
        .load(userId: 'A', groupId: 'g', period: period);
    expect(refundOffsets, [0, 100, 200, 205]);
    expect(rows.length, 206);
    final report =
        GroupReport.calculate(groupId: 'g', period: period, rows: rows);
    expect(report.totalCents, 10);
    expect(report.incomeCents, 1000);
    expect(report.receivedReimbursementCents, 2050);
    expect(report.balanceCents, 3040);
  });

  test(
      'failure on a later refund page rejects previously loaded income as well',
      () async {
    var refundPages = 0;
    final supabase = await client((request) async {
      if (!request.url.queryParameters.containsKey('reimbursement_status')) {
        return json(request.url.queryParameters['offset'] == '0'
            ? [
                {..._row(999), 'transaction_type': 'income'}
              ]
            : []);
      }
      refundPages++;
      if (refundPages == 1) return json(List.generate(200, _row));
      return json({'code': '500', 'message': 'refund page failed'}, 500);
    }, includeReimbursements: true);
    await expectLater(
        SupabaseReportLoader(supabase)
            .load(userId: 'A', groupId: 'g', period: period),
        throwsA(isA<PostgrestException>()));
    expect(refundPages, 2);
  });

  test(
      'changing account while refund query is pending rejects the complete result',
      () async {
    final pending = Completer<http.Response>();
    final refundStarted = Completer<void>();
    final supabase = await client((request) async {
      if (!request.url.queryParameters.containsKey('reimbursement_status'))
        return json([]);
      refundStarted.complete();
      return pending.future;
    }, includeReimbursements: true);
    final result = SupabaseReportLoader(supabase)
        .load(userId: 'A', groupId: 'g', period: period);
    final assertion = expectLater(result, throwsStateError);
    await refundStarted.future;
    await supabase.auth.setInitialSession(_session('B'));
    pending.complete(json([_row(1)]));
    await assertion;
  });
}
