import '../../../core/utils/date_only.dart';

DateTime reportDay(DateTime value) => _calendarDate(toServerDate(value));
DateTime _calendarDate(String text) {
  final date = DateTime.parse(text);
  return DateTime.utc(date.year, date.month, date.day);
}

DateTime reportMonth(DateTime value, [int offset = 0]) =>
    DateTime.utc(value.year, value.month + offset);
DateTime monthEnd(DateTime value) =>
    DateTime.utc(value.year, value.month + 1, 0);

/// Monetary database values are converted once; every sum uses integer cents.
int reportCents(Object amount) {
  final text = amount.toString();
  final match = RegExp(r'^(-?)(\d+)(?:\.(\d+))?$').firstMatch(text);
  if (match == null) throw FormatException('Importo non valido', text);
  final fraction = (match[3] ?? '').padRight(3, '0');
  final cents = int.parse(match[2]!) * 100 +
      int.parse(fraction.substring(0, 2)) +
      (int.parse(fraction[2]) >= 5 ? 1 : 0);
  return match[1] == '-' ? -cents : cents;
}

enum ReportMode { month, year }

class ReportPeriod {
  ReportPeriod(DateTime selected, DateTime now, {this.mode = ReportMode.month})
      : today = reportDay(now),
        month = reportMonth(selected).isAfter(reportMonth(now))
            ? reportMonth(now)
            : reportMonth(selected);
  final DateTime month;
  final DateTime today;
  final ReportMode mode;
  bool get isYear => mode == ReportMode.year;
  DateTime get start => isYear ? DateTime.utc(month.year) : month;
  DateTime get previousStart =>
      isYear ? DateTime.utc(start.year - 1) : reportMonth(start, -1);
  bool get isCurrent =>
      isYear ? start.year == today.year : month == reportMonth(today);
  DateTime get end => isCurrent
      ? today
      : (isYear ? DateTime.utc(start.year + 1, 1, 0) : monthEnd(start));
  DateTime get previousMonth => reportMonth(month, -1);
  int get comparisonDays => isCurrent
      ? (today.day < monthEnd(previousMonth).day
          ? today.day
          : monthEnd(previousMonth).day)
      : monthEnd(month).day;
  DateTime get comparisonEnd {
    if (!isCurrent) return end;
    if (isYear) return DateTime.utc(start.year, today.month, previousEnd.day);
    return DateTime.utc(month.year, month.month, comparisonDays);
  }

  DateTime get previousEnd {
    if (isYear) {
      if (!isCurrent) return DateTime.utc(start.year, 1, 0);
      final validDay =
          monthEnd(DateTime.utc(previousStart.year, today.month)).day;
      return DateTime.utc(previousStart.year, today.month,
          today.day < validDay ? today.day : validDay);
    }
    return isCurrent
        ? DateTime.utc(previousMonth.year, previousMonth.month, comparisonDays)
        : monthEnd(previousMonth);
  }

  DateTime get historyStart => isYear ? previousStart : reportMonth(month, -5);
}

class ReportExpense {
  const ReportExpense({
    required this.id,
    required this.groupId,
    required this.date,
    required this.cents,
    required this.createdBy,
    this.isGroupExpense = true,
    this.transactionType,
    this.categoryId,
    this.categoryName,
    this.paidBy,
    this.paidByName,
    this.createdByName,
    this.notes,
    this.merchant,
  });
  factory ReportExpense.fromJson(Map<String, dynamic> json) {
    final category = json['category_name'];
    return ReportExpense(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      date: _calendarDate(serverDateFromPayload(json['date'] as String)),
      cents: reportCents(json['amount'] as Object),
      createdBy: json['created_by'] as String? ?? '',
      isGroupExpense: json['is_group_expense'] == true,
      transactionType: json['transaction_type'] as String?,
      categoryId: json['category_id'] as String?,
      categoryName:
          category is Map ? category['name'] as String? : category as String?,
      paidBy: json['paid_by'] as String?,
      paidByName: json['paid_by_name'] as String?,
      createdByName: json['created_by_name'] as String?,
      notes: json['notes'] as String?,
      merchant: json['merchant'] as String?,
    );
  }
  final String id, groupId, createdBy;
  final DateTime date;
  final int cents;
  final bool isGroupExpense;
  final String? transactionType, categoryId, categoryName;
  final String? paidBy, paidByName, createdByName, notes, merchant;
  String get category => _nonblank(categoryName) ?? 'Altro';
  bool get _unlinkedPayer =>
      _nonblank(paidBy) == null &&
      _nonblank(paidByName) != null &&
      _nonblank(paidByName) != _nonblank(createdByName);
  String get payerId =>
      _nonblank(paidBy) ??
      (_unlinkedPayer ? 'legacy:$id' : _nonblank(createdBy)) ??
      'unknown:$id';
  String get payerName =>
      _nonblank(paidByName) ??
      ((_nonblank(paidBy) == null || paidBy!.trim() == createdBy.trim())
          ? _nonblank(createdByName)
          : null) ??
      'Non specificato';
  String get title => _nonblank(notes) ?? _nonblank(merchant) ?? category;
}

String? _nonblank(String? value) =>
    value?.trim().isNotEmpty == true ? value!.trim() : null;

class ReportSlice {
  const ReportSlice(this.id, this.label, this.cents, this.count);
  final String id, label;
  final int cents, count;
}

class ReportMonthTotal {
  const ReportMonthTotal(this.month, this.cents, this.partial,
      {this.future = false, this.count = 0});
  final DateTime month;
  final int cents;
  final bool partial;
  final bool future;
  final int count;
}

class ReportMember {
  const ReportMember(this.id, this.name);
  final String id, name;
}

class ReportPayment extends ReportSlice {
  const ReportPayment(super.id, super.label, super.cents, super.count,
      {required this.isCurrentMember, this.shareTenths = 0});
  final bool isCurrentMember;
  final int shareTenths;
  double get sharePercent => shareTenths / 10;
}

class GroupReport {
  GroupReport._(
      this.period,
      this.expenses,
      this.totalCents,
      this.comparisonCents,
      this.previousCents,
      this.categories,
      this.payers,
      this.days,
      this.trend,
      this.largestExpense);

  factory GroupReport.calculate(
      {required String groupId,
      required ReportPeriod period,
      required List<ReportExpense> rows}) {
    final eligible = rows
        .where((e) =>
            e.groupId == groupId &&
            e.isGroupExpense &&
            (e.transactionType == null || e.transactionType == 'expense') &&
            !e.date.isBefore(period.historyStart) &&
            !e.date.isAfter(period.end))
        .toList();
    List<ReportExpense> between(DateTime start, DateTime end) => eligible
        .where((e) => !e.date.isBefore(start) && !e.date.isAfter(end))
        .toList();
    int sum(Iterable<ReportExpense> values) =>
        values.fold(0, (s, e) => s + e.cents);
    final current = between(period.start, period.end)
      ..sort((a, b) => b.cents.compareTo(a.cents));
    List<ReportSlice> slices(String Function(ReportExpense) key,
        String Function(ReportExpense) label) {
      final groups = <String, List<ReportExpense>>{};
      for (final row in current) {
        groups.putIfAbsent(key(row), () => []).add(row);
      }
      return groups.entries
          .map((entry) => ReportSlice(entry.key, label(entry.value.first),
              sum(entry.value), entry.value.length))
          .toList()
        ..sort((a, b) => b.cents.compareTo(a.cents));
    }

    return GroupReport._(
      period,
      current,
      sum(current),
      sum(between(period.start, period.comparisonEnd)),
      sum(between(period.previousStart, period.previousEnd)),
      slices((e) => e.categoryId ?? e.category, (e) => e.category),
      slices((e) => e.payerId, (e) => e.payerName),
      slices((e) => toServerDate(e.date), (e) => toServerDate(e.date)),
      List.generate(period.isYear ? 12 : 6, (i) {
        final month = period.isYear
            ? DateTime.utc(period.start.year, i + 1)
            : reportMonth(period.month, i - 5);
        final future =
            period.isCurrent && month.isAfter(reportMonth(period.today));
        final monthRows = between(
            month,
            month == reportMonth(period.today) && period.isCurrent
                ? period.end
                : monthEnd(month));
        return ReportMonthTotal(month, sum(monthRows),
            month == reportMonth(period.today) && period.isCurrent,
            future: future, count: monthRows.length);
      }),
      current.isEmpty ? null : current.first,
    );
  }
  final ReportPeriod period;
  final List<ReportExpense> expenses;
  final int totalCents, comparisonCents, previousCents;
  final List<ReportSlice> categories, payers, days;
  final List<ReportMonthTotal> trend;
  final ReportExpense? largestExpense;
  int get count => expenses.length;
  int get averageCents => count == 0 ? 0 : (totalCents / count).round();
  ReportMonthTotal? get busiestMonth {
    final months = trend.where((m) => !m.future && m.count > 0).toList()
      ..sort((a, b) => b.cents.compareTo(a.cents));
    return months.isEmpty ? null : months.first;
  }

  /// The roster only changes this projection, never the underlying expense load.
  List<ReportPayment> memberPayments(Iterable<ReportMember> members) {
    final roster = {for (final member in members) member.id: member};
    final payments = <String, ReportPayment>{};
    for (final payer in payers) {
      final member = roster[payer.id];
      payments[payer.id] = ReportPayment(payer.id,
          _nonblank(member?.name) ?? payer.label, payer.cents, payer.count,
          isCurrentMember: member != null);
    }
    for (final member in roster.values) {
      payments.putIfAbsent(
          member.id,
          () => ReportPayment(
              member.id, _nonblank(member.name) ?? 'Non specificato', 0, 0,
              isCurrentMember: true));
    }
    final result = payments.values.toList()
      ..sort((a, b) {
        final amount = b.cents.compareTo(a.cents);
        return amount != 0 ? amount : a.label.compareTo(b.label);
      });
    if (totalCents <= 0 || result.any((payment) => payment.cents < 0))
      return result;
    final tenths = {
      for (final payment in result)
        payment.id: payment.cents * 1000 ~/ totalCents
    };
    var remainder =
        1000 - tenths.values.fold<int>(0, (sum, value) => sum + value);
    final byRemainder = [...result]..sort((a, b) {
        final difference = (b.cents * 1000 % totalCents)
            .compareTo(a.cents * 1000 % totalCents);
        return difference != 0 ? difference : a.id.compareTo(b.id);
      });
    for (final payment in byRemainder) {
      if (remainder <= 0) break;
      tenths[payment.id] = tenths[payment.id]! + 1;
      remainder--;
    }
    return [
      for (final payment in result)
        ReportPayment(payment.id, payment.label, payment.cents, payment.count,
            isCurrentMember: payment.isCurrentMember,
            shareTenths: tenths[payment.id]!)
    ];
  }

  double? get changePercent => previousCents == 0
      ? null
      : (comparisonCents - previousCents) / previousCents * 100;
}
