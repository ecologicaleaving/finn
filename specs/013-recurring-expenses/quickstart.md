# Quickstart: Recurring Expenses Developer Guide

**Feature**: 013-recurring-expenses
**Phase**: 1 (Design Artifacts)
**Created**: 2026-01-16

---

## Welcome

This guide helps developers quickly understand and work with the recurring expenses feature. Whether you're fixing bugs, adding new functionality, or just exploring the codebase, this document provides the essential context you need.

---

## Table of Contents

1. [High-Level Architecture](#high-level-architecture)
2. [Key Files and Responsibilities](#key-files-and-responsibilities)
3. [How Recurring Expense Creation Works](#how-recurring-expense-creation-works)
4. [How Background Task Generates Instances](#how-background-task-generates-instances)
5. [How Budget Reservation is Calculated](#how-budget-reservation-is-calculated)
6. [Testing Strategy](#testing-strategy)
7. [Common Development Tasks](#common-development-tasks)
8. [Troubleshooting](#troubleshooting)

---

## High-Level Architecture

### Conceptual Model

```
┌─────────────────────────────────────────────────────────────┐
│                    RECURRING EXPENSE                         │
│                                                              │
│  ┌────────────────┐           ┌──────────────────┐          │
│  │   TEMPLATE     │──creates─▶│  EXPENSE INSTANCE│          │
│  │                │           │                   │          │
│  │ • Frequency    │           │ • Amount          │          │
│  │ • Amount       │           │ • Date            │          │
│  │ • Category     │           │ • Category        │          │
│  │ • Anchor Date  │           │ • Merchant        │          │
│  └────────────────┘           └──────────────────┘          │
│         │                              │                     │
│         │                              │                     │
│         ▼                              ▼                     │
│  ┌────────────────┐           ┌──────────────────┐          │
│  │BUDGET          │           │ BUDGET STATS     │          │
│  │RESERVATION     │           │                  │          │
│  │                │           │ • Total Budget   │          │
│  │ • Reserved €   │           │ • Spent          │          │
│  └────────────────┘           │ • Reserved       │          │
│                               │ • Available      │          │
│                               └──────────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

### Architectural Layers

This feature follows Clean Architecture with three layers:

```
┌─────────────────────────────────────────────────────────────┐
│                     PRESENTATION LAYER                       │
│  • Widgets (RecurringExpenseListScreen, etc.)               │
│  • Providers (recurringExpenseListProvider, etc.)           │
│  • State Management (Riverpod)                              │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                      DOMAIN LAYER                            │
│  • Entities (RecurringExpenseEntity)                        │
│  • Repository Interfaces (RecurringExpenseRepository)       │
│  • Services (RecurrenceCalculator)                          │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                       DATA LAYER                             │
│  • Repository Implementations                               │
│  • Data Sources (Local: Drift, Remote: Supabase)           │
│  • Sync Logic (bidirectional Drift ↔ Supabase)             │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

**User Creates Recurring Expense**:
```
User Action (UI)
  │
  ├─▶ Provider (recurringExpenseListProvider)
  │     │
  │     ├─▶ Repository (RecurringExpenseRepository)
  │     │     │
  │     │     ├─▶ Local DataSource (Drift)
  │     │     │     └─▶ Insert into recurring_expenses table
  │     │     │
  │     │     └─▶ Sync Queue (SyncQueueProcessor)
  │     │           └─▶ Upload to Supabase (when online)
  │     │
  │     └─▶ Provider Invalidation (triggers UI update)
  │
  └─▶ Background Task Registration
        └─▶ Workmanager schedules periodic checks
```

**Background Task Creates Instance**:
```
Workmanager (every 15 min)
  │
  ├─▶ Query Drift for due templates (isPaused=false, nextDueDate<=now)
  │
  ├─▶ For each due template:
  │     │
  │     ├─▶ Create expense in OfflineExpenses table
  │     │
  │     ├─▶ Create mapping in RecurringExpenseInstances table
  │     │
  │     ├─▶ Update template (lastInstanceCreatedAt, nextDueDate)
  │     │
  │     └─▶ Queue sync (upload expense to Supabase)
  │
  └─▶ Provider Invalidation (expenseListProvider, budgetStatsProvider)
```

---

## Key Files and Responsibilities

### Domain Layer

| File | Responsibility | Key Methods |
|------|---------------|-------------|
| `lib/features/recurring_expenses/domain/entities/recurring_expense_entity.dart` | Domain entity representing a recurring expense template | `fromDrift()`, `toCompanion()`, `fromJson()`, `toJson()` |
| `lib/features/recurring_expenses/domain/entities/recurrence_frequency.dart` | Enum for recurrence frequencies (daily/weekly/monthly/yearly) | `fromString()`, `toDisplayString()` |
| `lib/features/recurring_expenses/domain/repositories/recurring_expense_repository.dart` | Repository interface (abstract class) | `createRecurringExpense()`, `updateRecurringExpense()`, `pauseRecurringExpense()`, `deleteRecurringExpense()`, `generateExpenseInstance()` |
| `lib/features/recurring_expenses/domain/services/recurrence_calculator.dart` | Recurrence calculation logic | `calculateNextDueDate()`, `calculateBudgetReservation()` |

### Data Layer

| File | Responsibility | Key Methods |
|------|---------------|-------------|
| `lib/features/recurring_expenses/data/repositories/recurring_expense_repository_impl.dart` | Repository implementation (Drift + Supabase sync) | Implements all RecurringExpenseRepository methods |
| `lib/features/recurring_expenses/data/datasources/recurring_expense_local_datasource.dart` | Drift database operations | `insertRecurringExpense()`, `updateRecurringExpense()`, `deleteRecurringExpense()`, `getAllRecurringExpenses()` |
| `lib/features/recurring_expenses/data/datasources/recurring_expense_remote_datasource.dart` | Supabase operations + Realtime subscriptions | `createRecurringExpense()`, `updateRecurringExpense()`, `watchRecurringExpenses()` |
| `lib/core/database/drift/tables/recurring_expenses_table.dart` | Drift table definition for recurring_expenses | Table schema, indexes, constraints |
| `lib/core/database/drift/tables/recurring_expense_instances_table.dart` | Drift table definition for recurring_expense_instances (mapping) | Table schema, indexes |

### Presentation Layer

| File | Responsibility | Key Widgets/Providers |
|------|---------------|----------------------|
| `lib/features/recurring_expenses/presentation/providers/recurring_expense_provider.dart` | Riverpod providers for state management | `recurringExpenseListProvider`, `recurringExpenseProvider(id)` |
| `lib/features/recurring_expenses/presentation/screens/recurring_expense_list_screen.dart` | Settings > Recurring Expenses screen | `RecurringExpenseListScreen` widget |
| `lib/features/recurring_expenses/presentation/screens/recurring_expense_form_screen.dart` | Create/edit recurring expense form | `RecurringExpenseFormScreen` widget |
| `lib/features/recurring_expenses/presentation/widgets/recurring_expense_card.dart` | List item widget for recurring expense | `RecurringExpenseCard` widget |
| `lib/features/expenses/presentation/screens/reimbursements_screen.dart` | Settings > Reimbursements screen | `ReimbursementsScreen` widget |

### Infrastructure

| File | Responsibility | Key Methods |
|------|---------------|-------------|
| `lib/features/recurring_expenses/infrastructure/recurring_expense_scheduler.dart` | Background task registration (workmanager) | `registerPeriodicCheck()`, `cancelPeriodicCheck()`, `recurringExpenseCallbackDispatcher()` |
| `lib/features/budgets/presentation/providers/budget_reservation_provider.dart` | Budget reservation calculation provider | `currentMonthReservedBudgetProvider` |
| `lib/core/utils/budget_calculator.dart` | Budget calculation utilities (EXTENDED) | `calculateReservedBudget()`, `calculateAvailableBudget()`, `getBudgetBreakdown()` |

### Database

| File | Responsibility | Migration Version |
|------|---------------|-------------------|
| `lib/features/offline/data/local/offline_database.dart` | Main Drift database class | Schema version 4 (adds recurring_expenses tables) |
| `supabase/migrations/20260116_001_create_recurring_expenses.sql` | Supabase migration (tables) | Creates recurring_expenses, recurring_expense_instances |
| `supabase/migrations/20260116_002_recurring_expenses_rls.sql` | Supabase migration (RLS policies) | Enables RLS, creates policies for multi-user isolation |

---

## How Recurring Expense Creation Works

### Flow Diagram

```
┌────────────────────────────────────────────────────────────────┐
│ 1. USER CREATES RECURRING EXPENSE                              │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 2. RecurringExpenseFormScreen                                  │
│    • User fills form (amount, category, frequency, etc.)       │
│    • Validation: amount > 0, category selected, etc.           │
│    • User taps "Save"                                          │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 3. Provider: recurringExpenseListProvider.notifier             │
│    • Calls repository.createRecurringExpense()                 │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 4. Repository: RecurringExpenseRepositoryImpl                  │
│    • Validates input (amount, category, etc.)                  │
│    • Generates UUID for new template                           │
│    • Calculates nextDueDate from anchorDate                    │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 5. Local DataSource: RecurringExpenseLocalDataSource           │
│    • Insert into Drift recurring_expenses table                │
│    • Sets createdAt, updatedAt timestamps                      │
│    • Returns created RecurringExpenseEntity                    │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 6. Sync Queue: SyncQueueProcessor                              │
│    • Creates sync queue item (operation: 'create')             │
│    • Payload: JSON-serialized recurring expense                │
│    • syncStatus: 'pending'                                     │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 7. Background Sync (when online)                               │
│    • SyncQueueProcessor processes pending items                │
│    • Uploads to Supabase recurring_expenses table              │
│    • Updates syncStatus: 'completed'                           │
│    • Supabase Realtime broadcasts to other devices             │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 8. Provider Invalidation                                       │
│    • recurringExpenseListProvider invalidated                  │
│    • UI re-fetches data and updates                            │
│    • User sees new recurring expense in list                   │
└────────────────────────────────────────────────────────────────┘
```

### Code Example

```dart
// In RecurringExpenseFormScreen
void _saveRecurringExpense() async {
  final repository = ref.read(recurringExpenseRepositoryProvider);

  final result = await repository.createRecurringExpense(
    amount: _amountController.value,
    categoryId: _selectedCategory.id,
    frequency: _selectedFrequency, // RecurrenceFrequency.monthly
    anchorDate: _selectedDate, // e.g., DateTime(2026, 1, 15)
    merchant: _merchantController.text,
    notes: _notesController.text,
    isGroupExpense: true,
    budgetReservationEnabled: _reserveBudget,
  );

  result.fold(
    (failure) => showErrorSnackbar(failure.message ?? 'Failed to create'),
    (expense) {
      ref.invalidate(recurringExpenseListProvider);
      Navigator.pop(context);
      showSuccessSnackbar('Recurring expense created');
    },
  );
}
```

---

## How Background Task Generates Instances

### Flow Diagram

```
┌────────────────────────────────────────────────────────────────┐
│ 1. WORKMANAGER TRIGGER (every 15 minutes)                      │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 2. recurringExpenseCallbackDispatcher()                        │
│    • Initialize dependencies (Drift database, Supabase client) │
│    • Get current time in local timezone                        │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 3. Query Active Templates                                      │
│    • SELECT * FROM recurring_expenses                          │
│      WHERE is_paused = false                                   │
│        AND next_due_date <= NOW()                              │
│    • Uses index: recurring_expenses_active_idx                 │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 4. For Each Due Template                                       │
│    • Calculate nextDueDate using RecurrenceCalculator          │
│    • Check if instance is due (_isDueNow())                    │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 5. Create Expense Instance                                     │
│    • Insert into OfflineExpenses table                         │
│      - id: new UUID                                            │
│      - amount: template.amount                                 │
│      - date: scheduledDate (nextDueDate)                       │
│      - categoryId: template.categoryId                         │
│      - recurringExpenseId: template.id                         │
│      - isRecurringInstance: true                               │
│      - reimbursementStatus: template.defaultReimbursementStatus│
│      - syncStatus: 'pending'                                   │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 6. Create Mapping Record                                       │
│    • Insert into RecurringExpenseInstances table               │
│      - recurringExpenseId: template.id                         │
│      - expenseId: newly created expense.id                     │
│      - scheduledDate: nextDueDate                              │
│      - createdAt: now                                          │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 7. Update Template                                             │
│    • UPDATE recurring_expenses SET                             │
│        last_instance_created_at = NOW(),                       │
│        next_due_date = [calculated next occurrence]            │
│      WHERE id = template.id                                    │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 8. Queue Expense Sync                                          │
│    • SyncQueueProcessor queues expense for upload              │
│    • Background sync uploads to Supabase when online           │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 9. Provider Invalidation (via Realtime)                        │
│    • expenseListProvider invalidated                           │
│    • budgetStatsProvider invalidated                           │
│    • UI updates to show new expense                            │
└────────────────────────────────────────────────────────────────┘
```

### Code Example

```dart
// In RecurringExpenseScheduler.recurringExpenseCallbackDispatcher()

@pragma('vm:entry-point')
void recurringExpenseCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final database = OfflineDatabase();
      final now = tz.TZDateTime.now(tz.local);

      // Query active templates
      final templates = await database.select(database.recurringExpenses)
        .where((tbl) => tbl.isPaused.equals(false))
        .get();

      // For each template, check if due
      for (final template in templates) {
        final nextDue = RecurrenceCalculator.calculateNextDueDate(
          anchorDate: template.anchorDate,
          frequency: RecurrenceFrequency.fromString(template.frequency),
          lastCreated: template.lastInstanceCreatedAt,
        );

        if (nextDue != null && _isDueNow(nextDue, now)) {
          // Create expense instance
          final expenseId = const Uuid().v4();
          await database.into(database.offlineExpenses).insert(
            OfflineExpensesCompanion.insert(
              id: expenseId,
              userId: template.userId,
              amount: template.amount,
              date: nextDue,
              categoryId: template.categoryId,
              merchant: Value(template.merchant),
              notes: Value(template.notes),
              isGroupExpense: template.isGroupExpense,
              recurringExpenseId: Value(template.id),
              isRecurringInstance: const Value(true),
              reimbursementStatus: Value(template.defaultReimbursementStatus),
              syncStatus: const Value('pending'),
              localCreatedAt: now,
              localUpdatedAt: now,
            ),
          );

          // Create mapping
          await database.into(database.recurringExpenseInstances).insert(
            RecurringExpenseInstancesCompanion.insert(
              recurringExpenseId: template.id,
              expenseId: expenseId,
              scheduledDate: nextDue,
              createdAt: now,
            ),
          );

          // Update template
          await (database.update(database.recurringExpenses)
            ..where((tbl) => tbl.id.equals(template.id)))
            .write(RecurringExpensesCompanion(
              lastInstanceCreatedAt: Value(now),
              nextDueDate: Value(_calculateNextDueDate(template, nextDue)),
            ));
        }
      }

      await database.close();
      return true;
    } catch (e) {
      print('Recurring expense creation error: $e');
      return false;
    }
  });
}
```

### Timezone Handling

All date calculations use the `timezone` package with local timezone:

```dart
// Always use tz.TZDateTime for timezone-aware calculations
final now = tz.TZDateTime.now(tz.local);
final anchor = tz.TZDateTime.from(template.anchorDate, tz.local);

// Monthly recurrence preserves day-of-month
final nextMonth = tz.TZDateTime(
  tz.local,
  anchor.year,
  anchor.month + 1,
  anchor.day, // Preserve day
);

// Edge case: Jan 31 → Feb 28/29 (last day of shorter month)
```

---

## How Budget Reservation is Calculated

### Calculation Flow

```
┌────────────────────────────────────────────────────────────────┐
│ 1. USER VIEWS BUDGET SCREEN                                    │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 2. BudgetStatsProvider                                         │
│    • Watches multiple providers:                               │
│      - totalBudgetProvider                                     │
│      - spentAmountProvider                                     │
│      - currentMonthReservedBudgetProvider (NEW)                │
│      - reimbursedIncomeProvider                                │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 3. currentMonthReservedBudgetProvider                          │
│    • Watches recurringExpenseListProvider                      │
│    • Gets current month/year                                   │
│    • Calls BudgetCalculator.calculateReservedBudget()          │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 4. BudgetCalculator.calculateReservedBudget()                  │
│    • Filters active templates (isPaused=false)                 │
│    • Filters budget reservation enabled                        │
│    • For each template:                                        │
│      - Calculate nextDueDate                                   │
│      - Check if due in current month                           │
│      - If yes, add amount to reservation                       │
│    • Returns total reserved amount in cents                    │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 5. BudgetCalculator.calculateAvailableBudget()                 │
│    • Formula:                                                  │
│      available = total - spent - (reserved/100) + (reimb/100)  │
│    • Example:                                                  │
│      total: 2000€                                              │
│      spent: 800€                                               │
│      reserved: 50000 cents (500€)                              │
│      reimbursed: 10000 cents (100€)                            │
│      available: 2000 - 800 - 500 + 100 = 800€                 │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ 6. UI DISPLAYS BUDGET BREAKDOWN                                │
│    • Total Budget: €2000                                       │
│    • Spent: €800                                               │
│    • Reserved: €500                                            │
│    • Available: €800                                           │
│    • Progress bar: 60% (800+500-100)/2000                      │
└────────────────────────────────────────────────────────────────┘
```

### Code Example

```dart
// In BudgetCalculator (lib/core/utils/budget_calculator.dart)

static int calculateReservedBudget({
  required List<RecurringExpenseEntity> recurringExpenses,
  required int month,
  required int year,
}) {
  if (recurringExpenses.isEmpty) return 0;

  final periodStart = TimezoneHandler.getMonthStart(year, month);
  final periodEnd = TimezoneHandler.getMonthEnd(year, month);

  return recurringExpenses.fold<int>(0, (sum, template) {
    // Only count active templates with budget reservation enabled
    if (template.isPaused || !template.budgetReservationEnabled) {
      return sum;
    }

    // Calculate next due date
    final nextDue = RecurrenceCalculator.calculateNextDueDate(
      anchorDate: template.anchorDate,
      frequency: template.frequency,
      lastCreated: template.lastInstanceCreatedAt,
    );

    if (nextDue == null) return sum;

    // If due in this period, reserve the amount
    if (nextDue.isAfter(periodStart) && nextDue.isBefore(periodEnd)) {
      return sum + (template.amount * 100).round(); // Convert to cents
    }

    return sum;
  });
}
```

### Caching Strategy

Riverpod automatically caches the budget reservation calculation:

```dart
@riverpod
Future<int> currentMonthReservedBudget(CurrentMonthReservedBudgetRef ref) async {
  // This provider watches recurringExpenseListProvider
  final recurringExpenses = await ref.watch(recurringExpenseListProvider.future);

  // Get current month/year
  final now = DateTime.now();

  // Calculate (result is cached until dependencies change)
  return BudgetCalculator.calculateReservedBudget(
    recurringExpenses: recurringExpenses,
    month: now.month,
    year: now.year,
  );
}
```

**Performance**:
- First load: ~10ms (calculation + database query)
- Subsequent loads: <1ms (cached result)
- Invalidation triggers: recurring expense created/updated/deleted, month changes

---

## Testing Strategy

### Unit Tests

**Location**: `test/features/recurring_expenses/domain/services/recurrence_calculator_test.dart`

Test the recurrence calculation logic:

```dart
void main() {
  group('RecurrenceCalculator.calculateNextDueDate', () {
    test('daily recurrence adds exactly 1 day', () {
      final anchor = DateTime(2026, 1, 15);
      final nextDue = RecurrenceCalculator.calculateNextDueDate(
        anchorDate: anchor,
        frequency: RecurrenceFrequency.daily,
        lastCreated: anchor,
      );

      expect(nextDue, DateTime(2026, 1, 16));
    });

    test('monthly recurrence preserves day-of-month', () {
      final anchor = DateTime(2026, 1, 15);
      final nextDue = RecurrenceCalculator.calculateNextDueDate(
        anchorDate: anchor,
        frequency: RecurrenceFrequency.monthly,
        lastCreated: anchor,
      );

      expect(nextDue, DateTime(2026, 2, 15));
    });

    test('monthly recurrence handles month-end edge case (Jan 31 → Feb 28)', () {
      final anchor = DateTime(2026, 1, 31);
      final nextDue = RecurrenceCalculator.calculateNextDueDate(
        anchorDate: anchor,
        frequency: RecurrenceFrequency.monthly,
        lastCreated: anchor,
      );

      expect(nextDue, DateTime(2026, 2, 28)); // Last day of February
    });

    test('yearly recurrence handles leap year edge case', () {
      final anchor = DateTime(2024, 2, 29); // Leap year
      final nextDue = RecurrenceCalculator.calculateNextDueDate(
        anchorDate: anchor,
        frequency: RecurrenceFrequency.yearly,
        lastCreated: anchor,
      );

      expect(nextDue, DateTime(2025, 2, 28)); // Non-leap year
    });
  });

  group('RecurrenceCalculator.calculateBudgetReservation', () {
    test('reserves budget for active template due in period', () {
      final template = RecurringExpenseEntity(
        id: 'test-id',
        amount: 500.0,
        frequency: RecurrenceFrequency.monthly,
        anchorDate: DateTime(2026, 1, 15),
        isPaused: false,
        budgetReservationEnabled: true,
        // ... other fields
      );

      final reservation = RecurrenceCalculator.calculateBudgetReservation(
        template: template,
        month: 1, // January
        year: 2026,
      );

      expect(reservation, 50000); // 500€ in cents
    });

    test('does not reserve budget for paused template', () {
      final template = RecurringExpenseEntity(
        id: 'test-id',
        amount: 500.0,
        isPaused: true, // Paused
        budgetReservationEnabled: true,
        // ... other fields
      );

      final reservation = RecurrenceCalculator.calculateBudgetReservation(
        template: template,
        month: 1,
        year: 2026,
      );

      expect(reservation, 0); // No reservation
    });
  });
}
```

### Integration Tests

**Location**: `test/features/recurring_expenses/data/repositories/recurring_expense_repository_impl_test.dart`

Test repository operations with Drift database:

```dart
void main() {
  late OfflineDatabase database;
  late RecurringExpenseRepositoryImpl repository;

  setUp(() {
    database = OfflineDatabase.forTesting();
    repository = RecurringExpenseRepositoryImpl(
      localDataSource: RecurringExpenseLocalDataSourceImpl(database: database),
      remoteDataSource: MockRecurringExpenseRemoteDataSource(),
    );
  });

  tearDown(() async {
    await database.close();
  });

  group('createRecurringExpense', () {
    test('creates recurring expense and queues sync', () async {
      final result = await repository.createRecurringExpense(
        amount: 500.0,
        categoryId: 'category-id',
        frequency: RecurrenceFrequency.monthly,
        anchorDate: DateTime(2026, 1, 15),
      );

      expect(result.isRight(), true);
      result.fold(
        (failure) => fail('Should succeed'),
        (expense) {
          expect(expense.amount, 500.0);
          expect(expense.frequency, RecurrenceFrequency.monthly);
          expect(expense.nextDueDate, isNotNull);
        },
      );

      // Verify stored in Drift
      final templates = await database.select(database.recurringExpenses).get();
      expect(templates.length, 1);
    });
  });
}
```

### Widget Tests

**Location**: `test/features/recurring_expenses/presentation/screens/recurring_expense_list_screen_test.dart`

Test UI components:

```dart
void main() {
  testWidgets('RecurringExpenseListScreen displays recurring expenses', (tester) async {
    final container = ProviderContainer(
      overrides: [
        recurringExpenseListProvider.overrideWith((ref) async => [
          RecurringExpenseEntity(
            id: '1',
            amount: 500.0,
            frequency: RecurrenceFrequency.monthly,
            // ... other fields
          ),
        ]),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: RecurringExpenseListScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify expense displayed
    expect(find.text('€500.00'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
  });
}
```

### End-to-End Tests

**Location**: `integration_test/recurring_expenses_flow_test.dart`

Test complete user flows:

```dart
void main() {
  testWidgets('User creates recurring expense and it generates instances', (tester) async {
    // 1. Navigate to Settings > Recurring Expenses
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recurring Expenses'));
    await tester.pumpAndSettle();

    // 2. Create new recurring expense
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(Key('amount_field')), '500');
    await tester.tap(find.text('Monthly'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // 3. Verify expense created
    expect(find.text('€500.00'), findsOneWidget);

    // 4. Trigger background task (simulate)
    // (In real test, would wait for workmanager or manually trigger)

    // 5. Verify instance created in expenses list
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();

    expect(find.text('€500.00'), findsAtLeastNWidgets(1));
  });
}
```

---

## Common Development Tasks

### Task 1: Add a New Recurrence Frequency

**Requirement**: Add "bi-weekly" (every 2 weeks) recurrence frequency.

**Steps**:

1. **Update enum** (`lib/features/recurring_expenses/domain/entities/recurrence_frequency.dart`):
   ```dart
   enum RecurrenceFrequency {
     daily('daily'),
     weekly('weekly'),
     biweekly('biweekly'), // NEW
     monthly('monthly'),
     yearly('yearly');
   }
   ```

2. **Update calculation** (`lib/features/recurring_expenses/domain/services/recurrence_calculator.dart`):
   ```dart
   case RecurrenceFrequency.biweekly:
     nextDate = reference.add(const Duration(days: 14)); // 2 weeks
     break;
   ```

3. **Update database constraint** (`lib/core/database/drift/tables/recurring_expenses_table.dart`):
   ```dart
   TextColumn get frequency => text()
     .check(frequency.isIn(['daily', 'weekly', 'biweekly', 'monthly', 'yearly']))();
   ```

4. **Update Supabase migration**:
   ```sql
   ALTER TABLE recurring_expenses DROP CONSTRAINT recurring_expenses_frequency_check;
   ALTER TABLE recurring_expenses ADD CONSTRAINT recurring_expenses_frequency_check
     CHECK (frequency IN ('daily', 'weekly', 'biweekly', 'monthly', 'yearly'));
   ```

5. **Update UI** (frequency picker in form):
   ```dart
   DropdownButton<RecurrenceFrequency>(
     items: RecurrenceFrequency.values.map((freq) =>
       DropdownMenuItem(value: freq, child: Text(freq.toDisplayString()))
     ).toList(),
   );
   ```

6. **Add tests**:
   ```dart
   test('biweekly recurrence adds exactly 14 days', () {
     final nextDue = RecurrenceCalculator.calculateNextDueDate(
       anchorDate: DateTime(2026, 1, 1),
       frequency: RecurrenceFrequency.biweekly,
       lastCreated: DateTime(2026, 1, 1),
     );
     expect(nextDue, DateTime(2026, 1, 15));
   });
   ```

---

### Task 2: Modify Budget Reservation Calculation

**Requirement**: Change budget reservation to reserve for all occurrences in the current month (not just the next one).

**Steps**:

1. **Update calculation** (`lib/core/utils/budget_calculator.dart`):
   ```dart
   static int calculateReservedBudget({
     required List<RecurringExpenseEntity> recurringExpenses,
     required int month,
     required int year,
   }) {
     final periodStart = TimezoneHandler.getMonthStart(year, month);
     final periodEnd = TimezoneHandler.getMonthEnd(year, month);

     return recurringExpenses.fold<int>(0, (sum, template) {
       if (template.isPaused || !template.budgetReservationEnabled) return sum;

       // NEW: Count ALL occurrences in the month
       int monthlyReservation = 0;
       DateTime? currentDue = RecurrenceCalculator.calculateNextDueDate(
         anchorDate: template.anchorDate,
         frequency: template.frequency,
         lastCreated: template.lastInstanceCreatedAt,
       );

       while (currentDue != null &&
              currentDue.isAfter(periodStart) &&
              currentDue.isBefore(periodEnd)) {
         monthlyReservation += (template.amount * 100).round();

         // Calculate next occurrence
         currentDue = RecurrenceCalculator.calculateNextDueDate(
           anchorDate: template.anchorDate,
           frequency: template.frequency,
           lastCreated: currentDue,
         );
       }

       return sum + monthlyReservation;
     });
   }
   ```

2. **Update tests**:
   ```dart
   test('reserves budget for multiple occurrences in same month', () {
     final template = RecurringExpenseEntity(
       amount: 100.0,
       frequency: RecurrenceFrequency.weekly,
       anchorDate: DateTime(2026, 1, 1),
       budgetReservationEnabled: true,
       // ... other fields
     );

     final reservation = BudgetCalculator.calculateReservedBudget(
       recurringExpenses: [template],
       month: 1,
       year: 2026,
     );

     // 4 weeks in January = 4 occurrences = 400€
     expect(reservation, 40000); // 400€ in cents
   });
   ```

---

### Task 3: Add "Skip Next Occurrence" Feature

**Requirement**: Allow users to skip the next occurrence of a recurring expense without pausing the entire template.

**Steps**:

1. **Add field to entity** (`lib/features/recurring_expenses/domain/entities/recurring_expense_entity.dart`):
   ```dart
   class RecurringExpenseEntity extends Equatable {
     final DateTime? skipNextOccurrence; // NEW

     // ... other fields
   }
   ```

2. **Add field to Drift table** (`lib/core/database/drift/tables/recurring_expenses_table.dart`):
   ```dart
   DateTimeColumn get skipNextOccurrence => dateTime().nullable()();
   ```

3. **Update database migration**:
   ```dart
   if (from < 5) {
     await m.addColumn(recurringExpenses, recurringExpenses.skipNextOccurrence);
   }
   ```

4. **Update background task logic** (`lib/features/recurring_expenses/infrastructure/recurring_expense_scheduler.dart`):
   ```dart
   if (nextDue != null && _isDueNow(nextDue, now)) {
     // NEW: Check if this occurrence should be skipped
     if (template.skipNextOccurrence != null &&
         _isSameDay(nextDue, template.skipNextOccurrence)) {
       // Skip this occurrence, clear skip flag, calculate next
       await database.update(database.recurringExpenses)
         ..where((tbl) => tbl.id.equals(template.id))
         ..write(RecurringExpensesCompanion(
           skipNextOccurrence: Value(null),
           nextDueDate: Value(_calculateNextDueDate(template, nextDue)),
         ));
       continue; // Don't create instance
     }

     // Create instance as normal...
   }
   ```

5. **Add repository method**:
   ```dart
   Future<Either<Failure, RecurringExpenseEntity>> skipNextOccurrence({
     required String id,
   });
   ```

6. **Add UI button** (in recurring expense detail screen):
   ```dart
   ElevatedButton(
     onPressed: () async {
       await repository.skipNextOccurrence(id: expense.id);
       ref.invalidate(recurringExpenseProvider(expense.id));
     },
     child: Text('Skip Next Occurrence'),
   );
   ```

---

### Task 4: Debug Background Task Not Running

**Symptoms**: Recurring expenses are not generating instances automatically.

**Debugging Steps**:

1. **Check if background task is registered**:
   ```dart
   // In app initialization (main.dart or similar)
   await RecurringExpenseScheduler.registerPeriodicCheck();
   ```

2. **Add logging to background task**:
   ```dart
   @pragma('vm:entry-point')
   void recurringExpenseCallbackDispatcher() {
     Workmanager().executeTask((task, inputData) async {
       print('[RecurringExpense] Background task started at ${DateTime.now()}');

       try {
         final database = OfflineDatabase();
         final templates = await database.select(database.recurringExpenses).get();
         print('[RecurringExpense] Found ${templates.length} templates');

         // ... rest of logic
       } catch (e, stack) {
         print('[RecurringExpense] ERROR: $e');
         print('[RecurringExpense] Stack trace: $stack');
       }
     });
   }
   ```

3. **Test background task manually**:
   ```dart
   // In debug screen or test
   await Workmanager().registerOneOffTask(
     'test-recurring-expense',
     'recurring-expense-creation',
     initialDelay: Duration(seconds: 5),
   );
   ```

4. **Check platform-specific issues**:
   - **Android**: Check if battery optimization is disabled for the app
   - **iOS**: Background fetch may be delayed/skipped if app not used regularly
   - **Both**: Check if workmanager is initialized in `main.dart`:
     ```dart
     await Workmanager().initialize(recurringExpenseCallbackDispatcher);
     ```

5. **Verify constraints**:
   ```dart
   // Check if battery constraint is too restrictive
   Constraints(
     requiresBatteryNotLow: false, // Try disabling for testing
   )
   ```

---

### Task 5: Add Analytics for Recurring Expenses

**Requirement**: Track how many recurring expenses are created, paused, and deleted.

**Steps**:

1. **Add analytics service** (assuming Firebase Analytics or similar):
   ```dart
   // lib/core/analytics/analytics_service.dart
   class AnalyticsService {
     static void logRecurringExpenseCreated({
       required RecurrenceFrequency frequency,
       required bool budgetReservationEnabled,
     }) {
       FirebaseAnalytics.instance.logEvent(
         name: 'recurring_expense_created',
         parameters: {
           'frequency': frequency.value,
           'budget_reservation': budgetReservationEnabled,
         },
       );
     }

     static void logRecurringExpensePaused() {
       FirebaseAnalytics.instance.logEvent(name: 'recurring_expense_paused');
     }

     static void logRecurringExpenseDeleted({required bool deleteInstances}) {
       FirebaseAnalytics.instance.logEvent(
         name: 'recurring_expense_deleted',
         parameters: {'delete_instances': deleteInstances},
       );
     }
   }
   ```

2. **Add analytics calls to repository**:
   ```dart
   // In RecurringExpenseRepositoryImpl.createRecurringExpense()
   Future<Either<Failure, RecurringExpenseEntity>> createRecurringExpense({...}) async {
     // ... creation logic

     final result = await localDataSource.insertRecurringExpense(entity);

     if (result.isRight()) {
       AnalyticsService.logRecurringExpenseCreated(
         frequency: frequency,
         budgetReservationEnabled: budgetReservationEnabled,
       );
     }

     return result;
   }
   ```

3. **Add dashboards** (in analytics platform):
   - Total recurring expenses created (by frequency)
   - Pause rate (paused / created)
   - Deletion rate (deleted / created)
   - Budget reservation adoption (% with reservation enabled)

---

## Troubleshooting

### Issue 1: Recurring Expense Not Creating Instances

**Symptoms**: Template exists, but no instances are generated.

**Checklist**:
- [ ] Is `isPaused = false`?
- [ ] Is `nextDueDate` in the past or today?
- [ ] Is background task registered? (Check logs)
- [ ] Is background task running? (Check platform battery optimization)
- [ ] Are there any errors in background task logs?
- [ ] Is Drift database accessible from background task?

**Solution**:
```dart
// Manually trigger instance creation for testing
final repository = ref.read(recurringExpenseRepositoryProvider);
await repository.generateExpenseInstance(
  recurringExpenseId: 'template-id',
  scheduledDate: DateTime.now(),
);
```

---

### Issue 2: Budget Reservation Calculation is Wrong

**Symptoms**: Reserved budget doesn't match expected amount.

**Checklist**:
- [ ] Is `budgetReservationEnabled = true` on the template?
- [ ] Is template paused? (Paused templates don't reserve budget)
- [ ] Is `nextDueDate` within the current month?
- [ ] Are you viewing the correct budget period (month/year)?
- [ ] Is provider cache stale? (Try invalidating manually)

**Debug Code**:
```dart
// Check reservation calculation manually
final templates = await ref.read(recurringExpenseListProvider.future);
final activeReservations = templates.where((t) =>
  !t.isPaused && t.budgetReservationEnabled
).toList();

print('Active reservations: ${activeReservations.length}');
for (final t in activeReservations) {
  print('Template ${t.id}: ${t.amount}€, next due: ${t.nextDueDate}');
}

final total = BudgetCalculator.calculateReservedBudget(
  recurringExpenses: activeReservations,
  month: DateTime.now().month,
  year: DateTime.now().year,
);
print('Total reserved: €${total / 100}');
```

---

### Issue 3: Sync Conflict Between Devices

**Symptoms**: Recurring expense shows different values on different devices.

**Cause**: Sync conflict due to concurrent modifications.

**Resolution Strategy**: Last-write-wins (server timestamp wins)

**Debug Steps**:
1. Check `updated_at` timestamp on both devices
2. Check Supabase `recurring_expenses` table for server version
3. Manually trigger sync:
   ```dart
   final processor = ref.read(syncQueueProcessorProvider);
   await processor.processSyncQueue();
   ```
4. Check for sync errors in `SyncQueueItems` table:
   ```dart
   final failedItems = await database.select(database.syncQueueItems)
     .where((tbl) => tbl.syncStatus.equals('failed'))
     .get();
   print('Failed sync items: ${failedItems.length}');
   ```

---

### Issue 4: Performance Degradation with Many Recurring Expenses

**Symptoms**: Budget screen loads slowly with 50+ recurring expenses.

**Diagnosis**:
1. Profile budget calculation:
   ```dart
   final stopwatch = Stopwatch()..start();
   final reserved = await ref.read(currentMonthReservedBudgetProvider.future);
   stopwatch.stop();
   print('Budget calculation took: ${stopwatch.elapsedMilliseconds}ms');
   ```

2. Check database query performance:
   ```sql
   EXPLAIN QUERY PLAN
   SELECT * FROM recurring_expenses
   WHERE is_paused = false AND budget_reservation_enabled = true;
   ```

**Optimization**:
- Ensure indexes are created (see data-model.md)
- Cache aggressively with Riverpod
- Consider pre-calculating `nextDueDate` and storing in database (already done)
- Limit query to only active templates

---

## Additional Resources

- **Feature Specification**: `specs/013-recurring-expenses/spec.md`
- **Research**: `specs/013-recurring-expenses/research.md`
- **Data Model**: `specs/013-recurring-expenses/data-model.md`
- **API Contracts**: `specs/013-recurring-expenses/contracts/recurring_expenses_api.md`
- **Workmanager Docs**: https://pub.dev/packages/workmanager
- **Timezone Package**: https://pub.dev/packages/timezone
- **Drift Documentation**: https://drift.simonbinder.eu/
- **Riverpod Caching**: https://riverpod.dev/docs/concepts/caching

---

## Getting Help

If you're stuck or have questions:

1. **Check existing code**: Look at how similar features (expenses, income sources) are implemented
2. **Read research doc**: `research.md` explains all technical decisions
3. **Run tests**: Tests often document expected behavior
4. **Ask team**: Reach out to team members familiar with offline sync or budget calculations

Happy coding!
