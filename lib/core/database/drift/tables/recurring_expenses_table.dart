import 'package:drift/drift.dart';
import '../../../enums/recurrence_frequency.dart';
import '../../../enums/reimbursement_status.dart';

/// Drift table definition for recurring_expenses
///
/// Stores recurring expense templates that generate expense instances
/// on a schedule.
@DataClassName('RecurringExpenseData')
class RecurringExpenses extends Table {
  /// Unique identifier (UUID)
  TextColumn get id => text()();

  /// Creator/owner of recurring template
  TextColumn get userId => text()();

  /// Family group for shared budgets (nullable)
  TextColumn get groupId => text().nullable()();

  /// Original expense that became recurring (nullable)
  TextColumn get templateExpenseId => text().nullable()();

  /// Expense amount in euros
  RealColumn get amount => real()();

  /// Expense category ID
  TextColumn get categoryId => text()();

  /// Category name (denormalized for offline access)
  TextColumn get categoryName => text()();

  /// Merchant/vendor name (nullable, max 100 chars)
  TextColumn get merchant => text().nullable()();

  /// Description/notes (nullable, max 500 chars)
  TextColumn get notes => text().nullable()();

  /// Whether expense affects group budget
  BoolColumn get isGroupExpense => boolean().withDefault(const Constant(true))();

  /// Recurrence frequency (daily/weekly/monthly/yearly)
  TextColumn get frequency => textEnum<RecurrenceFrequency>()();

  /// Reference date for recurrence calculation
  DateTimeColumn get anchorDate => dateTime()();

  /// Whether instance generation is paused
  BoolColumn get isPaused => boolean().withDefault(const Constant(false))();

  /// Last time an instance was generated (nullable)
  DateTimeColumn get lastInstanceCreatedAt => dateTime().nullable()();

  /// Calculated next occurrence (query optimization, nullable)
  DateTimeColumn get nextDueDate => dateTime().nullable()();

  /// Whether to reserve budget for this expense
  BoolColumn get budgetReservationEnabled => boolean().withDefault(const Constant(false))();

  /// Default reimbursement status for instances
  TextColumn get defaultReimbursementStatus => textEnum<ReimbursementStatus>().withDefault(const Constant('none'))();

  /// Payment method ID (nullable)
  TextColumn get paymentMethodId => text().nullable()();

  /// Payment method name (denormalized, nullable)
  TextColumn get paymentMethodName => text().nullable()();

  /// Template creation timestamp
  DateTimeColumn get createdAt => dateTime()();

  /// Last modification timestamp
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
