import 'dart:async';
import 'package:flutter/foundation.dart';

/// Service that pre-caches all data for offline use on app startup.
/// Call [precacheAll] once after successful authentication when online.
class OfflinePrecacheService {
  /// Pre-cache all data needed for offline use.
  /// Runs in background, never throws — all errors are silently caught.
  static Future<void> precacheAll({
    required Future<void> Function() loadExpenses,
    required Future<void> Function() loadDashboard,
    Future<void> Function()? loadCategories,
  }) async {
    debugPrint('[PRECACHE] Starting offline pre-cache...');

    // Run all in parallel, catch errors individually
    await Future.wait([
      _safe('expenses', loadExpenses),
      _safe('dashboard', loadDashboard),
      if (loadCategories != null) _safe('categories', loadCategories),
    ]);

    debugPrint('[PRECACHE] Pre-cache complete');
  }

  static Future<void> _safe(String name, Future<void> Function() fn) async {
    try {
      await fn().timeout(const Duration(seconds: 30));
      debugPrint('[PRECACHE] ✅ $name cached');
    } catch (e) {
      debugPrint('[PRECACHE] ⚠️ $name failed: $e');
    }
  }
}
