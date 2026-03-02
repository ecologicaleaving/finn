import 'dart:convert';

import 'package:hive/hive.dart';

import '../../domain/entities/dashboard_stats_entity.dart';
import '../models/dashboard_stats_model.dart';

/// Local data source for caching dashboard statistics.
abstract class DashboardLocalDataSource {
  /// Gets cached dashboard stats if available and not expired.
  Future<DashboardStatsModel?> getCachedStats({
    required String groupId,
    required DashboardPeriod period,
    String? userId,
    int offset = 0,
  });

  /// Caches dashboard stats locally.
  Future<void> cacheStats(
    DashboardStatsModel stats, {
    required String groupId,
    String? userId,
    int offset = 0,
  });

  /// Clears all cached dashboard statistics.
  Future<void> clearCache();
}

/// Implementation of [DashboardLocalDataSource] using Hive.
class DashboardLocalDataSourceImpl implements DashboardLocalDataSource {
  DashboardLocalDataSourceImpl({
    required Box<String> cacheBox,
  }) : _cacheBox = cacheBox;

  final Box<String> _cacheBox;

  static const _cacheExpiryMinutes = 5; // Cache expires after 5 minutes

  String _getCacheKey(
    String groupId,
    DashboardPeriod period,
    String? userId,
    int offset,
  ) {
    final userPart = userId ?? 'all';
    return 'dashboard_${groupId}_${period.apiValue}_${offset}_$userPart';
  }

  String _getTimestampKey(String cacheKey) => '${cacheKey}_timestamp';

  @override
  Future<DashboardStatsModel?> getCachedStats({
    required String groupId,
    required DashboardPeriod period,
    String? userId,
    int offset = 0,
  }) async {
    try {
      final cacheKey = _getCacheKey(groupId, period, userId, offset);
      final timestampKey = _getTimestampKey(cacheKey);

      final cachedData = _cacheBox.get(cacheKey);
      final cachedTimestamp = _cacheBox.get(timestampKey);

      if (cachedData == null || cachedTimestamp == null) {
        return null;
      }

      // Check if cache has expired
      final timestamp = DateTime.parse(cachedTimestamp);
      final now = DateTime.now();
      if (now.difference(timestamp).inMinutes > _cacheExpiryMinutes) {
        // Cache expired, remove it
        await _cacheBox.delete(cacheKey);
        await _cacheBox.delete(timestampKey);
        return null;
      }

      final json = jsonDecode(cachedData) as Map<String, dynamic>;
      return DashboardStatsModel.fromJson(json, period);
    } catch (e) {
      // If there's any error reading cache, return null
      return null;
    }
  }

  @override
  Future<void> cacheStats(
    DashboardStatsModel stats, {
    required String groupId,
    String? userId,
    int offset = 0,
  }) async {
    try {
      final cacheKey = _getCacheKey(groupId, stats.period, userId, offset);
      final timestampKey = _getTimestampKey(cacheKey);

      final json = stats.toJson();
      await _cacheBox.put(cacheKey, jsonEncode(json));
      await _cacheBox.put(timestampKey, DateTime.now().toIso8601String());
    } catch (e) {
      // Silently fail on cache errors
    }
  }

  @override
  Future<void> clearCache() async {
    try {
      final keysToDelete = _cacheBox.keys
          .where((key) => key.toString().startsWith('dashboard_'))
          .toList();

      for (final key in keysToDelete) {
        await _cacheBox.delete(key);
      }
    } catch (e) {
      // Silently fail on cache errors
    }
  }
}
