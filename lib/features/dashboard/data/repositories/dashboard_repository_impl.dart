import '../../domain/entities/dashboard_stats_entity.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../datasources/dashboard_local_datasource.dart';
import '../datasources/dashboard_remote_datasource.dart';
import '../models/dashboard_stats_model.dart';

/// Implementation of [DashboardRepository].
class DashboardRepositoryImpl implements DashboardRepository {
  DashboardRepositoryImpl({
    required DashboardRemoteDataSource remoteDataSource,
    required DashboardLocalDataSource localDataSource,
  })  : _remoteDataSource = remoteDataSource,
        _localDataSource = localDataSource;

  final DashboardRemoteDataSource _remoteDataSource;
  final DashboardLocalDataSource _localDataSource;

  String? _currentGroupId;

  @override
  Future<DashboardStats> getStats({
    required String groupId,
    required DashboardPeriod period,
    String? userId,
    int offset = 0,
  }) async {
    _currentGroupId = groupId;

    // Fetch from remote
    final stats = await _remoteDataSource.getStats(
      groupId: groupId,
      period: period,
      userId: userId,
      offset: offset,
    );

    // Cache the result
    await _localDataSource.cacheStats(
      stats,
      groupId: groupId,
      userId: userId,
      offset: offset,
    );

    return stats;
  }

  @override
  Future<DashboardStats?> getCachedStats({
    required String groupId,
    required DashboardPeriod period,
    String? userId,
    int offset = 0,
  }) async {
    return _localDataSource.getCachedStats(
      groupId: groupId,
      period: period,
      userId: userId,
      offset: offset,
    );
  }

  @override
  Future<void> cacheStats(DashboardStats stats, {String? userId}) async {
    if (_currentGroupId == null) return;

    await _localDataSource.cacheStats(
      DashboardStatsModel.fromEntity(stats),
      groupId: _currentGroupId!,
      userId: userId,
    );
  }

  @override
  Future<void> clearCache() async {
    await _localDataSource.clearCache();
  }
}
