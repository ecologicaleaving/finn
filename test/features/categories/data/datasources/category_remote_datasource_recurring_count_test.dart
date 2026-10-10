import 'dart:convert';

import 'package:family_expense_tracker/features/categories/data/datasources/category_remote_datasource.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('getCategoryRecurringExpenseCount ignora i template eliminati', () async {
    Uri? captured;
    final client = MockClient((request) async {
      captured = request.url;
      return http.Response(
        jsonEncode(<dynamic>[]),
        200,
        request: request,
        headers: {
          'content-type': 'application/json',
          'content-range': '*/0',
        },
      );
    });
    final supabase = SupabaseClient(
      'http://localhost:54321',
      'anon-key',
      httpClient: client,
    );
    final ds = CategoryRemoteDataSourceImpl(supabaseClient: supabase);

    final count = await ds.getCategoryRecurringExpenseCount(categoryId: 'cat-1');

    expect(count, 0);
    expect(captured, isNotNull);
    expect(captured!.path, endsWith('/recurring_expenses'));
    expect(captured!.queryParameters['category_id'], 'eq.cat-1');
    expect(captured!.queryParameters['deleted_at'], 'is.null');
  });
}
