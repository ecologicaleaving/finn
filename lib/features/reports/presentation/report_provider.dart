import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/presentation/providers/auth_provider.dart';
import '../../groups/presentation/providers/group_provider.dart';
import '../data/report_loader.dart';
import '../domain/group_report.dart';

final reportClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);
final reportLoaderProvider = Provider<ReportLoader>(
    (ref) => SupabaseReportLoader(Supabase.instance.client));

typedef ReportRequest = ({
  String userId,
  String groupId,
  DateTime month,
  DateTime today
});

final groupReportProvider = FutureProvider.autoDispose
    .family<GroupReport, ReportRequest>((ref, request) async {
  final userId = ref.watch(currentUserProvider.select((user) => user?.id));
  final groupId = ref.watch(groupProvider.select((state) => state.group?.id));
  if (userId != request.userId || groupId != request.groupId) {
    throw StateError('La sessione o il gruppo sono cambiati.');
  }
  final period = ReportPeriod(request.month, request.today);
  final rows = await ref
      .watch(reportLoaderProvider)
      .load(userId: request.userId, groupId: request.groupId, period: period);
  return GroupReport.calculate(
      groupId: request.groupId, period: period, rows: rows);
});
