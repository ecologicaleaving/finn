import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:finn/features/categories/data/datasources/category_remote_datasource.dart';
import 'package:finn/features/categories/domain/entities/expense_category_entity.dart';
import 'package:finn/features/offline/data/datasources/category_cache_datasource.dart';

// T12: Unit tests for CategoryRemoteDataSourceImpl — timeout + fallback
@GenerateMocks([SupabaseClient, GoTrueClient, CategoryCacheDataSource])
import 'category_remote_datasource_test.mocks.dart';

void main() {
  group('CategoryRemoteDataSourceImpl — offline-first (T6/T12)', () {
    late MockSupabaseClient mockSupabaseClient;
    late MockGoTrueClient mockGoTrueClient;
    late MockCategoryCacheDataSource mockCacheDataSource;

    setUp(() {
      mockSupabaseClient = MockSupabaseClient();
      mockGoTrueClient = MockGoTrueClient();
      mockCacheDataSource = MockCategoryCacheDataSource();
      when(mockSupabaseClient.auth).thenReturn(mockGoTrueClient);
    });

    group('getCategories()', () {
      test('returns cached categories when Supabase throws (network error)', () async {
        final mockUser = User(
          id: 'user-1',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: DateTime.now().toIso8601String(),
        );

        when(mockGoTrueClient.currentUser).thenReturn(mockUser);

        final cachedCategories = [
          ExpenseCategoryEntity(
            id: 'cat-1',
            name: 'Cibo',
            groupId: 'group-1',
            isDefault: true,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          ExpenseCategoryEntity(
            id: 'cat-2',
            name: 'Trasporti',
            groupId: 'group-1',
            isDefault: true,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ];

        when(mockCacheDataSource.getCachedCategories('group-1'))
            .thenAnswer((_) async => cachedCategories);

        // Simulate Supabase being unreachable
        when(mockSupabaseClient.from('expense_categories'))
            .thenThrow(Exception('Connection refused'));

        final ds = CategoryRemoteDataSourceImpl(
          supabaseClient: mockSupabaseClient,
          categoryCacheDataSource: mockCacheDataSource,
        );

        final result = await ds.getCategories(groupId: 'group-1');

        // Should return cached categories, not throw
        expect(result, hasLength(2));
        expect(result.first.name, equals('Cibo'));
      });

      test('returns empty list when network fails and no cache exists', () async {
        final mockUser = User(
          id: 'user-1',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: DateTime.now().toIso8601String(),
        );

        when(mockGoTrueClient.currentUser).thenReturn(mockUser);

        // Empty cache
        when(mockCacheDataSource.getCachedCategories('group-1'))
            .thenAnswer((_) async => []);

        when(mockSupabaseClient.from('expense_categories'))
            .thenThrow(Exception('Timeout'));

        final ds = CategoryRemoteDataSourceImpl(
          supabaseClient: mockSupabaseClient,
          categoryCacheDataSource: mockCacheDataSource,
        );

        final result = await ds.getCategories(groupId: 'group-1');

        // Graceful degradation: empty list, no exception
        expect(result, isEmpty);
      });
    });

    group('getCategoriesByMRU()', () {
      test('falls back to cache when Supabase throws', () async {
        final mockUser = User(
          id: 'user-1',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: DateTime.now().toIso8601String(),
        );

        when(mockGoTrueClient.currentUser).thenReturn(mockUser);

        final cachedCategories = [
          ExpenseCategoryEntity(
            id: 'cat-1',
            name: 'Cibo',
            groupId: 'group-1',
            isDefault: false,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ];

        when(mockCacheDataSource.getCachedCategories('group-1'))
            .thenAnswer((_) async => cachedCategories);

        when(mockSupabaseClient.from('expense_categories'))
            .thenThrow(Exception('Network timeout'));

        final ds = CategoryRemoteDataSourceImpl(
          supabaseClient: mockSupabaseClient,
          categoryCacheDataSource: mockCacheDataSource,
        );

        final result =
            await ds.getCategoriesByMRU(groupId: 'group-1', userId: 'user-1');

        expect(result, hasLength(1));
        expect(result.first.name, equals('Cibo'));
      });
    });
  });
}
