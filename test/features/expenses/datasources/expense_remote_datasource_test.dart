import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:finn/features/expenses/data/datasources/expense_remote_datasource.dart';
import 'package:finn/features/offline/data/datasources/offline_expense_local_datasource.dart';
import 'package:finn/features/offline/domain/entities/offline_expense_entity.dart';
import 'package:finn/core/errors/exceptions.dart';

@GenerateMocks([SupabaseClient, GoTrueClient, OfflineExpenseLocalDataSource])
import 'expense_remote_datasource_test.mocks.dart';

void main() {
  group('ExpenseRemoteDataSourceImpl', () {
    late MockSupabaseClient mockSupabaseClient;
    late MockGoTrueClient mockGoTrueClient;
    late MockOfflineExpenseLocalDataSource mockOfflineDataSource;

    setUp(() {
      mockSupabaseClient = MockSupabaseClient();
      mockGoTrueClient = MockGoTrueClient();
      mockOfflineDataSource = MockOfflineExpenseLocalDataSource();
      when(mockSupabaseClient.auth).thenReturn(mockGoTrueClient);
    });

    group('_currentUserId', () {
      test('throws AppAuthException when no user authenticated', () async {
        when(mockGoTrueClient.currentUser).thenReturn(null);
        final ds = ExpenseRemoteDataSourceImpl(
          supabaseClient: mockSupabaseClient,
          offlineLocalDataSource: mockOfflineDataSource,
        );

        // Trying to get expenses with no user should throw auth exception
        expect(
          () => ds.getExpenses(),
          throwsA(isA<AppAuthException>()),
        );
      });
    });

    group('getExpenses fallback', () {
      test('returns offline expenses when network fails and offline cache available', () async {
        final mockUser = User(
          id: 'user-1',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: DateTime.now().toIso8601String(),
        );

        when(mockGoTrueClient.currentUser).thenReturn(mockUser);

        final now = DateTime.now();
        final offlineExpenses = [
          OfflineExpenseEntity(
            id: 'offline-1',
            userId: 'user-1',
            amount: 42.0,
            date: now,
            categoryId: 'cat-1',
            merchant: null,
            notes: null,
            isGroupExpense: true,
            syncStatus: 'pending',
            retryCount: 0,
            lastSyncAttemptAt: null,
            syncErrorMessage: null,
            hasConflict: false,
            serverVersionData: null,
            localCreatedAt: now,
            localUpdatedAt: now,
            localReceiptPath: null,
            receiptImageSize: null,
          ),
        ];

        when(mockOfflineDataSource.getAllOfflineExpenses('user-1'))
            .thenAnswer((_) async => offlineExpenses);

        // The datasource will fail on Supabase queries (because we haven't mocked them)
        // and should fall back to offline
        final ds = ExpenseRemoteDataSourceImpl(
          supabaseClient: mockSupabaseClient,
          offlineLocalDataSource: mockOfflineDataSource,
        );

        // getExpenses will fail at _currentUserGroupId (Supabase not mocked properly)
        // and fall back to offline datasource
        // Since the from() call isn't mocked, it throws → fallback to offline
        final result = await ds.getExpenses();

        // Verify offline data was retrieved
        expect(result, isNotEmpty);
        expect(result.first.amount, equals(42.0));
        expect(result.first.id, equals('offline-1'));
      });
    });
  });
}
