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
    final rows = <String, ReportExpense>{};
    for (final reimbursements in [false, true]) {
      for (var offset = 0;;) {
        _checkUser(userId);
        var query = client
            .from('expenses')
            .select(
                'id,group_id,amount,date,created_at,created_by,created_by_name,'
                'paid_by,paid_by_name,is_group_expense,transaction_type,'
                'category_id,category_name:expense_categories(name),notes,merchant,'
                'reimbursement_status,reimbursed_at')
            .eq('group_id', groupId)
            .eq('is_group_expense', true)
            .or(reimbursements
                ? 'transaction_type.eq.expense,transaction_type.is.null'
                : 'transaction_type.eq.expense,transaction_type.is.null,transaction_type.eq.income');
        query = reimbursements
            ? query
                .eq('reimbursement_status', 'reimbursed')
                .gte('reimbursed_at',
                    period.localHistoryStartUtc.toIso8601String())
                .lt('reimbursed_at',
                    period.localEndExclusiveUtc.toIso8601String())
            : query
                .gte('date', toServerDate(period.historyStart))
                .lte('date', toServerDate(period.end));
        final page = await query
            .order(reimbursements ? 'reimbursed_at' : 'date', ascending: true)
            .order('created_at', ascending: true)
            .order('id', ascending: true)
            .range(offset, offset + pageSize - 1)
            .timeout(const Duration(seconds: 30));
        _checkUser(userId);
        if (page.isEmpty) break;
        for (final json in page) {
          final row = ReportExpense.fromJson(json);
          rows[row.id] = row;
        }
        offset += page.length;
      }
    }
    return rows.values.toList();
  }
}
