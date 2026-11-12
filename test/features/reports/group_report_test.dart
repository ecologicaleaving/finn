import 'package:flutter_test/flutter_test.dart';
import 'package:family_expense_tracker/features/reports/domain/group_report.dart';

ReportExpense row(
  String id,
  String date,
  Object amount, {
  String group = 'g',
  bool shared = true,
  String? type,
  String creator = 'a',
  String? creatorName = 'Anna',
  String? payer,
  String? payerName,
  String category = 'Cibo',
}) =>
    ReportExpense.fromJson({
      'id': id,
      'group_id': group,
      'date': date,
      'amount': amount,
      'created_by': creator,
      'created_by_name': creatorName,
      'paid_by': payer,
      'paid_by_name': payerName,
      'category_id': category,
      'category_name': {'name': category},
      'is_group_expense': shared,
      'transaction_type': type,
      'reimbursement_status': 'reimbursed',
    });

void main() {
  test('31 March compares equal days but preserves the complete current KPI',
      () {
    final period = ReportPeriod(DateTime(2026, 3), DateTime(2026, 3, 31));
    final report = GroupReport.calculate(groupId: 'g', period: period, rows: [
      row('feb', '2026-02-28', '12.30'),
      row('march', '2026-03-28', '10.10'),
      row('last', '2026-03-31', '20.20'),
    ]);
    expect(period.comparisonEnd, DateTime.utc(2026, 3, 28));
    expect(period.previousEnd, DateTime.utc(2026, 2, 28));
    expect(report.totalCents, 3030);
    expect(report.comparisonCents, 1010);
    expect(report.previousCents, 1230);
    expect(report.trend.last.partial, isTrue);
  });

  test('leap February and year boundaries use calendar dates', () {
    final leap = ReportPeriod(DateTime(2024, 3), DateTime(2024, 3, 31));
    expect(leap.comparisonEnd, DateTime.utc(2024, 3, 29));
    expect(leap.previousEnd, DateTime.utc(2024, 2, 29));
    final january = ReportPeriod(DateTime(2026, 1), DateTime(2026, 1, 11));
    expect(january.previousMonth, DateTime.utc(2025, 12));
    expect(january.historyStart, DateTime.utc(2025, 8));
    expect(january.previousEnd, DateTime.utc(2025, 12, 11));
    expect(reportDay(DateTime(2026, 3, 29, 23)), DateTime.utc(2026, 3, 29));
  });

  test(
      'historical months compare complete months and future selection is clamped',
      () {
    final past = ReportPeriod(DateTime(2026, 2), DateTime(2026, 11, 11));
    expect(past.end, DateTime.utc(2026, 2, 28));
    expect(past.previousEnd, DateTime.utc(2026, 1, 31));
    expect(past.isCurrent, isFalse);
    final future = ReportPeriod(DateTime(2027), DateTime(2026, 11, 11));
    expect(future.month, DateTime.utc(2026, 11));
    expect(future.end, DateTime.utc(2026, 11, 11));
  });

  test(
      'cents reconcile categories, people and average; reimbursed rows included',
      () {
    final report = GroupReport.calculate(
        groupId: 'g',
        period: ReportPeriod(DateTime(2026, 11), DateTime(2026, 11, 11)),
        rows: [
          row('a', '2026-11-01', 0.1),
          row('b', '2026-11-02', 0.2),
          row('c', '2026-11-02', '12.39', category: 'Casa')
        ]);
    expect(report.totalCents, 1269);
    expect(report.count, 3);
    expect(report.averageCents, 423);
    expect(report.categories.fold<int>(0, (s, e) => s + e.cents), 1269);
    expect(report.payers.fold<int>(0, (s, e) => s + e.cents), 1269);
    expect(report.days.first.cents, 1259);
    expect(report.largestExpense!.id, 'c');
    expect(reportCents('1.005'), 101);
    expect(reportCents('-1.005'), -101);
  });

  test(
      'personal, income, other group, future and outside-window rows are excluded',
      () {
    final report = GroupReport.calculate(
        groupId: 'g',
        period: ReportPeriod(DateTime(2026, 11), DateTime(2026, 11, 11)),
        rows: [
          row('legacy', '2026-11-01', 1),
          row('expense', '2026-11-02', 2, type: 'expense'),
          row('personal', '2026-11-01', 100, shared: false),
          row('income', '2026-11-01', 100, type: 'income'),
          row('other', '2026-11-01', 100, group: 'other'),
          row('future', '2026-11-12', 100),
          row('old', '2026-05-31', 100),
        ]);
    expect(report.totalCents, 300);
    expect(report.count, 2);
    expect(report.previousCents, 0);
    expect(report.changePercent, isNull);
    expect(report.trend.length, 6);
    expect(report.trend.take(5).every((month) => month.cents == 0), isTrue);
  });

  test(
      'payers are grouped by identity, including homonyms and different creators',
      () {
    final report = GroupReport.calculate(
        groupId: 'g',
        period: ReportPeriod(DateTime(2026, 11), DateTime(2026, 11, 11)),
        rows: [
          row('a', '2026-11-01', 10, payer: 'b', payerName: '  Luca  '),
          row('b', '2026-11-02', 20, payer: 'c', payerName: 'Luca'),
          row('c', '2026-11-03', 5, payer: 'b', payerName: 'Luca'),
          row('unknown', '2026-11-04', 3, payer: 'd'),
        ]);
    expect(report.payers.length, 3);
    expect(report.payers.singleWhere((p) => p.id == 'b').cents, 1500);
    expect(
        report.payers.singleWhere((p) => p.id == 'd').label, 'Non specificato');
    expect(report.payers.where((p) => p.label == 'Anna'), isEmpty);
  });

  test(
      'a historical payer name without id cannot reassign the creator payments',
      () {
    final report = GroupReport.calculate(
        groupId: 'g',
        period: ReportPeriod(DateTime(2026, 11), DateTime(2026, 11, 11)),
        rows: [
          row('legacy', '2026-11-01', 100,
              creatorName: 'Anna', payerName: 'Bruno'),
          row('creator', '2026-11-02', 50,
              creatorName: 'Anna', payer: 'a', payerName: 'Anna'),
          row('fallback', '2026-11-03', 10, creatorName: 'Anna'),
        ]);
    expect(report.payers.singleWhere((p) => p.id == 'a').cents, 6000);
    expect(report.payers.singleWhere((p) => p.label == 'Bruno').cents, 10000);
  });

  test('an empty selected month keeps historical spending in six-month trend',
      () {
    final report = GroupReport.calculate(
        groupId: 'g',
        period: ReportPeriod(DateTime(2026, 11), DateTime(2026, 11, 11)),
        rows: [row('october', '2026-10-10', 15)]);
    expect(report.count, 0);
    expect(report.totalCents, 0);
    expect(report.averageCents, 0);
    expect(report.trend[4].cents, 1500);
    expect(report.trend.last.cents, 0);
    expect(report.largestExpense, isNull);
  });
}
