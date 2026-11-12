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

class ReportPeriod {
  ReportPeriod(DateTime selected, DateTime now)
      : today = reportDay(now),
        month = reportMonth(selected).isAfter(reportMonth(now))
            ? reportMonth(now)
            : reportMonth(selected);
  final DateTime month;
  final DateTime today;
  bool get isCurrent => month == reportMonth(today);
  DateTime get end => isCurrent ? today : monthEnd(month);
  DateTime get previousMonth => reportMonth(month, -1);
  int get comparisonDays => isCurrent
      ? (today.day < monthEnd(previousMonth).day
          ? today.day
          : monthEnd(previousMonth).day)
      : monthEnd(month).day;
  DateTime get comparisonEnd =>
      isCurrent ? DateTime.utc(month.year, month.month, comparisonDays) : end;
  DateTime get previousEnd => isCurrent
      ? DateTime.utc(previousMonth.year, previousMonth.month, comparisonDays)
      : monthEnd(previousMonth);
  DateTime get historyStart => reportMonth(month, -5);
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
  const ReportMonthTotal(this.month, this.cents, this.partial);
  final DateTime month;
  final int cents;
  final bool partial;
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
    final current = between(period.month, period.end)
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
      sum(between(period.month, period.comparisonEnd)),
      sum(between(period.previousMonth, period.previousEnd)),
      slices((e) => e.categoryId ?? e.category, (e) => e.category),
      slices((e) => e.payerId, (e) => e.payerName),
      slices((e) => toServerDate(e.date), (e) => toServerDate(e.date)),
      List.generate(6, (i) {
        final month = reportMonth(period.month, i - 5);
        return ReportMonthTotal(
            month,
            sum(between(
                month, month == period.month ? period.end : monthEnd(month))),
            month == period.month && period.isCurrent);
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
  double? get changePercent => previousCents == 0
      ? null
      : (comparisonCents - previousCents) / previousCents * 100;
}
