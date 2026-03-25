import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/dashboard_stats_entity.dart';
import '../models/dashboard_stats_model.dart';
import 'dashboard_local_datasource.dart';

/// Remote data source for dashboard statistics.
/// Calculates stats from expenses table.
abstract class DashboardRemoteDataSource {
  /// Fetches dashboard statistics by querying expenses directly.
  Future<DashboardStatsModel> getStats({
    required String groupId,
    required DashboardPeriod period,
    String? userId,
    int offset = 0,
  });
}

/// Implementation of [DashboardRemoteDataSource] using direct Supabase queries.
/// Supports offline-first: timeout + write-through cache + network-error fallback.
class DashboardRemoteDataSourceImpl implements DashboardRemoteDataSource {
  DashboardRemoteDataSourceImpl({
    required SupabaseClient supabaseClient,
    required DashboardLocalDataSource localDataSource,
  })  : _supabaseClient = supabaseClient,
        _localDataSource = localDataSource;

  final SupabaseClient _supabaseClient;
  final DashboardLocalDataSource _localDataSource;

  /// Returns true for network-level errors that justify a cache fallback.
  bool _isNetworkError(Object e) {
    if (e is TimeoutException) return true;
    if (e is SocketException) return true;
    if (e is HttpException) return true;
    // Supabase wraps network errors — check message as safety net
    final msg = e.toString().toLowerCase();
    if (msg.contains('failed host lookup') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection refused')) {
      return true;
    }
    return false;
  }

  /// Calculate date range based on period and offset
  (DateTime start, DateTime end) _calculateDateRange(
    DashboardPeriod period,
    int offset,
  ) {
    final now = DateTime.now();

    switch (period) {
      case DashboardPeriod.week:
        // Find the start of the current week (Monday = 1)
        final weekDay = now.weekday;
        final currentWeekStart = now.subtract(Duration(days: weekDay - 1));
        final targetWeekStart = currentWeekStart.add(Duration(days: offset * 7));
        final targetWeekEnd = targetWeekStart.add(const Duration(days: 6));
        return (
          DateTime(targetWeekStart.year, targetWeekStart.month, targetWeekStart.day),
          DateTime(targetWeekEnd.year, targetWeekEnd.month, targetWeekEnd.day, 23, 59, 59),
        );

      case DashboardPeriod.month:
        // Calculate target month/year using DateTime constructor
        // DateTime handles month overflow/underflow automatically
        final targetDate = DateTime(now.year, now.month + offset, 1);
        final startDate = DateTime(targetDate.year, targetDate.month, 1);
        // Last day of month: day 0 of next month
        final endDate = DateTime(targetDate.year, targetDate.month + 1, 0, 23, 59, 59);
        return (startDate, endDate);

      case DashboardPeriod.year:
        final targetYear = now.year + offset;
        return (
          DateTime(targetYear, 1, 1),
          DateTime(targetYear, 12, 31, 23, 59, 59),
        );
    }
  }

  @override
  Future<DashboardStatsModel> getStats({
    required String groupId,
    required DashboardPeriod period,
    String? userId,
    int offset = 0,
  }) async {
    try {
      // Calculate date range based on period and offset
      final (startDate, endDate) = _calculateDateRange(period, offset);

      // Build query - select expenses with category_id (not category)
      // Filter by paid_by to attribute expenses to correct member
      var query = _supabaseClient
          .from('expenses')
          .select('id, amount, category_id, date, paid_by, is_group_expense')
          .eq('group_id', groupId)
          .gte('date', startDate.toIso8601String().split('T')[0])
          .lte('date', endDate.toIso8601String().split('T')[0]);

      if (userId != null) {
        // Filter by paid_by to show expenses paid by specific user
        query = query.eq('paid_by', userId);
      }

      // 10s timeout — avoids hanging forever in airplane mode
      final expenses = await query.timeout(const Duration(seconds: 10));

      // Fetch member names separately
      final memberIds = expenses
          .where((e) => e['paid_by'] != null)
          .map((e) => e['paid_by'] as String)
          .toSet()
          .toList();
      final memberNames = <String, String>{};

      if (memberIds.isNotEmpty) {
        try {
          final profiles = await _supabaseClient
              .from('profiles')
              .select('id, display_name')
              .inFilter('id', memberIds)
              .timeout(const Duration(seconds: 5));

          for (final profile in profiles) {
            memberNames[profile['id'] as String] =
                profile['display_name'] as String? ?? 'Utente';
          }
        } catch (_) {
          // Ignore errors fetching names, use default
        }
      }

      // Calculate stats from expenses
      double totalAmount = 0;
      final categoryTotals = <String, Map<String, dynamic>>{};
      final memberTotals = <String, Map<String, dynamic>>{};
      final trendData = <String, Map<String, dynamic>>{};

      for (final expense in expenses) {
        final amount = (expense['amount'] as num).toDouble();
        final categoryId = expense['category_id'] as String? ?? 'altro';
        final date = expense['date'] as String;
        final paidBy = expense['paid_by'] as String? ?? 'unknown';
        final displayName = memberNames[paidBy] ?? 'Utente sconosciuto';

        totalAmount += amount;

        // Category breakdown
        if (!categoryTotals.containsKey(categoryId)) {
          categoryTotals[categoryId] = {'total': 0.0, 'count': 0};
        }
        categoryTotals[categoryId]!['total'] =
            (categoryTotals[categoryId]!['total'] as double) + amount;
        categoryTotals[categoryId]!['count'] =
            (categoryTotals[categoryId]!['count'] as int) + 1;

        // Member breakdown
        if (!memberTotals.containsKey(paidBy)) {
          memberTotals[paidBy] = {
            'display_name': displayName,
            'total': 0.0,
            'count': 0
          };
        }
        memberTotals[paidBy]!['total'] =
            (memberTotals[paidBy]!['total'] as double) + amount;
        memberTotals[paidBy]!['count'] =
            (memberTotals[paidBy]!['count'] as int) + 1;

        // Trend data
        final trendKey = period == DashboardPeriod.year
            ? date.substring(0, 7) // YYYY-MM for year view
            : date; // YYYY-MM-DD for week/month view
        if (!trendData.containsKey(trendKey)) {
          trendData[trendKey] = {'total': 0.0, 'count': 0};
        }
        trendData[trendKey]!['total'] =
            (trendData[trendKey]!['total'] as double) + amount;
        trendData[trendKey]!['count'] =
            (trendData[trendKey]!['count'] as int) + 1;
      }

      final expenseCount = expenses.length;
      final averageExpense = expenseCount > 0 ? totalAmount / expenseCount : 0.0;

      // Build category breakdown list
      final byCategory = categoryTotals.entries.map((e) {
        final percentage =
            totalAmount > 0 ? (e.value['total'] as double) / totalAmount * 100 : 0.0;
        return CategoryBreakdownModel(
          category: e.key,
          total: e.value['total'] as double,
          count: e.value['count'] as int,
          percentage: double.parse(percentage.toStringAsFixed(1)),
        );
      }).toList()
        ..sort((a, b) => b.total.compareTo(a.total));

      // Build member breakdown list
      final byMember = memberTotals.entries.map((e) {
        final percentage =
            totalAmount > 0 ? (e.value['total'] as double) / totalAmount * 100 : 0.0;
        return MemberBreakdownModel(
          userId: e.key,
          displayName: e.value['display_name'] as String,
          total: e.value['total'] as double,
          count: e.value['count'] as int,
          percentage: double.parse(percentage.toStringAsFixed(1)),
        );
      }).toList()
        ..sort((a, b) => b.total.compareTo(a.total));

      // Build trend list
      final trend = trendData.entries.map((e) {
        final dateStr = period == DashboardPeriod.year
            ? '${e.key}-01' // Add day for parsing
            : e.key;
        return TrendDataPointModel(
          date: DateTime.parse(dateStr),
          total: e.value['total'] as double,
          count: e.value['count'] as int,
        );
      }).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      final result = DashboardStatsModel(
        period: period,
        startDate: startDate,
        endDate: endDate,
        totalAmount: totalAmount,
        expenseCount: expenseCount,
        averageExpense: double.parse(averageExpense.toStringAsFixed(2)),
        byCategory: byCategory,
        byMember: byMember,
        trend: trend,
      );

      // Write-through: persist to local cache so offline reads are fresh
      try {
        await _localDataSource.cacheStats(
          result,
          groupId: groupId,
          userId: userId,
          offset: offset,
        );
      } catch (cacheErr) {
        debugPrint('[DASHBOARD] Failed to write cache: $cacheErr');
      }

      return result;
    } on PostgrestException catch (e) {
      // Supabase application errors (e.g. RLS denied) → not a network issue
      throw ServerException(e.message);
    } catch (e) {
      if (e is ServerException) rethrow;

      // Network/timeout errors → try local cache (stale is fine offline)
      if (_isNetworkError(e)) {
        debugPrint('[OFFLINE] Dashboard network error, falling back to cache: $e');
        try {
          final cached = await _localDataSource.getCachedStats(
            groupId: groupId,
            period: period,
            userId: userId,
            offset: offset,
            ignoreExpiry: true, // stale data is better than no data offline
          );
          if (cached != null) {
            debugPrint('[OFFLINE] Returning cached dashboard stats');
            return cached;
          }
        } catch (cacheErr) {
          debugPrint('[OFFLINE] Cache read also failed: $cacheErr');
        }
        // Cache empty too — propagate as ServerException so UI shows error
        throw ServerException('Nessun dato disponibile offline');
      }

      throw ServerException('Failed to fetch dashboard stats: $e');
    }
  }
}
