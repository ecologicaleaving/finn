import 'package:flutter_test/flutter_test.dart';
import 'package:family_expense_tracker/features/reports/domain/group_report.dart';
import 'package:family_expense_tracker/features/reports/domain/member_balance.dart';

ReportExpense movement(String id, int cents,
        {String? payer = 'A',
        String? category = 'Cibo',
        String? categoryId = 'food',
        String? type,
        String status = 'none',
        DateTime? refundedAt,
        String creator = 'A',
        bool shared = true,
        String group = 'g',
        DateTime? date}) =>
    ReportExpense(
      id: id,
      groupId: group,
      date: date ?? DateTime.utc(2026, 11, 2),
      cents: cents,
      createdBy: creator,
      paidBy: payer,
      paidByName: 'Alex',
      createdByName: 'Alex',
      categoryId: categoryId,
      categoryName: category,
      transactionType: type,
      reimbursementStatus: status,
      reimbursedAt: refundedAt,
      isGroupExpense: shared,
    );
GroupReport report(List<ReportExpense> rows,
        {ReportMode mode = ReportMode.month}) =>
    GroupReport.calculate(
        groupId: 'g',
        period: ReportPeriod(DateTime(2026, 11), DateTime(2026, 11, 12),
            mode: mode),
        rows: rows);
MemberBalance calculate(GroupReport value,
        {String first = 'A',
        String second = 'G',
        Map<String, BalanceAttribution> assignments = const {}}) =>
    MemberBalance.calculate(
        report: value,
        firstId: first,
        secondId: second,
        attributions: assignments);

void main() {
  test(
      'user example 100/100 refund40 to G requires explicit confirmation and gives G to A20',
      () {
    final value = report([
      movement('a', 10000),
      movement('g', 10000, payer: 'G'),
      movement('old', 4000,
          payer: 'A',
          status: 'reimbursed',
          date: DateTime.utc(2020),
          refundedAt: DateTime(2026, 11, 5, 10).toUtc()),
    ]);
    final pending = calculate(value);
    expect(pending.isComplete, isFalse);
    expect(pending.people['A']!.deltaCents, isNull);
    expect(pending.transfer, isNull);
    final refund = pending.events
        .singleWhere((e) => e.kind == BalanceEventKind.reimbursement);
    final balance = calculate(value, assignments: {
      refund.key: BalanceAttribution.forEvent('G', refund),
    });
    expect(balance.people['A']!.netCents, 10000);
    expect(balance.people['G']!.netCents, 6000);
    expect(balance.people['A']!.targetCents, 8000);
    expect(balance.people['G']!.targetCents, 8000);
    expect(balance.people['A']!.deltaCents, 2000);
    expect(balance.people['G']!.deltaCents, -2000);
    expect(balance.transfer!.fromId, 'G');
    expect(balance.transfer!.toId, 'A');
    expect(balance.transfer!.cents, 2000);
  });

  test(
      '120/80 gives compensation20, not the40 gap; view order never changes recipient',
      () {
    final value =
        report([movement('a', 12000), movement('g', 8000, payer: 'G')]);
    for (final balance in [
      calculate(value),
      calculate(value, first: 'G', second: 'A')
    ]) {
      expect(balance.transfer!.fromId, 'G');
      expect(balance.transfer!.toId, 'A');
      expect(balance.transfer!.cents, 2000);
    }
  });

  test(
      'opposite categories compensate in total but remain individually unbalanced',
      () {
    final balance = calculate(report([
      movement('food-a', 12000),
      movement('food-g', 8000, payer: 'G'),
      movement('home-a', 8000, categoryId: 'home', category: 'Casa'),
      movement('home-g', 12000,
          payer: 'G', categoryId: 'home', category: 'Casa'),
    ]));
    expect(balance.people['A']!.deltaCents, 0);
    expect(balance.transfer, isNull);
    expect(balance.offsettingCategoryCount, 2);
    expect(balance.categories.map((c) => c.people['A']!.deltaCents),
        containsAll([2000, -2000]));
  });

  test(
      'missing explicit paidBy and outsiders block their category and total even when unknown net is zero',
      () {
    final value = report([
      movement('known-a', 12000),
      movement('known-g', 8000, payer: 'G'),
      movement('unknown-paid', 10000,
          payer: null, creator: 'A', categoryId: 'unknown'),
      movement('unknown-income', 10000,
          payer: null, creator: 'G', type: 'income', categoryId: 'unknown'),
      movement('third', 5000, payer: 'child', categoryId: 'third'),
    ]);
    final balance = calculate(value);
    expect(balance.unassigned.length, 3);
    expect(balance.isComplete, isFalse);
    expect(balance.people.values.every((p) => p.deltaCents == null), isTrue);
    final complete = balance.categories.singleWhere((c) => c.key == 'id:food');
    expect(complete.isComplete, isTrue);
    expect(complete.transfer!.cents, 2000);
    final unknown =
        balance.categories.singleWhere((c) => c.key == 'id:unknown');
    expect(unknown.netTotalCents, 0);
    expect(unknown.isComplete, isFalse);
    final overrides = {
      for (final event in balance.unassigned)
        event.key: BalanceAttribution.forEvent('G', event)
    };
    expect(calculate(value, assignments: overrides).isComplete, isTrue);
  });

  test(
      'income-only categories keep original classification; missing category is not real Altro',
      () {
    final balance = calculate(report([
      movement('support', 30000,
          payer: 'G',
          type: 'income',
          categoryId: 'support',
          category: 'Assegni'),
      movement('daughters', 10000, categoryId: 'daughters', category: 'Figlie'),
      movement('none', 100, categoryId: null, category: null),
      movement('other', 100, categoryId: null, category: 'Altro'),
    ]));
    expect(balance.categories.length, 4);
    expect(
        balance.categories
            .singleWhere((c) => c.key == 'id:support')
            .people['G']!
            .incomeCents,
        30000);
    expect(
        balance.categories
            .singleWhere((c) => c.key == 'id:daughters')
            .people['G']!
            .incomeCents,
        0);
    expect(balance.categories.singleWhere((c) => c.key == 'none').label,
        'Senza categoria');
    expect(balance.categories.singleWhere((c) => c.key == 'name:Altro').label,
        'Altro');
    expect(balance.netTotalCents, -19800);
  });

  test(
      'signed rounding reconciles category targets and deltas for odd and negative cents',
      () {
    for (var a = -3; a <= 3; a++) {
      for (var b = -3; b <= 3; b++) {
        for (var c = -3; c <= 3; c++) {
          final value = report([
            movement('a', a, categoryId: 'a'),
            movement('b', b, payer: 'G', categoryId: 'b'),
            movement('c', c, categoryId: 'c')
          ]);
          final normal = calculate(value);
          final swapped = calculate(value, first: 'G', second: 'A');
          expect(normal.isComplete, isTrue);
          expect(normal.people['A']!.targetCents, ((a + b + c) / 2).ceil());
          expect(normal.people['G']!.targetCents,
              (a + b + c) - ((a + b + c) / 2).ceil());
          for (final id in ['A', 'G']) {
            expect(
                normal.categories
                    .fold<int>(0, (s, cat) => s + cat.people[id]!.targetCents),
                normal.people[id]!.targetCents);
            expect(
                normal.categories
                    .fold<int>(0, (s, cat) => s + cat.people[id]!.deltaCents!),
                normal.people[id]!.deltaCents);
            expect(normal.people[id]!.targetCents,
                swapped.people[id]!.targetCents);
          }
          expect(normal.people.values.fold<int>(0, (s, p) => s + p.deltaCents!),
              0);
          expect(normal.transfer?.fromId, swapped.transfer?.fromId);
          expect(normal.transfer?.toId, swapped.transfer?.toId);
          expect(normal.transfer?.cents, swapped.transfer?.cents);
        }
      }
    }
  });

  test(
      'surplus with no expenses still has signed targets and a meaningful direction',
      () {
    final balance = calculate(report([
      movement('a-income', 7000, type: 'income'),
      movement('g-income', 3000, type: 'income', payer: 'G')
    ]));
    expect(balance.netTotalCents, -10000);
    expect(balance.people['A']!.targetCents, -5000);
    expect(balance.people['A']!.deltaCents, -2000);
    expect(balance.transfer!.fromId, 'A');
    expect(balance.transfer!.toId, 'G');
    expect(balance.transfer!.cents, 2000);
  });

  test(
      'attributions are event-specific and rejected after material source changes',
      () {
    final initial = report([
      movement('missing', 100, payer: null),
      movement('refund', 4000,
          payer: 'G',
          status: 'reimbursed',
          refundedAt: DateTime(2026, 11, 5).toUtc())
    ]);
    final events = MemberBalance.eventsFrom(initial);
    final missing = events.singleWhere((e) => e.key == 'expense:missing');
    final override = BalanceAttribution.forEvent('A', missing);
    final base = calculate(initial, assignments: {missing.key: override});
    expect(base.unassigned.single.kind, BalanceEventKind.reimbursement);
    final updated = report([movement('missing', 200, payer: null)]);
    expect(
        calculate(updated, assignments: {missing.key: override})
            .unassigned
            .length,
        1);
    expect(MemberBalance.snapshotOf(initial),
        isNot(MemberBalance.snapshotOf(updated)));
    final reordered = report(initial.expenses.reversed.toList());
    expect(MemberBalance.eventsFrom(reordered).map((e) => e.key),
        orderedEquals(MemberBalance.eventsFrom(initial).map((e) => e.key)));
  });

  test(
      'same display names remain separate, pending and personal income never become credits',
      () {
    final value = report([
      movement('a', 12000),
      movement('g', 8000, payer: 'G', status: 'reimbursable'),
      movement('personal', 100000, payer: 'G', type: 'income', shared: false),
      movement('other-group', 100000,
          payer: 'G', type: 'income', group: 'other')
    ]);
    final balance = calculate(value);
    expect(balance.people.length, 2);
    expect(balance.people['A']!.paidCents, 12000);
    expect(balance.people['G']!.paidCents, 8000);
    expect(balance.people['G']!.receivedCents, 0);
    expect(
        () => calculate(value, first: 'A', second: 'A'), throwsArgumentError);
  });
}
