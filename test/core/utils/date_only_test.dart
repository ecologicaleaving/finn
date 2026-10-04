import 'package:family_expense_tracker/core/utils/date_only.dart';
import 'package:flutter_test/flutter_test.dart';

String _expectedLocal(DateTime utc) {
  final l = utc.toLocal();
  final m = l.month.toString().padLeft(2, '0');
  final d = l.day.toString().padLeft(2, '0');
  return '${l.year}-$m-$d';
}

void main() {
  group('toServerDate (issue #66)', () {
    test('local DateTime just after midnight keeps the local day', () {
      expect(toServerDate(DateTime(2026, 10, 4, 0, 30)), '2026-10-04');
    });

    test('UTC midnight is a date-only marker and is not shifted', () {
      expect(toServerDate(DateTime.utc(2026, 10, 4)), '2026-10-04');
    });

    test('UTC instant with a time component is converted to local', () {
      final d = DateTime.utc(2026, 10, 3, 22, 30);
      expect(toServerDate(d), _expectedLocal(d));
    });

    test('zero padding for month and day', () {
      expect(toServerDate(DateTime(2026, 1, 5, 12)), '2026-01-05');
    });
  });

  group('serverDateFromPayload', () {
    test('local datetime string', () {
      expect(serverDateFromPayload('2026-10-04T00:30:00.000'), '2026-10-04');
    });

    test('date-only string', () {
      expect(serverDateFromPayload('2026-10-04'), '2026-10-04');
    });

    test('UTC midnight string', () {
      expect(serverDateFromPayload('2026-10-04T00:00:00.000Z'), '2026-10-04');
    });
  });
}
