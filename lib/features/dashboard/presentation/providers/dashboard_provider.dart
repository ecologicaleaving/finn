import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../groups/presentation/providers/group_provider.dart';
import '../../data/datasources/dashboard_local_datasource.dart';
import '../../data/datasources/dashboard_remote_datasource.dart';
import '../../data/repositories/dashboard_repository_impl.dart';
import '../../domain/entities/dashboard_stats_entity.dart';
import '../../domain/repositories/dashboard_repository.dart';

/// Provider for dashboard remote data source
final dashboardRemoteDataSourceProvider =
    Provider<DashboardRemoteDataSource>((ref) {
  return DashboardRemoteDataSourceImpl(
    supabaseClient: Supabase.instance.client,
    localDataSource: ref.watch(dashboardLocalDataSourceProvider),
  );
});

/// Provider for dashboard local data source
final dashboardLocalDataSourceProvider =
    Provider<DashboardLocalDataSource>((ref) {
  final box = Hive.box<String>('dashboard_cache');
  return DashboardLocalDataSourceImpl(cacheBox: box);
});

/// Provider for dashboard repository
final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepositoryImpl(
    remoteDataSource: ref.watch(dashboardRemoteDataSourceProvider),
    localDataSource: ref.watch(dashboardLocalDataSourceProvider),
  );
});

/// Dashboard state status
enum DashboardStatus {
  initial,
  loading,
  loaded,
  error,
}

/// View mode for dashboard
enum DashboardViewMode {
  personal,
  group,
}

/// Dashboard state class
class DashboardState {
  const DashboardState({
    this.status = DashboardStatus.initial,
    this.stats,
    this.period = DashboardPeriod.month,
    this.viewMode = DashboardViewMode.group,
    this.selectedMemberId,
    this.errorMessage,
    this.offset = 0,
  });

  final DashboardStatus status;
  final DashboardStats? stats;
  final DashboardPeriod period;
  final DashboardViewMode viewMode;
  final String? selectedMemberId;
  final String? errorMessage;
  final int offset;

  DashboardState copyWith({
    DashboardStatus? status,
    DashboardStats? stats,
    DashboardPeriod? period,
    DashboardViewMode? viewMode,
    String? selectedMemberId,
    bool clearMemberFilter = false,
    String? errorMessage,
    int? offset,
  }) {
    return DashboardState(
      status: status ?? this.status,
      stats: stats ?? this.stats,
      period: period ?? this.period,
      viewMode: viewMode ?? this.viewMode,
      selectedMemberId:
          clearMemberFilter ? null : (selectedMemberId ?? this.selectedMemberId),
      errorMessage: errorMessage,
      offset: offset ?? this.offset,
    );
  }

  bool get isLoading => status == DashboardStatus.loading;
  bool get hasError => status == DashboardStatus.error;
  bool get hasData => stats != null && !stats!.isEmpty;
  bool get isPersonalView => viewMode == DashboardViewMode.personal;
  bool get isGroupView => viewMode == DashboardViewMode.group;
  bool get canNavigateNext => offset < 0;
}

/// Dashboard notifier for managing dashboard state
class DashboardNotifier extends StateNotifier<DashboardState> {
  DashboardNotifier(this._dashboardRepository, this._currentUserId)
      : super(const DashboardState());

  final DashboardRepository _dashboardRepository;
  final String? _currentUserId;
  String? _groupId;

  /// Initialize with group ID
  void setGroupId(String groupId) {
    _groupId = groupId;
  }

  /// Load dashboard stats
  Future<void> loadStats() async {
    if (_groupId == null) return;
    if (!mounted) return;

    // Prevent duplicate loads
    if (state.isLoading) return;

    state = state.copyWith(status: DashboardStatus.loading, errorMessage: null);

    // Try to load from cache first for faster display
    final cachedStats = await _dashboardRepository.getCachedStats(
      groupId: _groupId!,
      period: state.period,
      userId: _getFilterUserId(),
      offset: state.offset,
    );

    if (!mounted) return;

    if (cachedStats != null) {
      state = state.copyWith(
        status: DashboardStatus.loaded,
        stats: cachedStats,
      );
    }

    // Then fetch fresh data
    try {
      final stats = await _dashboardRepository.getStats(
        groupId: _groupId!,
        period: state.period,
        userId: _getFilterUserId(),
        offset: state.offset,
      );

      if (!mounted) return;

      state = state.copyWith(
        status: DashboardStatus.loaded,
        stats: stats,
      );
    } catch (e) {
      if (!mounted) return;

      // If we have cached data, keep showing it with an error message
      if (state.stats != null) {
        state = state.copyWith(
          errorMessage: 'Impossibile aggiornare i dati: $e',
        );
      } else {
        state = state.copyWith(
          status: DashboardStatus.error,
          errorMessage: 'Errore nel caricamento: $e',
        );
      }
    }
  }

  /// Get the user ID to filter by based on view mode and member selection
  String? _getFilterUserId() {
    if (state.viewMode == DashboardViewMode.personal) {
      return _currentUserId;
    }
    return state.selectedMemberId;
  }

  /// Change time period
  Future<void> setPeriod(DashboardPeriod period) async {
    if (state.period == period) return;
    state = state.copyWith(period: period, offset: 0);
    await loadStats();
  }

  /// Navigate to previous period
  Future<void> navigatePrevious() async {
    state = state.copyWith(offset: state.offset - 1);
    await loadStats();
  }

  /// Navigate to next period
  Future<void> navigateNext() async {
    if (state.offset >= 0) return;
    state = state.copyWith(offset: state.offset + 1);
    await loadStats();
  }

  /// Change view mode
  Future<void> setViewMode(DashboardViewMode mode) async {
    if (state.viewMode == mode) return;
    state = state.copyWith(
      viewMode: mode,
      clearMemberFilter: mode == DashboardViewMode.personal,
      offset: 0,
    );
    await loadStats();
  }

  /// Filter by member (group view only)
  Future<void> setMemberFilter(String? memberId) async {
    if (state.selectedMemberId == memberId) return;
    state = state.copyWith(
      selectedMemberId: memberId,
      clearMemberFilter: memberId == null,
    );
    await loadStats();
  }

  /// Clear member filter
  Future<void> clearMemberFilter() async {
    await setMemberFilter(null);
  }

  /// Refresh stats
  Future<void> refresh() async {
    await loadStats();
  }

  /// Clear error message
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}

/// Provider for dashboard state
final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, DashboardState>((ref) {
  final repository = ref.watch(dashboardRepositoryProvider);
  final currentUser = Supabase.instance.client.auth.currentUser;
  final notifier = DashboardNotifier(repository, currentUser?.id);

  // Listen to group changes and auto-load stats (use listen to avoid provider recreation)
  ref.listen<GroupState>(groupProvider, (previous, next) {
    if (next.group != null) {
      notifier.setGroupId(next.group!.id);
      // Only load if group actually changed
      if (previous?.group?.id != next.group!.id) {
        Future.microtask(() => notifier.loadStats());
      }
    }
  });

  // Initial setup if group is already available
  final groupState = ref.read(groupProvider);
  if (groupState.group != null) {
    notifier.setGroupId(groupState.group!.id);
    Future.microtask(() => notifier.loadStats());
  }

  return notifier;
});

/// Convenience provider for current stats
final currentStatsProvider = Provider<DashboardStats?>((ref) {
  return ref.watch(dashboardProvider).stats;
});

/// Convenience provider for category breakdown
final categoryBreakdownProvider = Provider<List<CategoryBreakdown>>((ref) {
  return ref.watch(dashboardProvider).stats?.byCategory ?? [];
});

/// Convenience provider for member breakdown
final memberBreakdownProvider = Provider<List<MemberBreakdown>>((ref) {
  return ref.watch(dashboardProvider).stats?.byMember ?? [];
});

/// Convenience provider for trend data
final trendDataProvider = Provider<List<TrendDataPoint>>((ref) {
  return ref.watch(dashboardProvider).stats?.trend ?? [];
});
