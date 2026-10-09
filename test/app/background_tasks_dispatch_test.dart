import 'package:family_expense_tracker/app/background_tasks.dart';
import 'package:family_expense_tracker/core/services/recurring_expense_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

// Issue #69 - AC3: the single Workmanager dispatcher routes by task name.

void main() {
  test('the recurring task runs the generator', () async {
    var calls = 0;
    final ok = await BackgroundTasks.runTask(
      RecurringExpenseScheduler.taskName,
      recurringRunner: () async {
        calls++;
        return true;
      },
    );
    expect(ok, isTrue);
    expect(calls, 1);
  });

  test('the one-off alias runs the generator too', () async {
    var calls = 0;
    await BackgroundTasks.runTask(
      '${RecurringExpenseScheduler.taskName}_immediate',
      recurringRunner: () async {
        calls++;
        return true;
      },
    );
    expect(calls, 1);
  });

  test('a failing generator reports failure to Workmanager', () async {
    final ok = await BackgroundTasks.runTask(
      RecurringExpenseScheduler.taskName,
      recurringRunner: () async => false,
    );
    expect(ok, isFalse);
  });

  test('unknown tasks return true and run nothing', () async {
    var calls = 0;
    final ok = await BackgroundTasks.runTask(
      'something-else',
      recurringRunner: () async {
        calls++;
        return true;
      },
    );
    expect(ok, isTrue);
    expect(calls, 0);
  });
}
