import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// Drift chooses persistent OPFS or IndexedDB storage supported by the browser.
QueryExecutor openOfflineConnection() => DatabaseConnection.delayed(() async {
      final result = await WasmDatabase.open(
        databaseName: 'finn_offline_expenses',
        sqlite3Uri: Uri.parse('sqlite3.wasm'),
        driftWorkerUri: Uri.parse('drift_worker.js'),
      );
      return result.resolvedExecutor;
    }());
