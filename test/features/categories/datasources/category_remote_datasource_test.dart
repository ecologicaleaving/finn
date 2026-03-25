import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:finn/features/categories/data/datasources/category_remote_datasource.dart';
import 'package:finn/features/categories/domain/entities/expense_category_entity.dart';
import 'package:finn/features/offline/data/datasources/category_cache_datasource.dart';

@GenerateMocks([SupabaseClient, GoTrueClient, CategoryCacheDataSource])
import 'category_remote_datasource_test.mocks.dart';

void main() {
  group('CategoryRemoteDataSourceImpl', () {
    late MockSupabaseClient mockSupabaseClient;
    late MockGoTrueClient mockGoTrueClient;
    late MockCategoryDatasource mockCacheDataSource;

    setUp(() {
      mockSupabaseClient = MockSupabaseClient();
      mockGoTrueClient = MockGoTrueClient();
      mockCacheDataSource = MockCategoryDatasource();
      when(mockSupabaseClient.auth).thenReturn(mockGoTrueClient);
    });

    group('getCategories fallback', () {
      test('returns cached categories when network fails', () async {
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
        ];

        when(mockCacheDataSource.getCachedCategories('group-1'))
            .thenAnswer((_) async => cachedCategories);

        // Mock Supabase query builder to throw (simulating network timeout)
        when(mockSupabaseClient.from('expense_categories'))
            .thenThrow(Exception('Network timeout'));

        final ds = CategoryRemoteDataSourceImpl(
          supabaseClient: mockSupabaseClient,
          categoryCacheDataSource: mockCacheDataSource,
        );

        final result = await ds.getCategories(groupId: 'group-1');

        // Should return cached categories, not throw
        expect(result, isNotEmpty);
        expect(result.first.name, equals('Cibo'));
      });

      test('returns empty list when network fails and no cache', () async {
        final mockUser = User(
          id: 'user-1',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: DateTime.now().toIso8601String(),
        );

        when(mockGoTrueClient.currentUser).thenReturn(mockUser);

        when(mockCacheDataSource.getCachedCategories('group-1'))
            .thenAnswer((_) async => []);

        when(mockSupabaseClient.from('expense_categories'))
            .thenThrow(Exception('Network timeout'));

        final ds = CategoryRemoteDataSourceImpl(
          supabaseClient: mockSupabaseClient,
          categoryCacheDataSource: mockCacheDataSource,
        );

        final result = await ds.getCategories(groupId: 'group-1');

        // Should return empty list gracefully
        expect(result, isEmpty);
      });
    });
  });
}

// Mockito requires this alias since CategoryCacheDataSource is abstract
class MockCategoryDatasource extends Mock implements CategoryCacheDataSource {}
