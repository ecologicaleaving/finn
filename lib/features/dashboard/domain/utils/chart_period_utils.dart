import 'package:intl/intl.dart';

/// Granularità del grafico "Andamento Spese".
enum ChartPeriod { week, month, year }

final DateFormat _dayKeyFormat = DateFormat('yyyy-MM-dd');
final DateFormat _monthKeyFormat = DateFormat('yyyy-MM');

/// Calcola l'intervallo (date-only, estremi inclusi) del periodo indicato da
/// [period] e [offset] rispetto a [now].
///
/// Usa solo il costruttore [DateTime] (che normalizza mesi/giorni negativi o
/// in overflow), quindi gestisce correttamente i cambi d'anno (es. gennaio con
/// offset -1 → dicembre dell'anno precedente) e i cambi d'ora legale.
({DateTime start, DateTime end}) chartRangeFor(
  ChartPeriod period,
  int offset,
  DateTime now,
) {
  switch (period) {
    case ChartPeriod.week:
      final start = DateTime(
        now.year,
        now.month,
        now.day - (now.weekday - 1) + offset * 7,
      );
      final end = DateTime(start.year, start.month, start.day + 6);
      return (start: start, end: end);
    case ChartPeriod.month:
      final start = DateTime(now.year, now.month + offset, 1);
      final end = DateTime(now.year, now.month + offset + 1, 0);
      return (start: start, end: end);
    case ChartPeriod.year:
      return (
        start: DateTime(now.year + offset, 1, 1),
        end: DateTime(now.year + offset, 12, 31),
      );
  }
}

/// Chiave del bucket in cui ricade [date] per il periodo indicato:
/// 'yyyy-MM-dd' per settimana/mese, 'yyyy-MM' per anno.
String chartBucketKey(ChartPeriod period, DateTime date) {
  switch (period) {
    case ChartPeriod.week:
    case ChartPeriod.month:
      return _dayKeyFormat.format(date);
    case ChartPeriod.year:
      return _monthKeyFormat.format(date);
  }
}

/// Date dei bucket del grafico per l'intervallo [start]..[end]:
/// 7 giorni per la settimana, tutti i giorni del mese di [start] per il mese,
/// i 12 mesi dell'anno di [start] per l'anno.
List<DateTime> chartBucketDates(
  ChartPeriod period,
  DateTime start,
  DateTime end,
) {
  switch (period) {
    case ChartPeriod.week:
      return List.generate(
        7,
        (i) => DateTime(start.year, start.month, start.day + i),
      );
    case ChartPeriod.month:
      return [
        for (int d = start.day; d <= end.day; d++)
          DateTime(start.year, start.month, d),
      ];
    case ChartPeriod.year:
      return List.generate(12, (i) => DateTime(start.year, i + 1, 1));
  }
}

/// Raggruppa le righe (`{'amount': num, 'date': 'yyyy-MM-dd'}`) per bucket,
/// restituendo gli importi in centesimi (arrotondati).
Map<String, int> groupAmountsByBucket(
  ChartPeriod period,
  Iterable<Map<String, dynamic>> rows,
) {
  final grouped = <String, int>{};
  for (final row in rows) {
    final date = DateTime.parse(row['date'] as String);
    final amountCents = ((row['amount'] as num).toDouble() * 100).round();
    final key = chartBucketKey(period, date);
    grouped[key] = (grouped[key] ?? 0) + amountCents;
  }
  return grouped;
}
