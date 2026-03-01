# API Contracts: Recurring Expenses

**Feature**: 013-recurring-expenses
**Phase**: 1 (Design Artifacts)
**Created**: 2026-01-16

---

## Overview

This document defines the API contracts for recurring expense functionality, including repository interfaces, provider contracts, and service layer methods. All contracts follow the existing Clean Architecture pattern with domain entities, repository abstractions, and Riverpod providers.

---

## Repository Interface

### RecurringExpenseRepository

**Location**: `lib/features/recurring_expenses/domain/repositories/recurring_expense_repository.dart`

Abstract repository interface defining the contract for recurring expense operations.

#### Methods

##### createRecurringExpense

Creates a new recurring expense template.

**Signature**:
```dart
Future<Either<Failure, RecurringExpenseEntity>> createRecurringExpense({
  required double amount,
  required String categoryId,
  required RecurrenceFrequency frequency,
  required DateTime anchorDate,
  String? merchant,
  String? notes,
  bool isGroupExpense = true,
  bool budgetReservationEnabled = false,
  ReimbursementStatus defaultReimbursementStatus = ReimbursementStatus.none,
  String? templateExpenseId, // If converting existing expense
});
```

**Parameters**:
- `amount` (double, required): Expense amount in euros (must be > 0)
- `categoryId` (String, required): UUID of expense category
- `frequency` (RecurrenceFrequency, required): Recurrence frequency (daily/weekly/monthly/yearly)
- `anchorDate` (DateTime, required): Reference date for recurrence calculation
- `merchant` (String?, optional): Merchant/vendor name (max 100 chars)
- `notes` (String?, optional): Description/notes (max 500 chars)
- `isGroupExpense` (bool, default: true): Whether expense affects group budget
- `budgetReservationEnabled` (bool, default: false): Whether to reserve budget
- `defaultReimbursementStatus` (ReimbursementStatus, default: none): Default reimbursement status for instances
- `templateExpenseId` (String?, optional): ID of original expense if converting

**Returns**:
- `Right(RecurringExpenseEntity)`: Successfully created recurring expense with generated ID
- `Left(Failure)`: Operation failed with error details

**Error Cases**:
| Error Type | Condition | User Message |
|------------|-----------|--------------|
| `ValidationFailure` | amount <= 0 | "Amount must be greater than 0" |
| `ValidationFailure` | categoryId not found | "Invalid category" |
| `ValidationFailure` | merchant > 100 chars | "Merchant name too long" |
| `ValidationFailure` | notes > 500 chars | "Notes too long" |
| `NetworkFailure` | No internet connection | "No internet connection" |
| `ServerFailure` | Supabase error | "Failed to create recurring expense" |

**Side Effects**:
- Inserts record into local Drift `recurring_expenses` table
- Queues sync operation to upload to Supabase
- Calculates and sets `nextDueDate` field
- Invalidates `recurringExpenseListProvider` (triggers UI update)

---

##### updateRecurringExpense

Updates an existing recurring expense template.

**Signature**:
```dart
Future<Either<Failure, RecurringExpenseEntity>> updateRecurringExpense({
  required String id,
  double? amount,
  String? categoryId,
  RecurrenceFrequency? frequency,
  String? merchant,
  String? notes,
  bool? budgetReservationEnabled,
  ReimbursementStatus? defaultReimbursementStatus,
});
```

**Parameters**:
- `id` (String, required): UUID of recurring expense to update
- `amount` (double?, optional): New amount in euros
- `categoryId` (String?, optional): New category UUID
- `frequency` (RecurrenceFrequency?, optional): New recurrence frequency
- `merchant` (String?, optional): New merchant name
- `notes` (String?, optional): New notes
- `budgetReservationEnabled` (bool?, optional): Enable/disable budget reservation
- `defaultReimbursementStatus` (ReimbursementStatus?, optional): New default reimbursement status

**Returns**:
- `Right(RecurringExpenseEntity)`: Successfully updated recurring expense
- `Left(Failure)`: Operation failed with error details

**Error Cases**:
| Error Type | Condition | User Message |
|------------|-----------|--------------|
| `NotFoundFailure` | id not found | "Recurring expense not found" |
| `ValidationFailure` | amount <= 0 | "Amount must be greater than 0" |
| `ValidationFailure` | categoryId not found | "Invalid category" |
| `UnauthorizedFailure` | user_id != current user | "Cannot update another user's recurring expense" |
| `NetworkFailure` | No internet connection | "No internet connection" |

**Side Effects**:
- Updates record in Drift `recurring_expenses` table
- Queues sync operation
- Recalculates `nextDueDate` if frequency changed
- Updates `updatedAt` timestamp
- Invalidates `recurringExpenseProvider(id)` and `recurringExpenseListProvider`
- If `budgetReservationEnabled` changed, invalidates `budgetReservationProvider`

**Note**: Updating a template does NOT affect already-generated instances. Only future instances will use new values.

---

##### pauseRecurringExpense

Pauses a recurring expense template (stops generating instances).

**Signature**:
```dart
Future<Either<Failure, RecurringExpenseEntity>> pauseRecurringExpense({
  required String id,
});
```

**Parameters**:
- `id` (String, required): UUID of recurring expense to pause

**Returns**:
- `Right(RecurringExpenseEntity)`: Successfully paused recurring expense
- `Left(Failure)`: Operation failed with error details

**Error Cases**:
| Error Type | Condition | User Message |
|------------|-----------|--------------|
| `NotFoundFailure` | id not found | "Recurring expense not found" |
| `UnauthorizedFailure` | user_id != current user | "Cannot pause another user's recurring expense" |
| `ValidationFailure` | Already paused | "Recurring expense is already paused" |

**Side Effects**:
- Sets `isPaused = true` in Drift database
- Queues sync operation
- Background task will skip this template when checking for due instances
- If `budgetReservationEnabled`, removes from budget reservation calculation

---

##### resumeRecurringExpense

Resumes a paused recurring expense template.

**Signature**:
```dart
Future<Either<Failure, RecurringExpenseEntity>> resumeRecurringExpense({
  required String id,
});
```

**Parameters**:
- `id` (String, required): UUID of recurring expense to resume

**Returns**:
- `Right(RecurringExpenseEntity)`: Successfully resumed recurring expense
- `Left(Failure)`: Operation failed with error details

**Error Cases**:
| Error Type | Condition | User Message |
|------------|-----------|--------------|
| `NotFoundFailure` | id not found | "Recurring expense not found" |
| `UnauthorizedFailure` | user_id != current user | "Cannot resume another user's recurring expense" |
| `ValidationFailure` | Already active | "Recurring expense is already active" |

**Side Effects**:
- Sets `isPaused = false` in Drift database
- Recalculates `nextDueDate` from `anchorDate` and `lastInstanceCreatedAt`
- Queues sync operation
- Background task will check this template for due instances
- If `budgetReservationEnabled`, includes in budget reservation calculation

**Note**: Resuming does NOT retroactively create missed instances. Next instance will be scheduled from resume date forward.

---

##### deleteRecurringExpense

Deletes a recurring expense template.

**Signature**:
```dart
Future<Either<Failure, Unit>> deleteRecurringExpense({
  required String id,
  bool deleteInstances = false,
});
```

**Parameters**:
- `id` (String, required): UUID of recurring expense to delete
- `deleteInstances` (bool, default: false): Whether to delete all generated instances

**Returns**:
- `Right(Unit)`: Successfully deleted recurring expense
- `Left(Failure)`: Operation failed with error details

**Error Cases**:
| Error Type | Condition | User Message |
|------------|-----------|--------------|
| `NotFoundFailure` | id not found | "Recurring expense not found" |
| `UnauthorizedFailure` | user_id != current user | "Cannot delete another user's recurring expense" |

**Side Effects**:
- Deletes template record from Drift `recurring_expenses` table
- Cascade deletes all `recurring_expense_instances` mapping records
- If `deleteInstances = true`:
  - Deletes all linked expense instances from `offline_expenses` and `expenses` tables
  - Triggers budget recalculation
- Queues sync operation
- Invalidates `recurringExpenseListProvider`
- If `budgetReservationEnabled`, invalidates `budgetReservationProvider`

**UI Flow**:
```dart
// User deletes recurring expense
// 1. Show confirmation dialog
showDialog(
  title: "Delete Recurring Expense?",
  options: [
    "Delete future occurrences only",
    "Delete all occurrences (including past expenses)"
  ]
);

// 2. Call delete with appropriate flag
if (selectedOption == "Delete all") {
  await repository.deleteRecurringExpense(id: id, deleteInstances: true);
} else {
  await repository.deleteRecurringExpense(id: id, deleteInstances: false);
}
```

---

##### getRecurringExpenses

Retrieves all recurring expenses for the current user's group.

**Signature**:
```dart
Future<Either<Failure, List<RecurringExpenseEntity>>> getRecurringExpenses({
  bool? isPaused,
  bool? budgetReservationEnabled,
});
```

**Parameters**:
- `isPaused` (bool?, optional): Filter by paused status (null = all)
- `budgetReservationEnabled` (bool?, optional): Filter by budget reservation status (null = all)

**Returns**:
- `Right(List<RecurringExpenseEntity>)`: List of recurring expenses (empty list if none)
- `Left(Failure)`: Operation failed with error details

**Error Cases**:
| Error Type | Condition | User Message |
|------------|-----------|--------------|
| `NetworkFailure` | No internet + empty cache | "No internet connection" |
| `ServerFailure` | Supabase error | "Failed to load recurring expenses" |

**Side Effects**:
- Reads from local Drift database (offline-first)
- If online, triggers background sync to refresh cache
- No provider invalidation (read-only operation)

**Query Examples**:
```dart
// Get all recurring expenses
final all = await repository.getRecurringExpenses();

// Get only active recurring expenses
final active = await repository.getRecurringExpenses(isPaused: false);

// Get only expenses with budget reservation enabled
final reserved = await repository.getRecurringExpenses(
  isPaused: false,
  budgetReservationEnabled: true,
);
```

---

##### getRecurringExpense

Retrieves a single recurring expense by ID.

**Signature**:
```dart
Future<Either<Failure, RecurringExpenseEntity>> getRecurringExpense({
  required String id,
});
```

**Parameters**:
- `id` (String, required): UUID of recurring expense to retrieve

**Returns**:
- `Right(RecurringExpenseEntity)`: Successfully retrieved recurring expense
- `Left(Failure)`: Operation failed with error details

**Error Cases**:
| Error Type | Condition | User Message |
|------------|-----------|--------------|
| `NotFoundFailure` | id not found | "Recurring expense not found" |
| `NetworkFailure` | No internet + not in cache | "No internet connection" |

**Side Effects**:
- Reads from local Drift database
- No provider invalidation (read-only operation)

---

##### generateExpenseInstance

Manually generates an expense instance from a recurring template (used by background task).

**Signature**:
```dart
Future<Either<Failure, ExpenseEntity>> generateExpenseInstance({
  required String recurringExpenseId,
  required DateTime scheduledDate,
});
```

**Parameters**:
- `recurringExpenseId` (String, required): UUID of recurring expense template
- `scheduledDate` (DateTime, required): Date this instance is scheduled for

**Returns**:
- `Right(ExpenseEntity)`: Successfully created expense instance
- `Left(Failure)`: Operation failed with error details

**Error Cases**:
| Error Type | Condition | User Message |
|------------|-----------|--------------|
| `NotFoundFailure` | recurringExpenseId not found | "Recurring expense template not found" |
| `ValidationFailure` | Template is paused | "Cannot generate instance from paused template" |

**Side Effects**:
- Inserts expense into Drift `offline_expenses` table
- Inserts mapping into `recurring_expense_instances` table
- Updates template's `lastInstanceCreatedAt` timestamp
- Recalculates template's `nextDueDate`
- Queues sync operation for expense
- Invalidates `expenseListProvider` (existing expenses provider)
- Invalidates `budgetStatsProvider` (expense affects budget)

**Note**: This method is primarily used by the background task scheduler. Developers should rarely need to call it directly.

---

##### getRecurringExpenseInstances

Retrieves all expense instances generated from a recurring template.

**Signature**:
```dart
Future<Either<Failure, List<ExpenseEntity>>> getRecurringExpenseInstances({
  required String recurringExpenseId,
});
```

**Parameters**:
- `recurringExpenseId` (String, required): UUID of recurring expense template

**Returns**:
- `Right(List<ExpenseEntity>)`: List of all generated expense instances (empty if none)
- `Left(Failure)`: Operation failed with error details

**Error Cases**:
| Error Type | Condition | User Message |
|------------|-----------|--------------|
| `NotFoundFailure` | recurringExpenseId not found | "Recurring expense template not found" |

**Side Effects**:
- Joins `recurring_expense_instances` with `expenses` table
- Reads from local Drift database
- No provider invalidation (read-only operation)

**Use Case**: Display history of all instances generated from a template (for analytics or deletion preview).

---

## Domain Service: RecurrenceCalculator

**Location**: `lib/features/recurring_expenses/domain/services/recurrence_calculator.dart`

Utility service for calculating recurring expense due dates.

### calculateNextDueDate

Calculates the next occurrence date from an anchor date.

**Signature**:
```dart
static DateTime? calculateNextDueDate({
  required DateTime anchorDate,
  required RecurrenceFrequency frequency,
  DateTime? lastCreated,
});
```

**Parameters**:
- `anchorDate` (DateTime, required): Original date when recurring expense was created
- `frequency` (RecurrenceFrequency, required): Recurrence frequency (daily/weekly/monthly/yearly)
- `lastCreated` (DateTime?, optional): Last time an instance was created (null for first occurrence)

**Returns**:
- `DateTime`: Next due date in user's local timezone
- `null`: If calculation fails (edge case handling)

**Algorithm**:

```dart
// Pseudo-code
if (lastCreated == null) {
  // First occurrence: use anchor date
  return anchorDate;
} else {
  // Calculate next occurrence from last created
  switch (frequency) {
    case daily:
      return lastCreated + 1 day;
    case weekly:
      return lastCreated + 7 days;
    case monthly:
      return lastCreated + 1 month (preserving day-of-month);
    case yearly:
      return lastCreated + 1 year (preserving month and day);
  }
}
```

**Edge Case Handling**:

| Scenario | Anchor Date | Target Month | Result | Rationale |
|----------|-------------|--------------|--------|-----------|
| Month-end (31st) | Jan 31 | Feb | Feb 28/29 | Use last day of shorter month |
| Month-end (31st) | Jan 31 | Apr | Apr 30 | Use last day of shorter month |
| Leap year | Feb 29, 2024 | Feb 2025 | Feb 28, 2025 | Use last day of non-leap year |
| Weekly (any day) | Mon, Week 1 | Week 2 | Mon, Week 2 | Exactly 7 days later |
| Daily | Jan 1, 10:00 | Jan 2 | Jan 2, 10:00 | Exactly 24 hours later |

**Timezone Handling**:
- All calculations use `timezone` package with `tz.local`
- Dates stored in UTC in Supabase, converted to local for calculations
- Uses existing `TimezoneHandler` utility for consistency

**Example Usage**:
```dart
final nextDue = RecurrenceCalculator.calculateNextDueDate(
  anchorDate: DateTime(2026, 1, 31), // Jan 31, 2026
  frequency: RecurrenceFrequency.monthly,
  lastCreated: DateTime(2026, 1, 31),
);
// Result: Feb 28, 2026 (last day of February)
```

---

### calculateBudgetReservation

Calculates total reserved budget for a recurring expense in a period.

**Signature**:
```dart
static int calculateBudgetReservation({
  required RecurringExpenseEntity template,
  required int month,
  required int year,
});
```

**Parameters**:
- `template` (RecurringExpenseEntity, required): Recurring expense template
- `month` (int, required): Budget period month (1-12)
- `year` (int, required): Budget period year

**Returns**:
- `int`: Reserved amount in cents (0 if not due in period or paused)

**Algorithm**:
```dart
// Pseudo-code
if (template.isPaused || !template.budgetReservationEnabled) {
  return 0;
}

final periodStart = DateTime(year, month, 1);
final periodEnd = DateTime(year, month + 1, 0); // Last day of month

final nextDue = calculateNextDueDate(
  anchorDate: template.anchorDate,
  frequency: template.frequency,
  lastCreated: template.lastInstanceCreatedAt,
);

if (nextDue == null) return 0;

// If due in this period, reserve the amount
if (nextDue.isAfter(periodStart) && nextDue.isBefore(periodEnd)) {
  return (template.amount * 100).round(); // Convert euros to cents
}

return 0;
```

**Example Usage**:
```dart
// Rent: 500€/month, due on 1st of each month
final reservation = RecurrenceCalculator.calculateBudgetReservation(
  template: rentTemplate,
  month: 2, // February
  year: 2026,
);
// Result: 50000 cents (500€) if due in February, 0 otherwise
```

---

## Budget Utility Extension: BudgetCalculator

**Location**: `lib/core/utils/budget_calculator.dart` (EXTENDED)

Extend existing `BudgetCalculator` class with recurring expense methods.

### calculateReservedBudget

Calculates total reserved budget for all active recurring expenses in a period.

**Signature**:
```dart
static int calculateReservedBudget({
  required List<RecurringExpenseEntity> recurringExpenses,
  required int month,
  required int year,
});
```

**Parameters**:
- `recurringExpenses` (List<RecurringExpenseEntity>, required): List of recurring expense templates
- `month` (int, required): Budget period month (1-12)
- `year` (int, required): Budget period year

**Returns**:
- `int`: Total reserved amount in cents

**Algorithm**:
```dart
return recurringExpenses.fold<int>(0, (sum, template) {
  final reservation = RecurrenceCalculator.calculateBudgetReservation(
    template: template,
    month: month,
    year: year,
  );
  return sum + reservation;
});
```

**Side Effects**: None (pure function)

---

### calculateAvailableBudget

Calculates available budget after reservations.

**Signature**:
```dart
static int calculateAvailableBudget({
  required int budgetAmount,
  required int spentAmount,
  required int reservedBudget,
  int reimbursedIncome = 0,
});
```

**Parameters**:
- `budgetAmount` (int, required): Total budget in euros
- `spentAmount` (int, required): Amount spent in euros
- `reservedBudget` (int, required): Amount reserved for recurring expenses in cents
- `reimbursedIncome` (int, default: 0): Amount reimbursed in cents

**Returns**:
- `int`: Available budget in euros (can be negative)

**Formula**:
```
availableBudget = totalBudget - spentAmount - (reservedBudget / 100) + (reimbursedIncome / 100)
```

**Example**:
```dart
final available = BudgetCalculator.calculateAvailableBudget(
  budgetAmount: 2000, // €2000 total budget
  spentAmount: 800,   // €800 spent
  reservedBudget: 50000, // €500 reserved (in cents)
  reimbursedIncome: 10000, // €100 reimbursed (in cents)
);
// Result: 800€ available (2000 - 800 - 500 + 100)
```

---

### getBudgetBreakdown

Gets detailed budget breakdown including reservations.

**Signature**:
```dart
static Map<String, dynamic> getBudgetBreakdown({
  required int budgetAmount,
  required int spentAmount,
  required int reservedBudget,
  int reimbursedIncome = 0,
});
```

**Parameters**:
- `budgetAmount` (int, required): Total budget in euros
- `spentAmount` (int, required): Amount spent in euros
- `reservedBudget` (int, required): Amount reserved in cents
- `reimbursedIncome` (int, default: 0): Amount reimbursed in cents

**Returns**:
- `Map<String, dynamic>` with keys:
  - `totalBudget` (int): Total budget in euros
  - `spentAmount` (int): Amount spent in euros
  - `reservedBudget` (int): Amount reserved in euros
  - `reimbursedIncome` (int): Amount reimbursed in euros
  - `availableBudget` (int): Remaining available in euros
  - `percentageUsed` (double): Percentage of budget used (including reserved)

**Example**:
```dart
final breakdown = BudgetCalculator.getBudgetBreakdown(
  budgetAmount: 2000,
  spentAmount: 800,
  reservedBudget: 50000,
  reimbursedIncome: 10000,
);

// Result:
{
  'totalBudget': 2000,
  'spentAmount': 800,
  'reservedBudget': 500,
  'reimbursedIncome': 100,
  'availableBudget': 800,
  'percentageUsed': 60.0, // (800 + 500 - 100) / 2000 * 100
}
```

---

## Riverpod Provider Contracts

### recurringExpenseListProvider

Provides list of all recurring expenses for current user's group.

**Type**: `FutureProvider<List<RecurringExpenseEntity>>`

**Location**: `lib/features/recurring_expenses/presentation/providers/recurring_expense_provider.dart`

**Signature**:
```dart
@riverpod
Future<List<RecurringExpenseEntity>> recurringExpenseList(
  RecurringExpenseListRef ref,
) async {
  final repository = ref.watch(recurringExpenseRepositoryProvider);
  final result = await repository.getRecurringExpenses();
  return result.fold(
    (failure) => throw failure,
    (expenses) => expenses,
  );
}
```

**Returns**: List of all recurring expenses (active and paused)

**Invalidation Triggers**:
- `createRecurringExpense()` called
- `updateRecurringExpense()` called
- `deleteRecurringExpense()` called
- `pauseRecurringExpense()` called
- `resumeRecurringExpense()` called
- Supabase Realtime update received

**Usage**:
```dart
// In widget
final recurringExpenses = ref.watch(recurringExpenseListProvider);

recurringExpenses.when(
  data: (expenses) => ListView.builder(...),
  loading: () => CircularProgressIndicator(),
  error: (error, stack) => ErrorWidget(error),
);
```

---

### recurringExpenseProvider

Provides a single recurring expense by ID.

**Type**: `FutureProvider<RecurringExpenseEntity>`

**Location**: `lib/features/recurring_expenses/presentation/providers/recurring_expense_provider.dart`

**Signature**:
```dart
@riverpod
Future<RecurringExpenseEntity> recurringExpense(
  RecurringExpenseRef ref,
  String id,
) async {
  final repository = ref.watch(recurringExpenseRepositoryProvider);
  final result = await repository.getRecurringExpense(id: id);
  return result.fold(
    (failure) => throw failure,
    (expense) => expense,
  );
}
```

**Parameters**:
- `id` (String): UUID of recurring expense to retrieve

**Returns**: Single recurring expense entity

**Invalidation Triggers**:
- `updateRecurringExpense(id)` called
- `pauseRecurringExpense(id)` called
- `resumeRecurringExpense(id)` called
- Supabase Realtime update for this ID

**Usage**:
```dart
// In widget
final expense = ref.watch(recurringExpenseProvider(expenseId));

expense.when(
  data: (expense) => ExpenseDetailView(expense),
  loading: () => CircularProgressIndicator(),
  error: (error, stack) => ErrorWidget(error),
);
```

---

### budgetReservationProvider

Provides total reserved budget for current month.

**Type**: `FutureProvider<int>`

**Location**: `lib/features/budgets/presentation/providers/budget_reservation_provider.dart`

**Signature**:
```dart
@riverpod
Future<int> currentMonthReservedBudget(
  CurrentMonthReservedBudgetRef ref,
) async {
  // Watch recurring expenses list (auto-invalidates when list changes)
  final recurringExpenses = await ref.watch(recurringExpenseListProvider.future);

  // Get current month/year
  final now = DateTime.now();
  final month = now.month;
  final year = now.year;

  // Calculate reserved budget (cached until dependencies change)
  return BudgetCalculator.calculateReservedBudget(
    recurringExpenses: recurringExpenses,
    month: month,
    year: year,
  );
}
```

**Returns**: Total reserved budget in cents

**Invalidation Triggers**:
- `recurringExpenseListProvider` invalidates
- Month changes (new budget period)
- `budgetReservationEnabled` toggled for any template

**Caching Strategy**:
- Riverpod automatically caches result
- Recalculates only when dependencies change
- Performance: <50ms calculation, <1ms cached access

**Usage**:
```dart
// In budget widget
final reservedBudget = ref.watch(currentMonthReservedBudgetProvider);

reservedBudget.when(
  data: (amount) => Text('Reserved: €${amount / 100}'),
  loading: () => CircularProgressIndicator(),
  error: (error, stack) => Text('Error loading reservations'),
);
```

---

### reimbursementsListProvider

Provides list of all expenses with reimbursement status.

**Type**: `FutureProvider<List<ExpenseEntity>>`

**Location**: `lib/features/expenses/presentation/providers/reimbursements_provider.dart`

**Signature**:
```dart
@riverpod
Future<List<ExpenseEntity>> reimbursementsList(
  ReimbursementsListRef ref,
) async {
  final repository = ref.watch(expenseRepositoryProvider);
  final result = await repository.getExpenses(
    reimbursementStatus: null, // Get all (filter in UI)
  );

  return result.fold(
    (failure) => throw failure,
    (expenses) => expenses.where((e) =>
      e.reimbursementStatus != ReimbursementStatus.none
    ).toList(),
  );
}
```

**Returns**: List of expenses with `reimbursementStatus = reimbursable` or `reimbursed`

**Invalidation Triggers**:
- Expense created with reimbursement status
- Expense reimbursement status updated
- Expense deleted

**Usage**:
```dart
// In reimbursements screen
final reimbursements = ref.watch(reimbursementsListProvider);

reimbursements.when(
  data: (expenses) {
    final reimbursable = expenses.where((e) => e.reimbursementStatus == ReimbursementStatus.reimbursable);
    final reimbursed = expenses.where((e) => e.reimbursementStatus == ReimbursementStatus.reimbursed);
    // Display grouped lists
  },
  loading: () => CircularProgressIndicator(),
  error: (error, stack) => ErrorWidget(error),
);
```

---

## Background Task Service

### RecurringExpenseScheduler

**Location**: `lib/features/recurring_expenses/infrastructure/recurring_expense_scheduler.dart`

Service for registering and managing background tasks using `workmanager`.

#### registerPeriodicCheck

Registers a periodic background task to check for due recurring expenses.

**Signature**:
```dart
static Future<void> registerPeriodicCheck() async {
  await Workmanager().registerPeriodicTask(
    'recurring-expense-creation',
    'recurring-expense-creation',
    frequency: Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.not_required, // Can work offline
      requiresBatteryNotLow: true,
    ),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );
}
```

**Parameters**: None

**Returns**: `Future<void>`

**Side Effects**:
- Registers background task with platform (Android WorkManager, iOS BackgroundFetch)
- Task runs every 15 minutes (platform minimum)
- Task checks for due recurring expenses and generates instances

**Platform Behavior**:
- **Android**: WorkManager guarantees execution (may be delayed if battery low)
- **iOS**: BackgroundFetch is less reliable (may skip if app not used)

**Note**: User must open app at least once to register the task.

---

#### cancelPeriodicCheck

Cancels the recurring expense background task.

**Signature**:
```dart
static Future<void> cancelPeriodicCheck() async {
  await Workmanager().cancelByUniqueName('recurring-expense-creation');
}
```

**Parameters**: None

**Returns**: `Future<void>`

**Side Effects**:
- Stops background task from running
- Does NOT delete existing recurring expenses or instances

**Use Case**: User disables recurring expenses feature or logs out.

---

## Data Transformation Methods

### Entity Conversions

#### RecurringExpenseEntity.fromDrift

Converts Drift database row to domain entity.

**Signature**:
```dart
factory RecurringExpenseEntity.fromDrift(RecurringExpenseData data) {
  return RecurringExpenseEntity(
    id: data.id,
    userId: data.userId,
    groupId: data.groupId,
    templateExpenseId: data.templateExpenseId,
    amount: data.amount,
    categoryId: data.categoryId,
    merchant: data.merchant,
    notes: data.notes,
    isGroupExpense: data.isGroupExpense,
    frequency: RecurrenceFrequency.fromString(data.frequency),
    anchorDate: data.anchorDate,
    isPaused: data.isPaused,
    lastInstanceCreatedAt: data.lastInstanceCreatedAt,
    nextDueDate: data.nextDueDate,
    budgetReservationEnabled: data.budgetReservationEnabled,
    defaultReimbursementStatus: ReimbursementStatus.fromString(data.defaultReimbursementStatus),
    createdAt: data.createdAt,
    updatedAt: data.updatedAt,
  );
}
```

---

#### RecurringExpenseEntity.toCompanion

Converts domain entity to Drift companion for insert/update.

**Signature**:
```dart
RecurringExpensesCompanion toCompanion() {
  return RecurringExpensesCompanion(
    id: Value(id),
    userId: Value(userId),
    groupId: Value(groupId),
    templateExpenseId: Value(templateExpenseId),
    amount: Value(amount),
    categoryId: Value(categoryId),
    merchant: Value(merchant),
    notes: Value(notes),
    isGroupExpense: Value(isGroupExpense),
    frequency: Value(frequency.value),
    anchorDate: Value(anchorDate),
    isPaused: Value(isPaused),
    lastInstanceCreatedAt: Value(lastInstanceCreatedAt),
    nextDueDate: Value(nextDueDate),
    budgetReservationEnabled: Value(budgetReservationEnabled),
    defaultReimbursementStatus: Value(defaultReimbursementStatus.value),
    createdAt: Value(createdAt),
    updatedAt: Value(updatedAt),
  );
}
```

---

#### RecurringExpenseEntity.fromJson

Converts JSON (Supabase) to domain entity.

**Signature**:
```dart
factory RecurringExpenseEntity.fromJson(Map<String, dynamic> json) {
  return RecurringExpenseEntity(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    groupId: json['group_id'] as String?,
    templateExpenseId: json['template_expense_id'] as String?,
    amount: (json['amount'] as num).toDouble(),
    categoryId: json['category_id'] as String,
    merchant: json['merchant'] as String?,
    notes: json['notes'] as String?,
    isGroupExpense: json['is_group_expense'] as bool,
    frequency: RecurrenceFrequency.fromString(json['frequency'] as String),
    anchorDate: DateTime.parse(json['anchor_date'] as String),
    isPaused: json['is_paused'] as bool,
    lastInstanceCreatedAt: json['last_instance_created_at'] != null
        ? DateTime.parse(json['last_instance_created_at'] as String)
        : null,
    nextDueDate: json['next_due_date'] != null
        ? DateTime.parse(json['next_due_date'] as String)
        : null,
    budgetReservationEnabled: json['budget_reservation_enabled'] as bool,
    defaultReimbursementStatus: ReimbursementStatus.fromString(
      json['default_reimbursement_status'] as String,
    ),
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );
}
```

---

#### RecurringExpenseEntity.toJson

Converts domain entity to JSON (for Supabase).

**Signature**:
```dart
Map<String, dynamic> toJson() {
  return {
    'id': id,
    'user_id': userId,
    'group_id': groupId,
    'template_expense_id': templateExpenseId,
    'amount': amount,
    'category_id': categoryId,
    'merchant': merchant,
    'notes': notes,
    'is_group_expense': isGroupExpense,
    'frequency': frequency.value,
    'anchor_date': anchorDate.toIso8601String(),
    'is_paused': isPaused,
    'last_instance_created_at': lastInstanceCreatedAt?.toIso8601String(),
    'next_due_date': nextDueDate?.toIso8601String(),
    'budget_reservation_enabled': budgetReservationEnabled,
    'default_reimbursement_status': defaultReimbursementStatus.value,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}
```

---

## Enum Definitions

### RecurrenceFrequency

**Location**: `lib/features/recurring_expenses/domain/entities/recurrence_frequency.dart`

```dart
enum RecurrenceFrequency {
  daily('daily'),
  weekly('weekly'),
  monthly('monthly'),
  yearly('yearly');

  const RecurrenceFrequency(this.value);
  final String value;

  static RecurrenceFrequency fromString(String value) {
    return RecurrenceFrequency.values.firstWhere(
      (e) => e.value == value,
      orElse: () => throw ArgumentError('Invalid recurrence frequency: $value'),
    );
  }

  String toDisplayString() {
    switch (this) {
      case RecurrenceFrequency.daily:
        return 'Daily';
      case RecurrenceFrequency.weekly:
        return 'Weekly';
      case RecurrenceFrequency.monthly:
        return 'Monthly';
      case RecurrenceFrequency.yearly:
        return 'Yearly';
    }
  }
}
```

---

## Error Handling

All repository methods use the `Either<Failure, T>` pattern from `dartz` package:

- **Left(Failure)**: Operation failed with specific error type
- **Right(T)**: Operation succeeded with result value

### Failure Types

```dart
// Existing failures from core/errors/failures.dart
abstract class Failure {
  const Failure({this.message});
  final String? message;
}

class ValidationFailure extends Failure {
  const ValidationFailure({required String message}) : super(message: message);
}

class NotFoundFailure extends Failure {
  const NotFoundFailure({String? message}) : super(message: message);
}

class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure({String? message}) : super(message: message);
}

class NetworkFailure extends Failure {
  const NetworkFailure({String? message}) : super(message: message);
}

class ServerFailure extends Failure {
  const ServerFailure({String? message}) : super(message: message);
}
```

### Error Handling Example

```dart
final result = await repository.createRecurringExpense(
  amount: 500,
  categoryId: categoryId,
  frequency: RecurrenceFrequency.monthly,
  anchorDate: DateTime.now(),
);

result.fold(
  (failure) {
    // Handle error
    if (failure is ValidationFailure) {
      showSnackbar('Validation error: ${failure.message}');
    } else if (failure is NetworkFailure) {
      showSnackbar('No internet connection');
    } else {
      showSnackbar('Failed to create recurring expense');
    }
  },
  (expense) {
    // Handle success
    showSnackbar('Recurring expense created');
    ref.invalidate(recurringExpenseListProvider);
  },
);
```

---

## Summary

This API contract provides:

1. **Repository interface** with 9 methods for recurring expense CRUD operations
2. **Domain services** for recurrence calculation and budget reservation
3. **Riverpod providers** for state management and caching
4. **Background task service** for automatic expense instance generation
5. **Data transformation** methods for Drift ↔ Domain ↔ JSON conversions
6. **Error handling** with `Either<Failure, T>` pattern
7. **Performance optimization** via provider caching and strategic invalidation

All contracts follow existing codebase patterns and integrate seamlessly with Feature 010 (Offline Sync) and Feature 012 (Reimbursements).
