import 'package:flutter_test/flutter_test.dart';

import 'package:family_expense_tracker/features/dashboard/domain/utils/chart_period_utils.dart';

void main() {
  group('chartRangeFor', () {
    test('mese precedente (offset -1) copre tutto il mese target', () {
      final range = chartRangeFor(ChartPeriod.month, -1, DateTime(2026, 9, 26, 15, 30));
      expect(range.start, DateTime(2026, 8, 1));
      expect(range.end, DateTime(2026, 8, 31));
    });

    test('gennaio con offset -1 va a dicembre dell\'anno precedente', () {
      final range = chartRangeFor(ChartPeriod.month, -1, DateTime(2027, 1, 15));
      expect(range.start, DateTime(2026, 12, 1));
      expect(range.end, DateTime(2026, 12, 31));
    });

    test('gennaio con offset -13 va a dicembre di due anni prima', () {
      final range = chartRangeFor(ChartPeriod.month, -13, DateTime(2027, 1, 15));
      expect(range.start, DateTime(2025, 12, 1));
      expect(range.end, DateTime(2025, 12, 31));
    });

    test('offset 0 mantiene il mese corrente', () {
      final range = chartRangeFor(ChartPeriod.month, 0, DateTime(2026, 9, 26));
      expect(range.start, DateTime(2026, 9, 1));
      expect(range.end, DateTime(2026, 9, 30));
    });

    test('settimana a cavallo d\'anno parte dal lunedi\' precedente', () {
      // 2027-01-01 e' un venerdi'
      final range = chartRangeFor(ChartPeriod.week, 0, DateTime(2027, 1, 1, 10));
      expect(range.start, DateTime(2026, 12, 28));
      expect(range.start.weekday, DateTime.monday);
      expect(range.end, DateTime(2027, 1, 3));
    });

    test('settimana con offset -1', () {
      final range = chartRangeFor(ChartPeriod.week, -1, DateTime(2026, 9, 26));
      expect(range.start, DateTime(2026, 9, 14));
      expect(range.end, DateTime(2026, 9, 20));
    });

    test('anno con offset -1', () {
      final range = chartRangeFor(ChartPeriod.year, -1, DateTime(2026, 9, 26));
      expect(range.start, DateTime(2025, 1, 1));
      expect(range.end, DateTime(2025, 12, 31));
    });
  });

  group('chartBucketDates / groupAmountsByBucket', () {
    test('mese precedente: 31 bucket di agosto e nessuna spesa persa', () {
      final range = chartRangeFor(ChartPeriod.month, -1, DateTime(2026, 9, 26));
      final dates = chartBucketDates(ChartPeriod.month, range.start, range.end);
      final keys = dates.map((d) => chartBucketKey(ChartPeriod.month, d)).toList();

      expect(keys, hasLength(31));
      expect(keys.first, '2026-08-01');
      expect(keys.last, '2026-08-31');

      final rows = [
        {'amount': 10.5, 'date': '2026-08-01'},
        {'amount': 4.5, 'date': '2026-08-01'},
        {'amount': 20, 'date': '2026-08-15'},
        {'amount': 7.25, 'date': '2026-08-31'},
      ];
      final grouped = groupAmountsByBucket(ChartPeriod.month, rows);

      expect(grouped['2026-08-01'], 1500);
      expect(grouped['2026-08-15'], 2000);
      expect(grouped['2026-08-31'], 725);

      final total = keys.fold<int>(0, (sum, k) => sum + (grouped[k] ?? 0));
      expect(total, 1500 + 2000 + 725);
    });

    test('febbraio visto dal 31 marzo ha 28 bucket, senza overflow su marzo', () {
      final range = chartRangeFor(ChartPeriod.month, -1, DateTime(2026, 3, 31));
      expect(range.start, DateTime(2026, 2, 1));
      expect(range.end, DateTime(2026, 2, 28));
      final dates = chartBucketDates(ChartPeriod.month, range.start, range.end);
      expect(dates, hasLength(28));
      expect(dates.last, DateTime(2026, 2, 28));
    });

    test('anno precedente: chiavi da 2025-01 a 2025-12', () {
      final range = chartRangeFor(ChartPeriod.year, -1, DateTime(2026, 9, 26));
      final dates = chartBucketDates(ChartPeriod.year, range.start, range.end);
      final keys = dates.map((d) => chartBucketKey(ChartPeriod.year, d)).toList();

      expect(keys, hasLength(12));
      expect(keys.first, '2025-01');
      expect(keys.last, '2025-12');

      final grouped = groupAmountsByBucket(ChartPeriod.year, [
        {'amount': 12.34, 'date': '2025-03-10'},
        {'amount': 1, 'date': '2025-03-20'},
      ]);
      expect(grouped['2025-03'], 1334);
      expect(keys, contains('2025-03'));
    });

    test('settimana: 7 bucket consecutivi a cavallo d\'anno', () {
      final range = chartRangeFor(ChartPeriod.week, 0, DateTime(2027, 1, 1));
      final keys = chartBucketDates(ChartPeriod.week, range.start, range.end)
          .map((d) => chartBucketKey(ChartPeriod.week, d))
          .toList();
      expect(keys, [
        '2026-12-28',
        '2026-12-29',
        '2026-12-30',
        '2026-12-31',
        '2027-01-01',
        '2027-01-02',
        '2027-01-03',
      ]);
    });
  });
}
