import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/config/env.dart';
import 'backend_reachability.dart';

part 'connectivity_service.g.dart';

/// Network status enum
enum NetworkStatus {
  online,
  offline,
  unknown,
}

/// Connectivity service that monitors network status with debouncing and actual internet verification
///
/// Features:
/// - Real-time connectivity monitoring via connectivity_plus
/// - Debouncing (2-second delay) to avoid rapid state changes
/// - Actual internet verification by pinging Supabase
/// - Stream-based reactive updates for UI
@riverpod
class ConnectivityService extends _$ConnectivityService {
  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  @override
  Stream<NetworkStatus> build() async* {
    ref.onDispose(() {
      _subscription?.cancel();
    });

    // Initial check
    final initialResult = await _connectivity.checkConnectivity();
    yield await _mapResultsToStatus(initialResult);

    // Create a stream controller to emit values from the subscription
    final controller = StreamController<NetworkStatus>();

    // Listen for changes with debouncing
    _subscription = _connectivity.onConnectivityChanged.listen((results) async {
      // Add small delay to avoid rapid updates
      await Future.delayed(const Duration(seconds: 2));

      // Update status
      final status = await _mapResultsToStatus(results);
      controller.add(status);
    });

    // Yield values from the controller
    await for (final status in controller.stream) {
      yield status;
    }
  }

  /// Maps connectivity results to network status
  Future<NetworkStatus> _mapResultsToStatus(
    List<ConnectivityResult> results,
  ) async {
    // Check if any connection available
    final hasNetworkInterface = results.any(
      (result) => result != ConnectivityResult.none,
    );

    if (!hasNetworkInterface) {
      return NetworkStatus.offline;
    }

    // Verify actual internet access with Supabase ping
    final hasInternet = await _verifyInternetAccess();
    return hasInternet ? NetworkStatus.online : NetworkStatus.offline;
  }

  /// Independent of the current session, including the first visit before login.
  Future<bool> _verifyInternetAccess() => checkBackendReachability(
        supabaseUrl: Env.supabaseUrl,
        anonKey: Env.supabaseAnonKey,
      );
}

/// Helper provider for getting current connectivity status synchronously
/// Returns null if status is not yet determined
@riverpod
NetworkStatus? currentNetworkStatus(CurrentNetworkStatusRef ref) {
  return ref.watch(connectivityServiceProvider).value;
}

/// Helper provider to check if online
@riverpod
bool isOnline(IsOnlineRef ref) {
  final status = ref.watch(currentNetworkStatusProvider);
  return status == NetworkStatus.online;
}

/// Helper provider to check if offline
@riverpod
bool isOffline(IsOfflineRef ref) {
  final status = ref.watch(currentNetworkStatusProvider);
  return status == NetworkStatus.offline;
}
