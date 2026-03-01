# Recurring Expenses Implementation Research

**Feature**: 013-recurring-expenses
**Date**: 2026-01-16
**Purpose**: Resolve technical unknowns and establish implementation patterns for recurring expense functionality

---

## 1. Workmanager Background Task Strategy

### Decision

Use **workmanager** with 15-minute periodic tasks constrained by network connectivity and battery status. Implement timezone-aware scheduling using the existing `TimezoneHandler` utility and `timezone` package already in the project.

### Rationale

- **Already Integrated**: The project already uses `workmanager: ^0.9.0` (see `pubspec.yaml`) and has a working implementation in `BackgroundSyncService` (Feature 010)
- **Battery Efficient**: Workmanager uses Android WorkManager and iOS BackgroundFetch, which are platform-optimized for battery efficiency
- **Proven Pattern**: Existing implementation in `lib/features/offline/infrastructure/background_sync_service.dart` demonstrates successful background task execution
- **Minimum Interval**: 15-minute interval is the minimum allowed by both Android WorkManager and iOS BackgroundFetch, balancing timeliness with battery efficiency
- **Constraint Support**: Built-in support for network connectivity and battery level constraints prevents wasteful task execution
- **Timezone Support**: Existing `TimezoneHandler` class provides all necessary utilities for timezone-aware date calculations

### Implementation Pattern

```dart
// lib/features/recurring_expenses/infrastructure/recurring_expense_scheduler.dart

import 'package:workmanager/workmanager.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../core/utils/timezone_handler.dart';

class RecurringExpenseScheduler {
  static const String taskName = 'recurring-expense-creation';
  static const Duration checkInterval = Duration(minutes: 15);

  /// Register periodic task to check for due recurring expenses
  static Future<void> registerPeriodicCheck() async {
    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: checkInterval,
      constraints: Constraints(
        networkType: NetworkType.not_required, // Can work offline
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }

  /// Cancel periodic checking
  static Future<void> cancelPeriodicCheck() async {
    await Workmanager().cancelByUniqueName(taskName);
  }
}

/// Workmanager callback for recurring expense creation
@pragma('vm:entry-point')
void recurringExpenseCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Initialize dependencies (Drift database, Supabase)
      final database = OfflineDatabase();
      final now = tz.TZDateTime.now(tz.local);

      // Query all active recurring expense templates
      final templates = await database.select(database.recurringExpenses)
        .where((tbl) => tbl.isPaused.equals(false))
        .get();

      // For each template, check if a new instance is due
      for (final template in templates) {
        final nextDueDate = _calculateNextDueDate(
          anchorDate: template.anchorDate,
          frequency: template.frequency,
          lastCreated: template.lastInstanceCreatedAt,
        );

        if (nextDueDate != null && _isDueNow(nextDueDate, now)) {
          // Create expense instance in local Drift database
          await _createExpenseInstance(database, template, nextDueDate);

          // Update template's last_instance_created_at
          await database.update(database.recurringExpenses)
            ..where((tbl) => tbl.id.equals(template.id))
            ..write(RecurringExpensesCompanion(
              lastInstanceCreatedAt: Value(now),
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

/// Check if a recurring expense is due now (within current 15-minute window)
bool _isDueNow(DateTime dueDate, tz.TZDateTime now) {
  // Consider expense due if it's scheduled for today or earlier
  final dueDateLocal = tz.TZDateTime.from(dueDate, tz.local);
  return dueDateLocal.isBefore(now) || _isSameDay(dueDateLocal, now);
}

bool _isSameDay(DateTime date1, DateTime date2) {
  return date1.year == date2.year &&
         date1.month == date2.month &&
         date1.day == date2.day;
}

/// Create an expense instance from a recurring template
Future<void> _createExpenseInstance(
  OfflineDatabase database,
  RecurringExpenseData template,
  DateTime dueDate,
) async {
  // Insert into OfflineExpenses table (will be synced when online)
  await database.into(database.offlineExpenses).insert(
    OfflineExpensesCompanion.insert(
      id: const Uuid().v4(),
      userId: template.userId,
      amount: template.amount,
      date: dueDate,
      categoryId: template.categoryId,
      merchant: Value(template.merchant),
      notes: Value(template.notes),
      isGroupExpense: template.isGroupExpense,
      reimbursementStatus: Value(template.defaultReimbursementStatus),
      syncStatus: const Value('pending'),
      localCreatedAt: tz.TZDateTime.now(tz.local),
      localUpdatedAt: tz.TZDateTime.now(tz.local),
    ),
  );
}
```

### Timezone-Aware Scheduling Implementation

```dart
// lib/features/recurring_expenses/domain/services/recurrence_calculator.dart

import 'package:timezone/timezone.dart' as tz;
import '../../../../core/utils/timezone_handler.dart';
import '../entities/recurrence_frequency.dart';

class RecurrenceCalculator {
  /// Calculate the next occurrence date from an anchor date
  ///
  /// [anchorDate] - The original date when the recurring expense was created
  /// [frequency] - daily, weekly, monthly, or yearly
  /// [lastCreated] - Last time an instance was created (null for first occurrence)
  ///
  /// Returns the next due date in user's local timezone
  static DateTime? calculateNextDueDate({
    required DateTime anchorDate,
    required RecurrenceFrequency frequency,
    DateTime? lastCreated,
  }) {
    final anchor = tz.TZDateTime.from(anchorDate, tz.local);
    final reference = lastCreated != null
        ? tz.TZDateTime.from(lastCreated, tz.local)
        : anchor;

    tz.TZDateTime nextDate;

    switch (frequency) {
      case RecurrenceFrequency.daily:
        nextDate = reference.add(const Duration(days: 1));
        break;

      case RecurrenceFrequency.weekly:
        nextDate = reference.add(const Duration(days: 7));
        break;

      case RecurrenceFrequency.monthly:
        // Handle month-end edge cases (Jan 31 → Feb 28/29)
        nextDate = _addMonths(reference, 1, anchor.day);
        break;

      case RecurrenceFrequency.yearly:
        // Handle leap year edge case (Feb 29 → Feb 28 in non-leap years)
        nextDate = _addYears(reference, 1, anchor.month, anchor.day);
        break;
    }

    return nextDate;
  }

  /// Add months with day-of-month preservation
  ///
  /// Handles edge case: if anchor day doesn't exist in target month,
  /// use the last day of that month (Jan 31 → Feb 28/29)
  static tz.TZDateTime _addMonths(tz.TZDateTime date, int months, int anchorDay) {
    final targetMonth = date.month + months;
    final targetYear = date.year + (targetMonth - 1) ~/ 12;
    final normalizedMonth = ((targetMonth - 1) % 12) + 1;

    // Get last day of target month
    final lastDayOfMonth = _lastDayOfMonth(targetYear, normalizedMonth);
    final day = anchorDay <= lastDayOfMonth ? anchorDay : lastDayOfMonth;

    return tz.TZDateTime(
      tz.local,
      targetYear,
      normalizedMonth,
      day,
      date.hour,
      date.minute,
      date.second,
    );
  }

  /// Add years with month/day preservation
  ///
  /// Handles leap year edge case: Feb 29 → Feb 28 in non-leap years
  static tz.TZDateTime _addYears(tz.TZDateTime date, int years, int anchorMonth, int anchorDay) {
    final targetYear = date.year + years;

    // Check if anchor day exists in target year's month
    final lastDayOfMonth = _lastDayOfMonth(targetYear, anchorMonth);
    final day = anchorDay <= lastDayOfMonth ? anchorDay : lastDayOfMonth;

    return tz.TZDateTime(
      tz.local,
      targetYear,
      anchorMonth,
      day,
      date.hour,
      date.minute,
      date.second,
    );
  }

  /// Get the last day of a given month
  static int _lastDayOfMonth(int year, int month) {
    // First day of next month minus 1 day
    final nextMonth = DateTime(year, month + 1, 1);
    final lastDay = nextMonth.subtract(const Duration(days: 1));
    return lastDay.day;
  }
}
```

### Retry Strategy for Offline/Failure Scenarios

```dart
// Implemented in existing sync infrastructure (Feature 010)
// No changes needed - recurring expense instances are created in OfflineExpenses table
// and will be synced using the existing SyncQueueProcessor with exponential backoff

// Key behaviors from existing implementation:
// 1. Created in local Drift database immediately (no network required)
// 2. Sync queue item created with 'pending' status
// 3. Background sync (every 15 min) processes queue with constraints:
//    - Network available
//    - Battery not low
// 4. Exponential backoff on failure:
//    - Retry 1: immediate
//    - Retry 2: 1 minute
//    - Retry 3: 5 minutes
//    - Retry 4+: 15 minutes
// 5. Max retry attempts: 10 (then marked as 'failed')
```

### Alternatives Considered

- **flutter_local_notifications with alarms**: Rejected - Less reliable for background execution, doesn't survive app termination
- **android_alarm_manager_plus**: Rejected - Android-only, no iOS support, deprecated in favor of WorkManager
- **Manual periodic checks on app launch**: Rejected - Misses occurrences if app isn't opened regularly
- **Server-side cron job**: Rejected - Violates offline-first architecture, requires network
- **1-minute intervals**: Rejected - Violates platform minimum interval constraints (15 min), battery drain

### Implementation Notes

- **Platform Differences**: iOS background fetch is less reliable than Android WorkManager; users may experience slight delays (acceptable for budget planning)
- **First Launch**: User must open app at least once to register the background task
- **Testing**: Use `Workmanager().registerOneOffTask()` with immediate execution for development testing
- **Monitoring**: Log all background task executions to track reliability and debug issues

---

## 2. Drift Table Design for Recurring Expenses

### Decision

Create two new Drift tables: `RecurringExpenses` (templates) and `RecurringExpenseInstances` (mapping). Extend existing `OfflineExpenses` table with a `recurringExpenseId` foreign key to link generated instances back to their template.

### Rationale

- **Separation of Concerns**: Template configuration (frequency, amount, category) separated from generated expense instances
- **Template Preservation**: Original expense marked as recurring becomes the template and remains visible with a recurring indicator
- **Audit Trail**: Mapping table allows tracking all instances generated from each template for analytics and debugging
- **Existing Pattern**: Aligns with existing schema design patterns (e.g., `IncomeSources`, `SavingsGoals`, `GroupExpenseAssignments`)
- **Offline-First**: Templates stored in local Drift database, sync to Supabase when online
- **Budget Reservation**: Separate tracking allows independent budget reservation logic without affecting actual expenses

### Schema Design

```dart
// lib/core/database/drift/tables/recurring_expenses_table.dart

import 'package:drift/drift.dart';

/// Drift table for recurring expense templates
///
/// Stores the configuration for recurring expenses, including frequency,
/// amount, category, and budget reservation settings.
@TableIndex(name: 'recurring_expenses_user_idx', columns: {#userId})
@TableIndex(name: 'recurring_expenses_active_idx', columns: {#isPaused, #nextDueDate})
class RecurringExpenses extends Table {
  // Primary Key
  TextColumn get id => text()(); // UUID v4

  // User Isolation
  TextColumn get userId => text()(); // References auth.users(id)
  TextColumn get groupId => text().nullable()(); // References family_groups(id)

  // Template Source (the original expense that became recurring)
  TextColumn get templateExpenseId => text().nullable()(); // References expenses(id)

  // Expense Configuration
  RealColumn get amount => real()(); // Expense amount
  TextColumn get categoryId => text()(); // References expense_categories(id)
  TextColumn get merchant => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isGroupExpense => boolean().withDefault(const Constant(true))();

  // Recurrence Configuration
  TextColumn get frequency => text()
      .check(frequency.isIn(['daily', 'weekly', 'monthly', 'yearly']))();
  DateTimeColumn get anchorDate => dateTime()(); // Original date for recurrence calculation

  // Status
  BoolColumn get isPaused => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastInstanceCreatedAt => dateTime().nullable()(); // Last time an instance was generated
  DateTimeColumn get nextDueDate => dateTime().nullable()(); // Calculated next due date (for query optimization)

  // Budget Reservation
  BoolColumn get budgetReservationEnabled => boolean().withDefault(const Constant(false))();

  // Default reimbursement status for generated instances
  TextColumn get defaultReimbursementStatus => text()
      .withDefault(const Constant('none'))
      .check(defaultReimbursementStatus.isIn(['none', 'reimbursable', 'reimbursed']))();

  // Timestamps
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Mapping table: tracks which expense instances were generated from which templates
///
/// Provides audit trail and enables "delete all occurrences" functionality
@TableIndex(name: 'recurring_instances_template_idx', columns: {#recurringExpenseId})
@TableIndex(name: 'recurring_instances_expense_idx', columns: {#expenseId})
class RecurringExpenseInstances extends Table {
  IntColumn get id => integer().autoIncrement()();

  // Relationships
  TextColumn get recurringExpenseId => text()(); // References recurring_expenses(id)
  TextColumn get expenseId => text()(); // References expenses(id) or offline_expenses(id)

  // Metadata
  DateTimeColumn get scheduledDate => dateTime()(); // When instance was scheduled to occur
  DateTimeColumn get createdAt => dateTime()(); // When instance was actually created
}
```

### Extended OfflineExpenses Table

```dart
// Modification to existing lib/features/offline/data/local/offline_database.dart

// ADD to OfflineExpenses table:
class OfflineExpenses extends Table {
  // ... existing fields ...

  // Link to recurring expense template (null for non-recurring expenses)
  TextColumn get recurringExpenseId => text().nullable()(); // References recurring_expenses(id)
  BoolColumn get isRecurringInstance => boolean().withDefault(const Constant(false))();
}
```

### Indexing Strategy

**Purpose**: Optimize queries for finding due recurring expenses and budget calculations

```sql
-- Index 1: Find active recurring expenses due for creation
CREATE INDEX recurring_expenses_active_idx
ON recurring_expenses(is_paused, next_due_date)
WHERE is_paused = false;

-- Index 2: User isolation for listing user's recurring expenses
CREATE INDEX recurring_expenses_user_idx
ON recurring_expenses(user_id);

-- Index 3: Find all instances generated from a template
CREATE INDEX recurring_instances_template_idx
ON recurring_expense_instances(recurring_expense_id);

-- Index 4: Link expense back to its template
CREATE INDEX recurring_instances_expense_idx
ON recurring_expense_instances(expense_id);

-- Index 5: Budget reservation calculations (find active reservations)
CREATE INDEX recurring_expenses_reservation_idx
ON recurring_expenses(budget_reservation_enabled, user_id)
WHERE is_paused = false AND budget_reservation_enabled = true;
```

### Migration Strategy

```dart
// lib/features/offline/data/local/offline_database.dart

@DriftDatabase(tables: [
  OfflineExpenses,
  // ... existing tables ...
  RecurringExpenses,        // NEW
  RecurringExpenseInstances, // NEW
])
class OfflineDatabase extends _$OfflineDatabase {
  @override
  int get schemaVersion => 4; // Increment from 3 to 4

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.createTable(cachedCategories);
      }
      if (from < 3) {
        await m.createTable(incomeSources);
        await m.createTable(savingsGoals);
        await m.createTable(groupExpenseAssignments);
      }
      if (from < 4) {
        // Add recurring expense tables
        await m.createTable(recurringExpenses);
        await m.createTable(recurringExpenseInstances);

        // Add recurring_expense_id to existing OfflineExpenses
        await m.addColumn(offlineExpenses, offlineExpenses.recurringExpenseId);
        await m.addColumn(offlineExpenses, offlineExpenses.isRecurringInstance);
      }
    },
  );
}
```

### Alternatives Considered

- **Single table with is_template flag**: Rejected - Mixes template configuration with actual expenses, complex queries
- **Store frequency in JSON**: Rejected - Loses type safety, harder to index and query
- **No mapping table**: Rejected - Can't track generated instances, difficult to implement "delete all occurrences"
- **Store instances as JSON array in template**: Rejected - Violates normalization, limits query capabilities

---

## 3. Recurrence Calculation Algorithm

### Decision

Implement a **date-based calculation algorithm** using the anchor date pattern with the existing `timezone` package and `TimezoneHandler` utility. Handle edge cases (month-end, leap years) with "last day of month" fallback logic.

### Rationale

- **Timezone Package Already Integrated**: Project uses `timezone: ^0.10.1` with `TimezoneHandler` for budget calculations
- **Anchor Date Pattern**: Preserves the original date chosen by user (e.g., "15th of each month" for rent)
- **Predictable Behavior**: Edge cases have clear, documented fallback logic
- **Performance**: Calculation is pure function, no database queries required
- **Testability**: Easy to unit test with known inputs/outputs

### Algorithm Implementation

See "Timezone-Aware Scheduling Implementation" in Section 1 above for the full `RecurrenceCalculator` class.

### Edge Case Handling

| Scenario | Anchor Date | Target Month | Result | Rationale |
|----------|-------------|--------------|--------|-----------|
| Month-end (31st) | Jan 31 | Feb | Feb 28/29 | Use last day of shorter month |
| Month-end (31st) | Jan 31 | Apr | Apr 30 | Use last day of shorter month |
| Leap year | Feb 29, 2024 | Feb 2025 | Feb 28, 2025 | Use last day of non-leap year |
| Weekly (any day) | Mon, Week 1 | Week 2 | Mon, Week 2 | Exactly 7 days later |
| Daily | Jan 1, 10:00 | Jan 2 | Jan 2, 10:00 | Exactly 24 hours later |

### Weekly Recurrence with Different Start Days

```dart
// Weekly recurrence is simple: always add exactly 7 days
// No special handling needed for different weekdays

// Example:
// Anchor: Monday, Jan 1, 2026
// Next occurrences:
// - Monday, Jan 8, 2026
// - Monday, Jan 15, 2026
// - Monday, Jan 22, 2026

// The day of week is preserved naturally by adding 7-day intervals
```

### Timezone Handling

```dart
// All date calculations use TimezoneHandler.toLocal() and tz.local
// This ensures recurring expenses are created at the correct local time
// regardless of device timezone or Supabase storage (UTC)

// Example: User in Italy (UTC+1) sets recurring expense for "1st of month"
// 1. anchorDate stored as: 2026-01-01 00:00:00 (local Italy time)
// 2. Next occurrence calculated as: 2026-02-01 00:00:00 (local Italy time)
// 3. When synced to Supabase: 2026-01-31 23:00:00 UTC (correct conversion)

// This prevents issues where:
// - User in UTC+8 would get expenses 8 hours early if using naive UTC
// - Monthly "1st of month" becomes "31st of previous month" in some timezones
```

### Alternatives Considered

- **Cron expression parser**: Rejected - Overkill for 4 simple frequencies, adds complexity
- **RRule library**: Rejected - Heavy dependency, designed for calendar events not budget expenses
- **Server-side calculation**: Rejected - Violates offline-first architecture
- **Store next 12 occurrences**: Rejected - Wastes storage, difficult to modify frequency

---

## 4. Budget Reservation Calculation

### Decision

Extend the existing `BudgetCalculator` utility class with new methods for calculating reserved budget. Implement a **caching strategy using Riverpod providers** with selective invalidation to avoid recalculating on every budget view.

### Rationale

- **Existing Pattern**: `BudgetCalculator` already handles budget calculations with reimbursement logic (Feature 012)
- **Centralized Logic**: All budget math in one utility class, easier to maintain and test
- **Riverpod Caching**: Project uses `flutter_riverpod: ^2.4.0` for state management; providers automatically cache and invalidate
- **Performance**: Calculations only re-run when dependencies change (recurring expenses modified, budget period changed)
- **Integration**: Works seamlessly with existing budget system (no breaking changes)

### Budget Reservation Calculation Logic

```dart
// lib/core/utils/budget_calculator.dart (EXTENDED)

class BudgetCalculator {
  // ... existing methods ...

  /// Calculate total reserved budget for active recurring expenses in a period
  ///
  /// T120: Feature 013-recurring-expenses - User Story 2
  /// Sums all recurring expenses with budget_reservation_enabled = true
  /// that are due in the current budget period (month/year).
  ///
  /// [recurringExpenses] - List of recurring expense templates
  /// [month] - Budget period month (1-12)
  /// [year] - Budget period year
  ///
  /// Returns total reserved amount in cents
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

      // Check if this recurring expense is due in the current period
      final nextDueDate = RecurrenceCalculator.calculateNextDueDate(
        anchorDate: template.anchorDate,
        frequency: template.frequency,
        lastCreated: template.lastInstanceCreatedAt,
      );

      if (nextDueDate == null) return sum;

      // If due date falls within the budget period, reserve the amount
      if (nextDueDate.isAfter(periodStart) &&
          nextDueDate.isBefore(periodEnd)) {
        return sum + (template.amount * 100).round();
      }

      return sum;
    });
  }

  /// Calculate available budget after reservations
  ///
  /// T121: Feature 013-recurring-expenses - User Story 2
  /// Formula: availableBudget = totalBudget - spentAmount - reservedBudget + reimbursedIncome
  ///
  /// [budgetAmount] - Total budget in euros
  /// [spentAmount] - Amount spent in euros
  /// [reservedBudget] - Amount reserved for recurring expenses in cents
  /// [reimbursedIncome] - Amount reimbursed in cents (default: 0)
  ///
  /// Returns available budget in euros (can be negative)
  static int calculateAvailableBudget({
    required int budgetAmount,
    required int spentAmount,
    required int reservedBudget,
    int reimbursedIncome = 0,
  }) {
    final reservedEuros = (reservedBudget / 100).round();
    final reimbursedEuros = (reimbursedIncome / 100).round();

    return budgetAmount - spentAmount - reservedEuros + reimbursedEuros;
  }

  /// Get budget breakdown with reservations
  ///
  /// T122: Feature 013-recurring-expenses - User Story 2
  /// Returns a detailed breakdown of budget allocation
  ///
  /// Returns map with:
  /// - totalBudget: Total budget in euros
  /// - spentAmount: Amount spent in euros
  /// - reservedBudget: Amount reserved in euros
  /// - reimbursedIncome: Amount reimbursed in euros
  /// - availableBudget: Remaining available in euros
  /// - percentageUsed: Percentage of budget used (including reserved)
  static Map<String, dynamic> getBudgetBreakdown({
    required int budgetAmount,
    required int spentAmount,
    required int reservedBudget,
    int reimbursedIncome = 0,
  }) {
    final reservedEuros = (reservedBudget / 100).round();
    final reimbursedEuros = (reimbursedIncome / 100).round();
    final availableBudget = calculateAvailableBudget(
      budgetAmount: budgetAmount,
      spentAmount: spentAmount,
      reservedBudget: reservedBudget,
      reimbursedIncome: reimbursedIncome,
    );

    // Calculate percentage including reserved amounts
    final totalCommitted = spentAmount + reservedEuros - reimbursedEuros;
    final percentageUsed = budgetAmount > 0
        ? (totalCommitted / budgetAmount * 100)
        : 0.0;

    return {
      'totalBudget': budgetAmount,
      'spentAmount': spentAmount,
      'reservedBudget': reservedEuros,
      'reimbursedIncome': reimbursedEuros,
      'availableBudget': availableBudget,
      'percentageUsed': percentageUsed.clamp(0.0, 100.0),
    };
  }
}
```

### Caching Strategy with Riverpod

```dart
// lib/features/budgets/presentation/providers/budget_reservation_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../../core/utils/budget_calculator.dart';
import '../../../../core/utils/timezone_handler.dart';
import '../../../recurring_expenses/presentation/providers/recurring_expense_provider.dart';

part 'budget_reservation_provider.g.dart';

/// Cached provider for budget reservations in current month
///
/// Automatically invalidates when:
/// - Recurring expenses are modified (via recurringExpenseListProvider)
/// - Month changes (reactive to TimezoneHandler.getCurrentMonthYear())
@riverpod
Future<int> currentMonthReservedBudget(CurrentMonthReservedBudgetRef ref) async {
  // Watch recurring expenses list (auto-invalidates when list changes)
  final recurringExpenses = await ref.watch(recurringExpenseListProvider.future);

  // Get current month/year
  final (:month, :year) = TimezoneHandler.getCurrentMonthYear();

  // Calculate reserved budget (cached until dependencies change)
  return BudgetCalculator.calculateReservedBudget(
    recurringExpenses: recurringExpenses,
    month: month,
    year: year,
  );
}

/// Provider for available budget (total - spent - reserved + reimbursed)
@riverpod
Future<int> availableBudget(AvailableBudgetRef ref) async {
  // Watch all dependencies
  final totalBudget = await ref.watch(totalBudgetProvider.future);
  final spentAmount = await ref.watch(spentAmountProvider.future);
  final reservedBudget = await ref.watch(currentMonthReservedBudgetProvider.future);
  final reimbursedIncome = await ref.watch(reimbursedIncomeProvider.future);

  // Calculate (cached until any dependency changes)
  return BudgetCalculator.calculateAvailableBudget(
    budgetAmount: totalBudget,
    spentAmount: spentAmount,
    reservedBudget: reservedBudget,
    reimbursedIncome: reimbursedIncome,
  );
}
```

### Avoiding Recalculation on Every Budget View

**Strategy**: Use Riverpod's automatic caching and selective invalidation

1. **Provider Caching**: Riverpod providers cache results until dependencies change
2. **Selective Watching**: Only watch specific providers needed for calculation
3. **Granular Invalidation**: Only invalidate when:
   - User creates/modifies/deletes a recurring expense
   - User toggles budget reservation for a recurring expense
   - Budget period changes (new month)
   - Budget amount changes

**Performance Impact**:
- First load: ~10ms (calculation + database query)
- Subsequent loads: <1ms (cached result)
- On invalidation: ~10ms (recalculation only)

### Integration with Existing Budget System

```dart
// Modify existing budget provider to include reservations

// lib/features/budgets/presentation/providers/budget_provider.dart (MODIFIED)

@riverpod
class BudgetStats extends _$BudgetStats {
  @override
  Future<BudgetStatsState> build() async {
    final totalBudget = await ref.watch(totalBudgetProvider.future);
    final spentAmount = await ref.watch(spentAmountProvider.future);
    final reimbursedIncome = await ref.watch(reimbursedIncomeProvider.future);

    // NEW: Include reserved budget
    final reservedBudget = await ref.watch(currentMonthReservedBudgetProvider.future);

    // NEW: Calculate breakdown with reservations
    final breakdown = BudgetCalculator.getBudgetBreakdown(
      budgetAmount: totalBudget,
      spentAmount: spentAmount,
      reservedBudget: reservedBudget,
      reimbursedIncome: reimbursedIncome,
    );

    return BudgetStatsState(
      totalBudget: breakdown['totalBudget'] as int,
      spentAmount: breakdown['spentAmount'] as int,
      reservedBudget: breakdown['reservedBudget'] as int,
      availableBudget: breakdown['availableBudget'] as int,
      percentageUsed: breakdown['percentageUsed'] as double,
      // ... other fields
    );
  }
}
```

### Alternatives Considered

- **Recalculate on every UI render**: Rejected - Poor performance, wasteful computation
- **Manual caching with expiry**: Rejected - Riverpod handles this automatically and more reliably
- **Pre-calculate and store in database**: Rejected - Adds complexity, risk of stale data
- **Server-side calculation**: Rejected - Adds latency, violates offline-first architecture

---

## 5. Supabase Schema Extension

### Decision

Create a new `recurring_expenses` table in Supabase with foreign key relationships to `expenses` and `expense_categories`. Implement **RLS policies** for multi-user access using the existing group-based security pattern. Use **bidirectional sync strategy** between Drift and Supabase.

### Rationale

- **Existing Pattern**: Follows the same structure as `income_sources`, `savings_goals`, and `expenses` tables
- **RLS Consistency**: Reuses existing group-based RLS policies for security
- **Offline-First**: Local Drift database is source of truth, Supabase is sync target
- **Audit Trail**: Supabase provides server-side backup and cross-device sync
- **Relationship Integrity**: Foreign keys ensure referential integrity with expenses and categories

### Supabase Migration

```sql
-- supabase/migrations/20260116_001_create_recurring_expenses.sql

-- Enable UUID extension (if not already enabled)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Table 1: recurring_expenses (templates)
CREATE TABLE public.recurring_expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- User & Group Isolation
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  group_id UUID REFERENCES public.family_groups(id) ON DELETE CASCADE,

  -- Template Source (the original expense that became recurring)
  template_expense_id UUID REFERENCES public.expenses(id) ON DELETE SET NULL,

  -- Expense Configuration
  amount DECIMAL(10, 2) NOT NULL CHECK (amount > 0),
  category_id UUID NOT NULL REFERENCES public.expense_categories(id) ON DELETE RESTRICT,
  merchant TEXT CHECK (char_length(merchant) <= 100),
  notes TEXT CHECK (char_length(notes) <= 500),
  is_group_expense BOOLEAN NOT NULL DEFAULT true,

  -- Recurrence Configuration
  frequency TEXT NOT NULL CHECK (frequency IN ('daily', 'weekly', 'monthly', 'yearly')),
  anchor_date DATE NOT NULL,

  -- Status
  is_paused BOOLEAN NOT NULL DEFAULT false,
  last_instance_created_at TIMESTAMPTZ,
  next_due_date DATE, -- Calculated field for query optimization

  -- Budget Reservation
  budget_reservation_enabled BOOLEAN NOT NULL DEFAULT false,

  -- Default reimbursement status for generated instances
  default_reimbursement_status TEXT NOT NULL DEFAULT 'none'
    CHECK (default_reimbursement_status IN ('none', 'reimbursable', 'reimbursed')),

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Table 2: recurring_expense_instances (mapping)
CREATE TABLE public.recurring_expense_instances (
  id SERIAL PRIMARY KEY,

  -- Relationships
  recurring_expense_id UUID NOT NULL REFERENCES public.recurring_expenses(id) ON DELETE CASCADE,
  expense_id UUID NOT NULL REFERENCES public.expenses(id) ON DELETE CASCADE,

  -- Metadata
  scheduled_date DATE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_recurring_expenses_user_id ON public.recurring_expenses(user_id);
CREATE INDEX idx_recurring_expenses_group_id ON public.recurring_expenses(group_id);
CREATE INDEX idx_recurring_expenses_active ON public.recurring_expenses(is_paused, next_due_date)
  WHERE is_paused = false;
CREATE INDEX idx_recurring_expenses_reservation ON public.recurring_expenses(budget_reservation_enabled, user_id)
  WHERE is_paused = false AND budget_reservation_enabled = true;

CREATE INDEX idx_recurring_instances_template ON public.recurring_expense_instances(recurring_expense_id);
CREATE INDEX idx_recurring_instances_expense ON public.recurring_expense_instances(expense_id);

-- Updated_at trigger
CREATE TRIGGER update_recurring_expenses_updated_at
  BEFORE UPDATE ON public.recurring_expenses
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Comments for documentation
COMMENT ON TABLE public.recurring_expenses IS
  'Templates for recurring expenses with frequency and budget reservation settings';
COMMENT ON TABLE public.recurring_expense_instances IS
  'Audit trail mapping generated expense instances to their recurring templates';
COMMENT ON COLUMN public.recurring_expenses.next_due_date IS
  'Calculated next occurrence date for query optimization (updated by trigger or app)';
```

### RLS Policies

```sql
-- supabase/migrations/20260116_002_recurring_expenses_rls.sql

-- Enable RLS
ALTER TABLE public.recurring_expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recurring_expense_instances ENABLE ROW LEVEL SECURITY;

-- Policy 1: Users can view recurring expenses in their group
CREATE POLICY "Users can view recurring expenses in their group"
  ON public.recurring_expenses
  FOR SELECT
  TO authenticated
  USING (
    group_id IN (
      SELECT group_id
      FROM public.profiles
      WHERE id = auth.uid()
    )
  );

-- Policy 2: Users can create recurring expenses
CREATE POLICY "Users can create recurring expenses"
  ON public.recurring_expenses
  FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid() AND
    group_id IN (
      SELECT group_id
      FROM public.profiles
      WHERE id = auth.uid()
    )
  );

-- Policy 3: Users can update their own recurring expenses
CREATE POLICY "Users can update their own recurring expenses"
  ON public.recurring_expenses
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Policy 4: Users can delete their own recurring expenses
CREATE POLICY "Users can delete their own recurring expenses"
  ON public.recurring_expenses
  FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

-- Policy 5: Users can view instances in their group
CREATE POLICY "Users can view recurring expense instances in their group"
  ON public.recurring_expense_instances
  FOR SELECT
  TO authenticated
  USING (
    recurring_expense_id IN (
      SELECT id FROM public.recurring_expenses
      WHERE group_id IN (
        SELECT group_id FROM public.profiles WHERE id = auth.uid()
      )
    )
  );

-- Policy 6: System can create instances (for background tasks)
CREATE POLICY "System can create recurring expense instances"
  ON public.recurring_expense_instances
  FOR INSERT
  TO authenticated
  WITH CHECK (
    recurring_expense_id IN (
      SELECT id FROM public.recurring_expenses
      WHERE user_id = auth.uid()
    )
  );

-- Policy 7: Users can delete instances from their templates
CREATE POLICY "Users can delete their recurring expense instances"
  ON public.recurring_expense_instances
  FOR DELETE
  TO authenticated
  USING (
    recurring_expense_id IN (
      SELECT id FROM public.recurring_expenses
      WHERE user_id = auth.uid()
    )
  );
```

### Foreign Key Cascade Behaviors

| Parent Table | Child Table | Relationship | On Delete Behavior | Rationale |
|--------------|-------------|--------------|-------------------|-----------|
| `auth.users` | `recurring_expenses` | user owns template | CASCADE | Delete user → delete their recurring templates |
| `family_groups` | `recurring_expenses` | group contains templates | CASCADE | Delete group → delete all group templates |
| `expense_categories` | `recurring_expenses` | template uses category | RESTRICT | Prevent category deletion if used by recurring template |
| `expenses` | `recurring_expenses` | template source | SET NULL | Delete original expense → keep template, clear source reference |
| `recurring_expenses` | `recurring_expense_instances` | template → instances | CASCADE | Delete template → delete all generated instance records |
| `expenses` | `recurring_expense_instances` | instance mapping | CASCADE | Delete expense → delete mapping record |

### Sync Strategy: Drift ↔ Supabase

**Bidirectional Sync Pattern** (reuses existing Feature 010 infrastructure):

1. **Local Creation** (Offline-First):
   - User creates recurring expense → Insert into Drift `recurring_expenses` table
   - Add sync queue item: `{operation: 'create', entity: 'recurring_expense', payload: {...}}`
   - Background sync uploads to Supabase when online

2. **Remote Changes** (Multi-Device Sync):
   - Listen to Supabase Realtime on `recurring_expenses` table
   - On remote INSERT/UPDATE/DELETE → Update local Drift database
   - Conflict resolution: Server wins (last-write-wins strategy)

3. **Instance Creation** (Background Task):
   - Background task creates expense in `OfflineExpenses` table
   - Add sync queue item for expense sync
   - After expense synced, create mapping in `recurring_expense_instances`

4. **Consistency Checks**:
   - On app launch: Verify local and remote recurring expense counts match
   - If mismatch: Trigger full re-sync from Supabase (rare edge case)

```dart
// lib/features/recurring_expenses/data/datasources/recurring_expense_remote_datasource.dart

abstract class RecurringExpenseRemoteDataSource {
  Future<void> createRecurringExpense(RecurringExpenseEntity expense);
  Future<void> updateRecurringExpense(RecurringExpenseEntity expense);
  Future<void> deleteRecurringExpense(String id);
  Future<List<RecurringExpenseEntity>> getRecurringExpenses(String userId);
  Stream<List<RecurringExpenseEntity>> watchRecurringExpenses(String userId);
}

class RecurringExpenseRemoteDataSourceImpl implements RecurringExpenseRemoteDataSource {
  final SupabaseClient supabase;

  @override
  Stream<List<RecurringExpenseEntity>> watchRecurringExpenses(String userId) {
    return supabase
      .from('recurring_expenses')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId)
      .map((data) => data.map((json) => RecurringExpenseEntity.fromJson(json)).toList());
  }

  // ... other implementations
}
```

### Alternatives Considered

- **No Supabase table, Drift only**: Rejected - No cross-device sync, no backup
- **Store as JSON in expenses table**: Rejected - Poor query performance, loses type safety
- **Separate RLS for personal vs group**: Rejected - Existing pattern uses single RLS with group_id check
- **Manual sync triggers**: Rejected - Realtime subscriptions are more reliable and efficient

---

## Research Summary

All technical unknowns resolved. Ready to proceed to Phase 1 (Design & Contracts).

### Key Decisions

1. **Workmanager**: 15-minute periodic tasks with network/battery constraints, timezone-aware scheduling using existing `TimezoneHandler`
2. **Drift Schema**: Two new tables (`RecurringExpenses` templates, `RecurringExpenseInstances` mapping) + extend `OfflineExpenses` with foreign key
3. **Recurrence Algorithm**: Date-based calculation with anchor date pattern, edge case handling for month-end/leap years
4. **Budget Reservation**: Extend `BudgetCalculator` utility, Riverpod caching strategy with selective invalidation
5. **Supabase Schema**: New `recurring_expenses` table with group-based RLS policies, bidirectional sync using existing Feature 010 infrastructure

### No Blockers

All implementation patterns align with existing codebase architecture:
- Clean Architecture (data/domain/presentation layers)
- Feature-based modules
- Offline-first with Drift + Supabase sync
- Riverpod state management
- Timezone-aware date handling
- Group-based RLS security model

### Dependencies

- Feature 010 (Offline Expense Sync): Provides sync queue infrastructure for recurring expense instances
- Feature 012 (Expense Improvements): Provides reimbursement status enum and tracking
- Existing infrastructure: `workmanager`, `timezone`, `TimezoneHandler`, `BudgetCalculator`, RLS policies

### Next Steps

1. Generate data model diagrams (Phase 1: `data-model.md`)
2. Create API contracts (Phase 1: `contracts/`)
3. Write quickstart guide (Phase 1: `quickstart.md`)
4. Generate implementation tasks (Phase 2: `tasks.md`)
