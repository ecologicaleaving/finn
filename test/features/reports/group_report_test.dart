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
  String status = 'reimbursed',
  String? reimbursedAt,
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
      'reimbursement_status': status,
      'reimbursed_at': reimbursedAt,
    });

void main() {
  test(
      'group balance is income plus received refunds minus gross, pending excluded',
      () {
    final refund = row('old-refund', '2025-01-02', 100,
        reimbursedAt: DateTime(2026, 11, 2, 10).toUtc().toIso8601String());
    final report = GroupReport.calculate(
        groupId: 'g',
        period: ReportPeriod(DateTime(2026, 11), DateTime(2026, 11, 12)),
        rows: [
          row('gross', '2026-11-01', 950, status: 'none'),
          row('pending', '2026-11-03', 50, status: 'reimbursable'),
          row('benefit', '2026-11-04', 300,
              type: 'income',
              category: 'Aiuti statali',
              payer: 'giovanna',
              payerName: 'Giovanna'),
          refund,
          refund,
        ]);
    expect(report.totalCents, 100000);
    expect(report.incomeCents, 30000);
    expect(report.receivedReimbursementCents, 10000);
    expect(report.pendingReimbursementCents, 5000);
    expect(report.balanceCents, -60000);
    expect(report.count, 2);
    expect(report.payers.fold<int>(0, (s, p) => s + p.cents), 100000);
    expect(report.incomeCategories.single.label, 'Aiuti statali');
    expect(report.incomePeople.single.id, 'giovanna');
    expect(report.inflows.length, 2);
    expect(report.trend.last.inflowCents, 40000);
  });

  test(
      'income cannot also become a refund and unrelated or future movements are excluded',
      () {
    final report = GroupReport.calculate(
        groupId: 'g',
        period: ReportPeriod(DateTime(2026, 11), DateTime(2026, 11, 12)),
        rows: [
          row('income', '2026-11-01', 10,
              type: 'income',
              reimbursedAt: DateTime(2026, 11, 2).toUtc().toIso8601String()),
          row('personal', '2026-11-01', 500, type: 'income', shared: false),
          row('other-group', '2026-11-01', 500, type: 'income', group: 'other'),
          row('unknown', '2026-11-01', 500, type: 'other'),
          row('future-income', '2026-11-13', 500, type: 'income'),
          row('future-refund', '2024-01-01', 500,
              reimbursedAt: DateTime(2026, 11, 13).toUtc().toIso8601String()),
          row('missing-timestamp', '2024-01-01', 500),
        ]);
    expect(report.totalCents, 0);
    expect(report.incomeCents, 1000);
    expect(report.receivedReimbursementCents, 0);
    expect(report.balanceCents, 1000);
    expect(report.pendingReimbursementCents, 0);
    expect(report.inflows.single.kind, ReportInflowKind.income);
  });

  test('refund periods use local calendar days and exclusive next midnight',
      () {
    final period = ReportPeriod(DateTime(2026, 11), DateTime(2026, 12, 2));
    String instant(int month, int day, int hour, int minute) =>
        DateTime(2026, month, day, hour, minute).toUtc().toIso8601String();
    final report = GroupReport.calculate(groupId: 'g', period: period, rows: [
      row('first', '2024-01-01', 10, reimbursedAt: instant(11, 1, 0, 0)),
      row('last', '2024-01-01', 20, reimbursedAt: instant(11, 30, 23, 59)),
      row('before', '2024-01-01', 100, reimbursedAt: instant(10, 31, 23, 59)),
      row('after', '2024-01-01', 100, reimbursedAt: instant(12, 1, 0, 0)),
    ]);
    expect(report.receivedReimbursementCents, 3000);
    expect(report.inflows.map((entry) => entry.expense.id),
        containsAll(['first', 'last']));
    final utcMidnight = DateTime.utc(2026, 11, 1);
    final local = utcMidnight.toLocal();
    expect(reportTimestampDay(utcMidnight),
        DateTime.utc(local.year, local.month, local.day));
    expect(period.localEndExclusiveUtc, DateTime(2026, 12, 1).toUtc());
    final dst = ReportPeriod(DateTime(2026, 3), DateTime(2026, 4, 2));
    expect(dst.localEndExclusiveUtc, DateTime(2026, 4, 1).toUtc());
  });

  test(
      'duplicate ID is counted once but a separate income is never guessed to be the same refund',
      () {
    final expense = row('expense', '2026-11-01', 100,
        reimbursedAt: DateTime(2026, 11, 2).toUtc().toIso8601String());
    final report = GroupReport.calculate(
        groupId: 'g',
        period: ReportPeriod(DateTime(2026, 11), DateTime(2026, 11, 12)),
        rows: [
          expense,
          expense,
          row('separate-income', '2026-11-02', 100, type: 'income'),
        ]);
    expect(report.count, 1);
    expect(report.totalCents, 10000);
    expect(report.receivedReimbursementCents, 10000);
    expect(report.incomeCents, 10000);
    expect(report.balanceCents, 10000);
    expect(report.inflows.length, 2);
  });

  test(
      'annual balance and trend include old expenses refunded in the selected year',
      () {
    final report = GroupReport.calculate(
        groupId: 'g',
        period: ReportPeriod(DateTime(2026), DateTime(2026, 11, 12),
            mode: ReportMode.year),
        rows: [
          row('jan-income', '2026-01-01', '0.10', type: 'income'),
          row('nov-income', '2026-11-01', '0.20', type: 'income'),
          row('old-expense', '2020-02-01', '12.34',
              reimbursedAt: DateTime(2026, 7, 5).toUtc().toIso8601String()),
        ]);
    expect(report.totalCents, 0);
    expect(report.incomeCents, 30);
    expect(report.receivedReimbursementCents, 1234);
    expect(report.balanceCents, 1264);
    expect(report.trend.fold<int>(0, (s, m) => s + m.inflowCents), 1264);
    expect(report.trend[6].reimbursementCents, 1234);
    expect(report.trend.last.future, isTrue);
    expect(report.trend.last.inflowCents, 0);
  });

  test(
      'current annual report uses year-to-date and calendar-aligned comparison',
      () {
    final period = ReportPeriod(DateTime(2026), DateTime(2026, 11, 12),
        mode: ReportMode.year);
    expect(period.start, DateTime.utc(2026));
    expect(period.end, DateTime.utc(2026, 11, 12));
    expect(period.previousStart, DateTime.utc(2025));
    expect(period.previousEnd, DateTime.utc(2025, 11, 12));
    expect(period.historyStart, DateTime.utc(2025));
    final report = GroupReport.calculate(groupId: 'g', period: period, rows: [
      row('jan', '2026-01-01', 10),
      row('june', '2026-06-10', 20),
      row('nov', '2026-11-12', 30),
      row('future', '2026-12-01', 999),
      row('previous', '2025-11-12', 40),
      row('after-comparison', '2025-11-13', 999),
    ]);
    expect(report.totalCents, 6000);
    expect(report.count, 3);
    expect(report.previousCents, 4000);
    expect(report.trend.length, 12);
    expect(report.trend[1].cents, 0);
    expect(report.trend[1].future, isFalse);
    expect(report.trend[10].partial, isTrue);
    expect(report.trend[11].future, isTrue);
    expect(report.busiestMonth!.month, DateTime.utc(2026, 11));
    expect(report.categories.single.cents, 6000);
  });

  test(
      '29 February annual comparison excludes extra day from both comparison totals only',
      () {
    final period = ReportPeriod(DateTime(2024), DateTime(2024, 2, 29),
        mode: ReportMode.year);
    expect(period.end, DateTime.utc(2024, 2, 29));
    expect(period.comparisonEnd, DateTime.utc(2024, 2, 28));
    expect(period.previousEnd, DateTime.utc(2023, 2, 28));
    final report = GroupReport.calculate(groupId: 'g', period: period, rows: [
      row('feb28', '2024-02-28', 10),
      row('leap', '2024-02-29', 20),
      row('previous', '2023-02-28', 5),
    ]);
    expect(report.totalCents, 3000);
    expect(report.comparisonCents, 1000);
    expect(report.previousCents, 500);
    final march = ReportPeriod(DateTime(2024), DateTime(2024, 3, 1),
        mode: ReportMode.year);
    expect(march.previousEnd, DateTime.utc(2023, 3, 1));
    expect(march.comparisonEnd, DateTime.utc(2024, 3, 1));
  });

  test(
      'historical annual reports include complete years and zero comparison stays safe',
      () {
    final period = ReportPeriod(DateTime(2024), DateTime(2026, 11, 12),
        mode: ReportMode.year);
    expect(period.end, DateTime.utc(2024, 12, 31));
    expect(period.previousEnd, DateTime.utc(2023, 12, 31));
    final report = GroupReport.calculate(groupId: 'g', period: period, rows: [
      row('first', '2024-01-01', 1),
      row('leap', '2024-02-29', 2),
      row('last', '2024-12-31', 3),
      row('outside', '2025-01-01', 999),
    ]);
    expect(report.totalCents, 600);
    expect(report.averageCents, 200);
    expect(report.changePercent, isNull);
    expect(
        report.trend.every((month) => !month.future && !month.partial), isTrue);
    expect(report.largestExpense!.id, 'last');
  });

  test(
      'member payment projection preserves zero members, homonyms and historic identities',
      () {
    final report = GroupReport.calculate(
        groupId: 'g',
        period: ReportPeriod(DateTime(2026), DateTime(2026, 11, 12),
            mode: ReportMode.year),
        rows: [
          row('a', '2026-01-01', 30, payer: 'a', payerName: 'Vecchio nome'),
          row('b', '2026-02-01', 20, payer: 'b', payerName: 'Luca'),
          row('old', '2026-03-01', 40,
              payer: 'former', payerName: 'Ex componente'),
          row('legacy', '2026-04-01', 10, payerName: 'Nome storico'),
        ]);
    final payments = report.memberPayments(const [
      ReportMember('a', 'Luca'),
      ReportMember('b', 'Luca'),
      ReportMember('zero', 'Giulia')
    ]);
    expect(payments.length, 5);
    expect(payments.where((payment) => payment.label == 'Luca').length, 2);
    expect(payments.singleWhere((payment) => payment.id == 'zero').cents, 0);
    expect(payments.singleWhere((payment) => payment.id == 'zero').count, 0);
    expect(
        payments
            .singleWhere((payment) => payment.id == 'former')
            .isCurrentMember,
        isFalse);
    expect(
        payments.singleWhere((payment) => payment.id == 'legacy:legacy').cents,
        1000);
    expect(payments.fold<int>(0, (s, p) => s + p.cents), report.totalCents);
    expect(payments.fold<int>(0, (s, p) => s + p.count), report.count);
    expect(payments.fold<int>(0, (s, p) => s + p.shareTenths), 1000);
    expect(
        payments.singleWhere((payment) => payment.id == 'a').sharePercent, 30);
  });

  test(
      'displayed percentage tenths total 100 for thirds, and zero total gives zero',
      () {
    final period = ReportPeriod(DateTime(2026), DateTime(2026, 11, 12),
        mode: ReportMode.year);
    final report = GroupReport.calculate(groupId: 'g', period: period, rows: [
      row('a', '2026-01-01', 1, payer: 'a'),
      row('b', '2026-01-01', 1, payer: 'b'),
      row('c', '2026-01-01', 1, payer: 'c'),
    ]);
    final payments = report.memberPayments(const []);
    expect(payments.map((p) => p.shareTenths), containsAll([334, 333, 333]));
    expect(payments.fold<int>(0, (s, p) => s + p.shareTenths), 1000);
    final empty = GroupReport.calculate(groupId: 'g', period: period, rows: []);
    expect(
        empty
            .memberPayments(const [ReportMember('a', 'Anna')])
            .single
            .sharePercent,
        0);
  });

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
