import 'package:drift/native.dart';
import 'package:family_expense_tracker/core/enums/recurrence_frequency.dart';
import 'package:family_expense_tracker/features/offline/data/local/offline_database.dart';
import 'package:flutter_test/flutter_test.dart';

// Issue #69 - AC6: Drift v4 -> v5 adds only deleted_at and keeps every row.

void main() {
  test('upgrade from v4 keeps the rows and adds a null deleted_at', () async {
    final db = OfflineDatabase.forTesting(
      NativeDatabase.memory(setup: (raw) {
        raw.execute('''
          CREATE TABLE recurring_expenses (
            id TEXT NOT NULL PRIMARY KEY,
            user_id TEXT NOT NULL,
            group_id TEXT NULL,
            template_expense_id TEXT NULL,
            amount REAL NOT NULL,
            category_id TEXT NOT NULL,
            category_name TEXT NOT NULL,
            merchant TEXT NULL,
            notes TEXT NULL,
            is_group_expense INTEGER NOT NULL DEFAULT 1,
            frequency TEXT NOT NULL,
            anchor_date INTEGER NOT NULL,
            is_paused INTEGER NOT NULL DEFAULT 0,
            last_instance_created_at INTEGER NULL,
            next_due_date INTEGER NULL,
            budget_reservation_enabled INTEGER NOT NULL DEFAULT 0,
            default_reimbursement_status TEXT NOT NULL DEFAULT 'none',
            payment_method_id TEXT NULL,
            payment_method_name TEXT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        raw.execute('''
          INSERT INTO recurring_expenses
            (id, user_id, amount, category_id, category_name, frequency,
             anchor_date, created_at, updated_at)
          VALUES ('t1', 'u1', 42.5, 'c1', 'Casa', 'monthly',
                  1790000000, 1790000000, 1790000000)
        ''');
        raw.execute('PRAGMA user_version = 4');
      }),
    );
    addTearDown(db.close);

    final rows = await db.select(db.recurringExpenses).get();

    expect(rows, hasLength(1));
    expect(rows.single.id, 't1');
    expect(rows.single.amount, 42.5);
    expect(rows.single.frequency, RecurrenceFrequency.monthly);
    expect(rows.single.deletedAt, isNull);
    expect(db.schemaVersion, 5);
  });
}
