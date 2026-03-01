import 'package:drift/drift.dart';

/// Drift table definition for recurring_expense_instances
///
/// Audit trail mapping that tracks which expense instances were generated
/// from which recurring templates.
@DataClassName('RecurringExpenseInstanceData')
class RecurringExpenseInstances extends Table {
  /// Auto-increment primary key
  IntColumn get id => integer().autoIncrement()();

  /// Template that generated this instance
  TextColumn get recurringExpenseId => text()();

  /// Generated expense instance (references expenses or offline_expenses)
  TextColumn get expenseId => text()();

  /// When instance was scheduled to occur
  DateTimeColumn get scheduledDate => dateTime()();

  /// When instance was actually created
  DateTimeColumn get createdAt => dateTime()();
}
