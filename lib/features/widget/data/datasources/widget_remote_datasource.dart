import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/widget_data_model.dart';

/// Abstract interface for widget remote data operations
/// Feature 001: Supabase Realtime subscription for widget updates
abstract class WidgetRemoteDataSource {
  /// Subscribe to expense changes for real-time widget updates
  /// Listens to INSERT/UPDATE/DELETE on expenses table filtered by user
  Stream<List<Map<String, dynamic>>> subscribeToExpenseChanges(String userId);

  /// Get current month expenses for a user
  Future<List<Map<String, dynamic>>> getCurrentMonthExpenses(String userId);

  /// Dispose of subscriptions and clean up resources
  void dispose();
}

/// Implementation of WidgetRemoteDataSource using Supabase Realtime
class WidgetRemoteDataSourceImpl implements WidgetRemoteDataSource {
  final SupabaseClient supabase;

  WidgetRemoteDataSourceImpl({required this.supabase});

  @override
  Stream<List<Map<String, dynamic>>> subscribeToExpenseChanges(String userId) {
    // Subscribe to expenses table with realtime updates
    // Filter by paid_by to only get user's personal expenses
    return supabase
        .from('expenses')
        .stream(primaryKey: ['id'])
        .eq('paid_by', userId)
        .order('date', ascending: false);
  }

  @override
  Future<List<Map<String, dynamic>>> getCurrentMonthExpenses(String userId) async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    final response = await supabase
        .from('expenses')
        .select('id, amount, date')
        .eq('paid_by', userId)
        .gte('date', startOfMonth.toIso8601String().split('T')[0])
        .lte('date', endOfMonth.toIso8601String().split('T')[0]);

    return List<Map<String, dynamic>>.from(response as List);
  }

  @override
  void dispose() {
    // Cleanup if needed
    // Supabase handles subscription cleanup automatically
  }
}
