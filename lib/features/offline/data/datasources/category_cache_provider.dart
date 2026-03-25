import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local/offline_database.dart';
import 'category_cache_datasource.dart';
import 'expense_cache_datasource.dart';

/// Provider for the offline database instance
final offlineDatabaseProvider = Provider<OfflineDatabase>((ref) {
  return OfflineDatabase();
});

/// Provider for category cache datasource
final categoryCacheDataSourceProvider = Provider<CategoryCacheDataSource>((ref) {
  final database = ref.watch(offlineDatabaseProvider);
  return CategoryCacheDataSourceImpl(database: database);
});

/// Provider for expense cache datasource (read-through cache for online expenses)
final expenseCacheDataSourceProvider = Provider<ExpenseCacheDataSource>((ref) {
  final database = ref.watch(offlineDatabaseProvider);
  return ExpenseCacheDataSourceImpl(database: database);
});
