import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/recurring_instance_generator.dart';
import '../../../../shared/services/connectivity_service.dart';
import '../../../offline/presentation/providers/offline_providers.dart';
import 'recurring_expense_provider.dart';

/// Foreground trigger of the recurring instance generation (issue #69).
///
/// Runs the local generator and then, if online, the sync (templates first,
/// then the queued expenses). It is called after authentication and at every
/// app resume. Concurrent runs are skipped by [_running]; runs concurrent
/// with the background isolate are harmless thanks to the deterministic
/// instance ids.
class RecurringGenerationTrigger {
  RecurringGenerationTrigger(this._ref);

  final Ref _ref;
  bool _running = false;

  Future<void> run() async {
    if (_running) return;
    _running = true;
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // The DAO provider keeps the (auto-dispose) database alive.
      final db = _ref.read(recurringExpenseDaoProvider).attachedDatabase;
      await RecurringInstanceGenerator.generate(db, DateTime.now());

      final online =
          _ref.read(connectivityServiceProvider).value == NetworkStatus.online;
      if (online) {
        await _ref.read(syncTriggerProvider.notifier).sync();
      }

      _ref.invalidate(pendingSyncCountProvider);
      final listState = _ref.read(recurringExpenseListProvider);
      if (listState.status != RecurringExpenseListStatus.initial) {
        await _ref.read(recurringExpenseListProvider.notifier).refresh();
      }
    } catch (e) {
      // Never blocks or crashes the app: retried at the next trigger.
      debugPrint('RecurringGenerationTrigger: $e');
    } finally {
      _running = false;
    }
  }
}

final recurringGenerationTriggerProvider =
    Provider<RecurringGenerationTrigger>((ref) {
  return RecurringGenerationTrigger(ref);
});
