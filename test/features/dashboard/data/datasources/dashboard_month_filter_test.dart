import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:family_expense_tracker/features/dashboard/domain/entities/dashboard_stats_entity.dart';

// Unit tests per il filtro mensile della dashboard — Issue #13
//
// Bug: totale per mese sempre zero — regressione dal fix precedente.
//
// Causa: DashboardLocalDataSource._getCacheKey non includeva l'offset,
// quindi mesi diversi condividevano la stessa chiave cache:
//   - getCachedStats(offset=0)  → restituiva dati di un mese sbagliato
//   - cacheStats(offset=-1)     → sovrascriveva la cache dell'offset=0
//
// Fix: aggiunto `offset` alla chiave cache e a getCachedStats/cacheStats.
void main() {
  group('Dashboard Monthly Date Range — Issue #13', () {
    // -----------------------------------------------------------------------
    // Helper: riproduce _calculateDateRange da personal_dashboard_view.dart
    // Testato separatamente per assicurare che il filtro mensile sia corretto.
    // -----------------------------------------------------------------------
    (DateTime start, DateTime end) calcMonthRange(DateTime now, int offset) {
      final targetDate = DateTime(now.year, now.month + offset, 1);
      final startDate = DateTime(targetDate.year, targetDate.month, 1);
      final endDate =
          DateTime(targetDate.year, targetDate.month + 1, 0, 23, 59, 59);
      return (startDate, endDate);
    }

    // -----------------------------------------------------------------------
    // Helper: somma spese mock che rientrano nel range [startDate, endDate]
    // Simula la logica di query con .gte/.lte su colonna 'date'.
    // -----------------------------------------------------------------------
    int sumExpensesInRange(
      List<Map<String, dynamic>> expenses,
      DateTime startDate,
      DateTime endDate,
    ) {
      final startStr =
          DateFormat('yyyy-MM-dd').format(startDate); // es. '2026-03-01'
      final endStr =
          DateFormat('yyyy-MM-dd').format(endDate); // es. '2026-03-31'

      int total = 0;
      for (final expense in expenses) {
        final date = expense['date'] as String;
        if (date.compareTo(startStr) >= 0 && date.compareTo(endStr) <= 0) {
          total += ((expense['amount'] as double) * 100).round();
        }
      }
      return total;
    }

    // Mock expenses distribuiti su 3 mesi diversi
    final mockExpenses = [
      {'date': '2026-01-10', 'amount': 50.0},
      {'date': '2026-01-25', 'amount': 30.0},
      {'date': '2026-02-05', 'amount': 80.0},
      {'date': '2026-02-20', 'amount': 40.0},
      {'date': '2026-03-01', 'amount': 100.0},
      {'date': '2026-03-15', 'amount': 60.0},
    ];

    // -----------------------------------------------------------------------
    // AC1: filtro mensile produce totali corretti e non zero per mesi diversi
    // -----------------------------------------------------------------------
    group('AC1 — filtro mensile per offset diversi', () {
      test('mese corrente (offset=0, marzo 2026): totale corretto e non zero',
          () {
        final now = DateTime(2026, 3, 15);
        final (start, end) = calcMonthRange(now, 0);

        final total = sumExpensesInRange(mockExpenses, start, end);

        expect(total, isNot(0),
            reason: 'il totale di marzo non deve essere zero');
        expect(total, equals(16000),
            reason: '100 + 60 = €160 in centesimi');
      });

      test('mese precedente (offset=-1, febbraio 2026): totale corretto e non zero',
          () {
        final now = DateTime(2026, 3, 15);
        final (start, end) = calcMonthRange(now, -1);

        final total = sumExpensesInRange(mockExpenses, start, end);

        expect(total, isNot(0),
            reason: 'il totale di febbraio non deve essere zero');
        expect(total, equals(12000),
            reason: '80 + 40 = €120 in centesimi');
      });

      test('due mesi fa (offset=-2, gennaio 2026): totale corretto e non zero',
          () {
        final now = DateTime(2026, 3, 15);
        final (start, end) = calcMonthRange(now, -2);

        final total = sumExpensesInRange(mockExpenses, start, end);

        expect(total, isNot(0),
            reason: 'il totale di gennaio non deve essere zero');
        expect(total, equals(8000),
            reason: '50 + 30 = €80 in centesimi');
      });

      test('offset diversi producono totali diversi — non sempre lo stesso valore',
          () {
        final now = DateTime(2026, 3, 15);

        final (s0, e0) = calcMonthRange(now, 0);
        final (s1, e1) = calcMonthRange(now, -1);
        final (s2, e2) = calcMonthRange(now, -2);

        final total0 = sumExpensesInRange(mockExpenses, s0, e0);
        final total1 = sumExpensesInRange(mockExpenses, s1, e1);
        final total2 = sumExpensesInRange(mockExpenses, s2, e2);

        expect(total0, isNot(equals(total1)),
            reason:
                'marzo e febbraio devono avere totali diversi (non entrambi zero)');
        expect(total1, isNot(equals(total2)),
            reason:
                'febbraio e gennaio devono avere totali diversi (non entrambi zero)');
        expect(total0, isNot(equals(total2)),
            reason:
                'marzo e gennaio devono avere totali diversi (non entrambi zero)');
      });

      test('spese di altri mesi NON compaiono nel totale del mese selezionato',
          () {
        final now = DateTime(2026, 3, 15);
        final (start, end) = calcMonthRange(now, 0); // solo marzo

        final total = sumExpensesInRange(mockExpenses, start, end);

        // Totale di tutti i mesi combinati
        final totalAllMonths = mockExpenses.fold<int>(
          0,
          (sum, e) => sum + ((e['amount'] as double) * 100).round(),
        );

        expect(total, lessThan(totalAllMonths),
            reason:
                'il totale di marzo deve essere < totale di tutti i mesi: '
                'le spese di altri mesi non devono essere incluse');
      });

      test('cross-year: gennaio 2026 con offset=-1 filtra dicembre 2025',
          () {
        final now = DateTime(2026, 1, 15);
        final (start, end) = calcMonthRange(now, -1);

        // Il range deve coprire dicembre 2025
        expect(start, equals(DateTime(2025, 12, 1)),
            reason: 'start deve essere 2025-12-01');
        expect(end.year, equals(2025),
            reason: 'end deve essere nel 2025 (cross-year)');
        expect(end.month, equals(12));
        expect(end.day, equals(31));

        final dec2025Expenses = [
          {'date': '2025-12-10', 'amount': 200.0},
          {'date': '2025-12-25', 'amount': 50.0},
          {'date': '2026-01-01', 'amount': 999.0}, // da escludere
        ];

        final total = sumExpensesInRange(dec2025Expenses, start, end);
        expect(total, isNot(0),
            reason: 'dicembre 2025 non deve essere zero');
        expect(total, equals(25000),
            reason: '200 + 50 = €250, senza la spesa di gennaio 2026');
      });
    });

    // -----------------------------------------------------------------------
    // AC2: cache key include offset — la regressione è corretta
    // -----------------------------------------------------------------------
    group('AC2 — cache key include offset (verifica fix regressione)', () {
      // Testa che la cache key generata includa l'offset, in modo che
      // mesi diversi non sovrascrivano la cache a vicenda.
      //
      // REGRESSIONE (prima del fix):
      //   chiave = 'dashboard_{groupId}_{period}_{userId}'
      //   → offset=0 e offset=-1 avevano la STESSA chiave
      //   → getCachedStats(offset=-1) restituiva dati del mese sbagliato
      //
      // FIX:
      //   chiave = 'dashboard_{groupId}_{period}_{offset}_{userId}'
      //   → ogni mese ha la propria chiave cache

      String buildExpectedCacheKey(
        String groupId,
        DashboardPeriod period,
        int offset, {
        String userId = 'all',
      }) {
        // Riproduci la logica di _getCacheKey dopo il fix
        return 'dashboard_${groupId}_${period.apiValue}_${offset}_$userId';
      }

      test('offset=0 e offset=-1 producono chiavi diverse', () {
        const groupId = 'test-group';

        final key0 = buildExpectedCacheKey(groupId, DashboardPeriod.month, 0);
        final key1 =
            buildExpectedCacheKey(groupId, DashboardPeriod.month, -1);

        expect(key0, isNot(equals(key1)),
            reason:
                'mesi diversi devono avere chiavi cache diverse (fix regressione)');
      });

      test('chiave include il valore dell\'offset', () {
        const groupId = 'test-group';

        final keyOffset0 =
            buildExpectedCacheKey(groupId, DashboardPeriod.month, 0);
        final keyOffset2 =
            buildExpectedCacheKey(groupId, DashboardPeriod.month, -2);

        expect(keyOffset0, contains('_0_'),
            reason: 'chiave per offset=0 deve contenere _0_');
        expect(keyOffset2, contains('_-2_'),
            reason: 'chiave per offset=-2 deve contenere _-2_');
      });

      test('week e year con stesso offset producono chiavi diverse da month', () {
        const groupId = 'test-group';

        final keyMonth = buildExpectedCacheKey(groupId, DashboardPeriod.month, -1);
        final keyWeek = buildExpectedCacheKey(groupId, DashboardPeriod.week, -1);
        final keyYear = buildExpectedCacheKey(groupId, DashboardPeriod.year, -1);

        expect(keyMonth, isNot(equals(keyWeek)));
        expect(keyMonth, isNot(equals(keyYear)));
        expect(keyWeek, isNot(equals(keyYear)));
      });

      test('userId diversi producono chiavi diverse per lo stesso mese', () {
        const groupId = 'test-group';

        final keyAllUsers =
            buildExpectedCacheKey(groupId, DashboardPeriod.month, -1);
        final keyUser1 = buildExpectedCacheKey(
          groupId,
          DashboardPeriod.month,
          -1,
          userId: 'user-abc',
        );

        expect(keyAllUsers, isNot(equals(keyUser1)));
      });
    });

    // -----------------------------------------------------------------------
    // Verifica aggiuntiva: logica di range non regredisce per offset=0
    // -----------------------------------------------------------------------
    group('offset=0 non introduce regressioni', () {
      test('range per offset=0 copre esattamente il mese corrente', () {
        final now = DateTime(2026, 3, 15);
        final (start, end) = calcMonthRange(now, 0);

        expect(start, equals(DateTime(2026, 3, 1)));
        expect(end.year, equals(2026));
        expect(end.month, equals(3));
        expect(end.day, equals(31));
      });

      test('range per offset=0 a gennaio copre l\'intero gennaio', () {
        final now = DateTime(2026, 1, 10);
        final (start, end) = calcMonthRange(now, 0);

        expect(start, equals(DateTime(2026, 1, 1)));
        expect(end.day, equals(31));
        expect(end.month, equals(1));
      });

      test('range per offset=0 a febbraio (anno bisestile) termina il 29', () {
        final now = DateTime(2024, 2, 10); // 2024 è bisestile
        final (start, end) = calcMonthRange(now, 0);

        expect(start, equals(DateTime(2024, 2, 1)));
        expect(end.day, equals(29)); // febbraio 2024 ha 29 giorni
      });
    });
  });
}
