import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:finn/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:finn/features/auth/data/models/user_model.dart';
import 'package:finn/core/errors/exceptions.dart';

@GenerateMocks([SupabaseClient, GoTrueClient])
import 'auth_remote_datasource_test.mocks.dart';

/// Fake Hive Box for testing
class FakeHiveBox extends Fake implements Box<String> {
  final Map<String, String> _data = {};

  @override
  String? get(key, {String? defaultValue}) => _data[key as String] ?? defaultValue;

  @override
  Future<void> put(key, String value) async {
    _data[key as String] = value;
  }

  @override
  Future<void> delete(key) async {
    _data.remove(key as String);
  }
}

void main() {
  group('AuthRemoteDataSourceImpl', () {
    late MockSupabaseClient mockSupabaseClient;
    late MockGoTrueClient mockGoTrueClient;

    setUp(() {
      mockSupabaseClient = MockSupabaseClient();
      mockGoTrueClient = MockGoTrueClient();
      when(mockSupabaseClient.auth).thenReturn(mockGoTrueClient);
    });

    group('isAuthenticated', () {
      test('returns true when currentUser is not null', () {
        when(mockGoTrueClient.currentUser).thenReturn(
          User(
            id: 'user-1',
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: DateTime.now().toIso8601String(),
          ),
        );
        final ds = AuthRemoteDataSourceImpl(supabaseClient: mockSupabaseClient);
        expect(ds.isAuthenticated, isTrue);
      });

      test('returns false when currentUser is null', () {
        when(mockGoTrueClient.currentUser).thenReturn(null);
        final ds = AuthRemoteDataSourceImpl(supabaseClient: mockSupabaseClient);
        expect(ds.isAuthenticated, isFalse);
      });
    });

    group('getCurrentUser', () {
      test('throws AppAuthException when no authenticated user', () async {
        when(mockGoTrueClient.currentUser).thenReturn(null);
        final ds = AuthRemoteDataSourceImpl(supabaseClient: mockSupabaseClient);

        expect(
          () => ds.getCurrentUser(),
          throwsA(isA<AppAuthException>()),
        );
      });
    });
  });
}
