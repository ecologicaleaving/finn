import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/groups/data/datasources/group_remote_datasource.dart';
import '../features/groups/presentation/providers/group_provider.dart';
import '../features/widget/data/datasources/widget_local_datasource.dart';
import '../features/widget/presentation/providers/widget_provider.dart';

/// Pulizia dei dati di sessione legati all'utente che esce (issue #64).
///
/// AC2 - NON tocca, volutamente, nessun dato di spesa:
/// - OfflineDatabase (Drift): tabelle `offline_expenses` e `sync_queue`
///   (spese pending/failed restano, filtrate per userId);
/// - cache Hive `expense_cache`;
/// - dati budget in Drift;
/// - le chiavi di sessione di Supabase / token in secure storage.
///
/// Cancella solo: cache del gruppo (secure storage) e dati del widget.
class SessionCleanup {
  SessionCleanup({
    required GroupRemoteDataSource groupDs,
    required WidgetLocalDataSource widgetDs,
  })  : _groupDs = groupDs,
        _widgetDs = widgetDs;

  final GroupRemoteDataSource _groupDs;
  final WidgetLocalDataSource _widgetDs;

  Future<void> clearUserScopedData(String? userId) async {
    try {
      await _groupDs.clearCachedGroup(userId: userId);
    } catch (e) {
      debugPrint('[SessionCleanup] group cache clear failed: $e');
    }
    try {
      await _widgetDs.clearWidgetData();
    } catch (e) {
      debugPrint('[SessionCleanup] widget clear failed: $e');
    }
  }
}

final sessionCleanupProvider = Provider<SessionCleanup>((ref) {
  return SessionCleanup(
    groupDs: ref.read(groupRemoteDataSourceProvider),
    widgetDs: ref.read(widgetLocalDataSourceProvider),
  );
});
