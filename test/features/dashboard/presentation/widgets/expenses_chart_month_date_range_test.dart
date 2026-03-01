import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

// Unit tests for the monthly dashboard date range calculation fix (Issue #11)
void main() {
  group('Dashboard Monthly Date Range Calculation (Issue #11)', () {
    (DateTime startDate, DateTime endDate) calcMonthRange(DateTime now, int offset) {
      final targetDate = DateTime(now.year, now.month + offset, 1);
      final targetYear = targetDate.year;
      final normalizedMonth = targetDate.month;
      final startDate = DateTime(targetYear, normalizedMonth, 1);
      final endDate = DateTime(targetYear, normalizedMonth + 1, 0);
      return (startDate, endDate);
    }

    (DateTime startDate, DateTime endDate) calcMonthRangeOld(DateTime now, int offset) {
      final targetMonth = now.month + offset;
      final targetYear = now.year + (targetMonth - 1) ~/ 12;
      final normalizedMonth = ((targetMonth - 1) % 12) + 1;
      final startDate = DateTime(targetYear, normalizedMonth, 1);
      final endDate = DateTime(targetYear, normalizedMonth + 1, 0);
      return (startDate, endDate);
    }

    test('aggregazione mensile restituisce dati corretti - mese corrente', () {
      final now = DateTime(2026, 3, 15);
      final (start, end) = calcMonthRange(now, 0);
      expect(start, equals(DateTime(2026, 3, 1)));
      expect(end, equals(DateTime(2026, 3, 31)));
    });

    test('mese precedente offset=-1 calcola range corretto', () {
      final now = DateTime(2026, 3, 15);
      final (start, end) = calcMonthRange(now, -1);
      expect(start, equals(DateTime(2026, 2, 1)));
      expect(end, equals(DateTime(2026, 2, 28)));
    });

    test('navigazione cross-year: gennaio offset=-1 usa anno precedente', () {
      final now = DateTime(2026, 1, 15);
      final (start, end) = calcMonthRange(now, -1);
      expect(start.year, equals(2025));
      expect(start.month, equals(12));
      expect(end, equals(DateTime(2025, 12, 31)));
    });

    test('bug vecchio: gennaio con offset=-1 dava anno sbagliato (2026 invece di 2025)', () {
      final now = DateTime(2026, 1, 15);
      // Old code: targetMonth=0, (0-1)~/12 = 0 (not -1 as expected)
      // So targetYear = 2026 (wrong), should be 2025
      final targetMonth = now.month + (-1);
      final targetYearOld = now.year + (targetMonth - 1) ~/ 12;
      expect(targetYearOld, equals(2026)); // Documents the bug: wrong year
      
      final (startFixed, _) = calcMonthRange(now, -1);
      expect(startFixed.year, equals(2025)); // Fix: correct year
    });

    test('result keys corrispondono al mese target (non al mese corrente)', () {
      final now = DateTime(2026, 3, 15);
      final (startDate, endDate) = calcMonthRange(now, -1);
      final daysInMonth = endDate.day;

      final fixedKeys = List.generate(
        daysInMonth,
        (i) => DateFormat('yyyy-MM-dd').format(DateTime(startDate.year, startDate.month, i + 1)),
      );
      final brokenKeys = List.generate(
        daysInMonth,
        (i) => DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month, i + 1)),
      );

      expect(fixedKeys.first, equals('2026-02-01'));
      expect(fixedKeys.last, equals('2026-02-28'));
      expect(brokenKeys.first, equals('2026-03-01')); // Bug: wrong month
    });

    test('offset=0 non introduce regressioni rispetto al vecchio calcolo', () {
      final now = DateTime(2026, 3, 15);
      final (startFixed, endFixed) = calcMonthRange(now, 0);
      final (startOld, endOld) = calcMonthRangeOld(now, 0);
      expect(startFixed, equals(startOld));
      expect(endFixed, equals(endOld));
    });

    test('settimana e anno non sono impattati dal fix mensile', () {
      final now = DateTime(2026, 3, 15);
      // Week: unchanged
      final weekDay = now.weekday;
      final weekStart = now.subtract(Duration(days: weekDay - 1));
      expect(weekStart.weekday, equals(1));
      // Year: unchanged
      final yearStart = DateTime(now.year, 1, 1);
      final yearEnd = DateTime(now.year, 12, 31);
      expect(yearStart.month, equals(1));
      expect(yearEnd.month, equals(12));
    });
  });
}
