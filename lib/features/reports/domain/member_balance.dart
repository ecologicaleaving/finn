import 'dart:convert';

import 'group_report.dart';

enum BalanceEventKind { expense, income, reimbursement }

class BalanceEvent {
  const BalanceEvent(this.key, this.kind, this.source, this.date);
  final String key;
  final BalanceEventKind kind;
  final ReportExpense source;
  final DateTime date;
  int get cents => source.cents;
  int get netCents => kind == BalanceEventKind.expense ? cents : -cents;
  String? get explicitPersonId =>
      source.paidBy?.trim().isNotEmpty == true ? source.paidBy!.trim() : null;
  String get categoryLabel => source.categoryName?.trim().isNotEmpty == true
      ? source.categoryName!.trim()
      : 'Senza categoria';
  String get categoryKey => source.categoryId?.trim().isNotEmpty == true
      ? 'id:${source.categoryId!.trim()}'
      : source.categoryName?.trim().isNotEmpty == true
          ? 'name:$categoryLabel'
          : 'none';
  String get fingerprint => jsonEncode([
        key,
        kind.name,
        cents,
        categoryKey,
        categoryLabel,
        explicitPersonId,
        source.groupId,
        source.createdBy,
        source.date.toIso8601String(),
        date.toIso8601String(),
        source.reimbursementStatus,
        source.reimbursedAt?.toIso8601String(),
        source.notes,
        source.merchant,
        source.paidByName,
      ]);
}

/// Local analysis only. A changed movement cannot reuse an old attribution.
class BalanceAttribution {
  const BalanceAttribution(this.personId, this.fingerprint);
  factory BalanceAttribution.forEvent(String personId, BalanceEvent event) =>
      BalanceAttribution(personId, event.fingerprint);
  final String personId, fingerprint;
}

class PersonBalance {
  const PersonBalance(
      {required this.personId,
      required this.paidCents,
      required this.incomeCents,
      required this.refundCents,
      required this.targetCents,
      required this.deltaCents});
  final String personId;
  final int paidCents, incomeCents, refundCents, targetCents;
  final int? deltaCents;
  int get receivedCents => incomeCents + refundCents;
  int get netCents => paidCents - receivedCents;
}

class BalanceTransfer {
  const BalanceTransfer(this.fromId, this.toId, this.cents);
  final String fromId, toId;
  final int cents;
}

BalanceTransfer? _transfer(Map<String, PersonBalance> people) {
  final first = people.values.first;
  final second = people.values.last;
  final delta = first.deltaCents;
  if (delta == null || delta == 0) return null;
  return delta > 0
      ? BalanceTransfer(second.personId, first.personId, delta)
      : BalanceTransfer(first.personId, second.personId, -delta);
}

class CategoryBalance {
  const CategoryBalance(
      this.key, this.label, this.netTotalCents, this.people, this.unassigned);
  final String key, label;
  final int netTotalCents;
  final Map<String, PersonBalance> people;
  final List<BalanceEvent> unassigned;
  bool get isComplete => unassigned.isEmpty;
  BalanceTransfer? get transfer => _transfer(people);
}

class _Amounts {
  int paid = 0, income = 0, refund = 0;
  void add(BalanceEvent event) {
    switch (event.kind) {
      case BalanceEventKind.expense:
        paid += event.cents;
      case BalanceEventKind.income:
        income += event.cents;
      case BalanceEventKind.reimbursement:
        refund += event.cents;
    }
  }

  PersonBalance finish(String id, int target, bool complete) => PersonBalance(
      personId: id,
      paidCents: paid,
      incomeCents: income,
      refundCents: refund,
      targetCents: target,
      deltaCents: complete ? paid - income - refund - target : null);
}

class MemberBalance {
  MemberBalance._(this.people, this.categories, this.events, this.unassigned,
      this.netTotalCents);
  final Map<String, PersonBalance> people;
  final List<CategoryBalance> categories;
  final List<BalanceEvent> events, unassigned;
  final int netTotalCents;
  bool get isComplete => unassigned.isEmpty;
  BalanceTransfer? get transfer => _transfer(people);
  int get offsettingCategoryCount => categories
      .where((category) =>
          category.isComplete && category.people.values.first.deltaCents != 0)
      .length;

  static List<BalanceEvent> eventsFrom(GroupReport report) => [
        for (final row in report.expenses)
          BalanceEvent(
              'expense:${row.id}', BalanceEventKind.expense, row, row.date),
        for (final inflow in report.inflows)
          BalanceEvent(
              inflow.id,
              inflow.kind == ReportInflowKind.income
                  ? BalanceEventKind.income
                  : BalanceEventKind.reimbursement,
              inflow.expense,
              inflow.date),
      ]..sort((a, b) => a.key.compareTo(b.key));

  static String snapshotOf(GroupReport report) => jsonEncode([
        report.period.mode.name,
        report.period.start.toIso8601String(),
        report.period.end.toIso8601String(),
        for (final event in eventsFrom(report)) event.fingerprint,
      ]);

  static String? assignedPerson(BalanceEvent event, Iterable<String> pair,
      Map<String, BalanceAttribution> attributions) {
    final local = attributions[event.key];
    if (local != null &&
        local.fingerprint == event.fingerprint &&
        pair.contains(local.personId)) return local.personId;
    // A refund's original payer never proves who received that refund.
    if (event.kind != BalanceEventKind.reimbursement &&
        pair.contains(event.explicitPersonId)) return event.explicitPersonId;
    return null;
  }

  factory MemberBalance.calculate(
      {required GroupReport report,
      required String firstId,
      required String secondId,
      Map<String, BalanceAttribution> attributions = const {}}) {
    if (firstId.trim().isEmpty ||
        secondId.trim().isEmpty ||
        firstId == secondId) {
      throw ArgumentError('Scegli due persone distinte.');
    }
    final pair = [firstId, secondId]..sort();
    final events = eventsFrom(report);
    final grouped = <String, List<BalanceEvent>>{};
    for (final event in events) {
      grouped.putIfAbsent(event.categoryKey, () => []).add(event);
    }
    final keys = grouped.keys.toList()..sort();
    int categoryTotal(String key) =>
        grouped[key]!.fold(0, (s, e) => s + e.netCents);
    int floorHalf(int value) =>
        value < 0 && value.isOdd ? value ~/ 2 - 1 : value ~/ 2;
    final total = events.fold<int>(0, (s, e) => s + e.netCents);
    final firstTotalTarget = -floorHalf(-total);
    var extra = firstTotalTarget -
        keys.fold<int>(0, (s, key) => s + floorHalf(categoryTotal(key)));
    final categories = <CategoryBalance>[];
    final unassigned = <BalanceEvent>[];
    final totalAmounts = {for (final id in pair) id: _Amounts()};
    for (final key in keys) {
      final categoryEvents = grouped[key]!;
      final subtotal = categoryTotal(key);
      var firstTarget = floorHalf(subtotal);
      if (subtotal.isOdd && extra > 0) {
        firstTarget++;
        extra--;
      }
      final amounts = {for (final id in pair) id: _Amounts()};
      final missing = <BalanceEvent>[];
      for (final event in categoryEvents) {
        final person = assignedPerson(event, pair, attributions);
        if (person == null) {
          if (event.cents != 0) missing.add(event);
        } else {
          amounts[person]!.add(event);
          totalAmounts[person]!.add(event);
        }
      }
      unassigned.addAll(missing);
      categories.add(CategoryBalance(
          key,
          categoryEvents.first.categoryLabel,
          subtotal,
          {
            pair.first: amounts[pair.first]!
                .finish(pair.first, firstTarget, missing.isEmpty),
            pair.last: amounts[pair.last]!
                .finish(pair.last, subtotal - firstTarget, missing.isEmpty),
          },
          missing));
    }
    return MemberBalance._({
      pair.first: totalAmounts[pair.first]!
          .finish(pair.first, firstTotalTarget, unassigned.isEmpty),
      pair.last: totalAmounts[pair.last]!
          .finish(pair.last, total - firstTotalTarget, unassigned.isEmpty),
    }, categories, events, unassigned, total);
  }
}
