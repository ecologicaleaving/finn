import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/date_only.dart';
import '../domain/group_report.dart';

abstract class ReportLoader {
  Future<List<ReportExpense>> load(
      {required String userId,
      required String groupId,
      required ReportPeriod period});
}

/// Read-only, independently paginated dataset; never uses the expense list cache.
class SupabaseReportLoader implements ReportLoader {
  SupabaseReportLoader(this.client);
  final SupabaseClient client;
  static const pageSize = 200;
  void _checkUser(String userId) {
    if (client.auth.currentUser?.id != userId) {
      throw StateError('La sessione è cambiata. Riapri Report.');
    }
  }

  @override
  Future<List<ReportExpense>> load(
      {required String userId,
      required String groupId,
      required ReportPeriod period}) async {
    final rows = <ReportExpense>[];
    for (var offset = 0;;) {
      _checkUser(userId);
      final page = await client
          .from('expenses')
          .select(
              'id,group_id,amount,date,created_at,created_by,created_by_name,'
              'paid_by,paid_by_name,is_group_expense,transaction_type,'
              'category_id,category_name:expense_categories(name),notes,merchant')
          .eq('group_id', groupId)
          .eq('is_group_expense', true)
          .or('transaction_type.eq.expense,transaction_type.is.null')
          .gte('date', toServerDate(period.historyStart))
          .lte('date', toServerDate(period.end))
          .order('date', ascending: true)
          .order('created_at', ascending: true)
          .order('id', ascending: true)
          .range(offset, offset + pageSize - 1)
          .timeout(const Duration(seconds: 30));
      _checkUser(userId);
      if (page.isEmpty) return rows;
      rows.addAll(page.map(ReportExpense.fromJson));
      offset += page.length;
    }
  }
}
