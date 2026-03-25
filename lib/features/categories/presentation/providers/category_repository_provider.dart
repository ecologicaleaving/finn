import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../offline/data/datasources/category_cache_datasource.dart';
import '../../../offline/presentation/providers/offline_providers.dart';
import '../../data/datasources/category_remote_datasource.dart';
import '../../data/repositories/category_repository_impl.dart';
import '../../domain/repositories/category_repository.dart';

/// Provider for Supabase client
final _supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Provider for category cache datasource (Drift-backed, T6)
final categoryCacheDataSourceProvider = Provider<CategoryCacheDataSource>((ref) {
  final db = ref.watch(offlineDatabaseProvider);
  return CategoryCacheDataSourceImpl(database: db);
});

/// Provider for category remote datasource — wired with Drift cache fallback (T6)
final categoryRemoteDataSourceProvider = Provider<CategoryRemoteDataSource>((ref) {
  return CategoryRemoteDataSourceImpl(
    supabaseClient: ref.watch(_supabaseClientProvider),
    categoryCacheDataSource: ref.watch(categoryCacheDataSourceProvider),
  );
});

/// Provider for category repository
final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepositoryImpl(
    remoteDataSource: ref.watch(categoryRemoteDataSourceProvider),
  );
});
