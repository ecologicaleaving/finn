# Data Model: Recurring Expenses and Reimbursements Management

**Feature**: 013-recurring-expenses
**Phase**: 1 (Design Artifacts)
**Created**: 2026-01-16

---

## Overview

This document defines the complete data model for recurring expense functionality, including local Drift tables, Supabase schema, and relationships to existing entities. The design follows the existing offline-first architecture with bidirectional sync between Drift (local) and Supabase (remote).

### Architecture Pattern

- **Offline-First**: Local Drift database is source of truth
- **Bidirectional Sync**: Changes propagate between Drift ↔ Supabase
- **Group Isolation**: RLS policies ensure multi-user data separation
- **Clean Architecture**: Domain entities separate from data layer

---

## Entities

### 1. RecurringExpense (Template)

Represents a recurring expense template that generates expense instances on a schedule.

#### Fields

| Field | Type | Nullable | Default | Constraints | Description |
|-------|------|----------|---------|-------------|-------------|
| `id` | String (UUID) | No | - | PK | Unique identifier |
| `userId` | String (UUID) | No | - | FK → auth.users(id) | Creator/owner of recurring template |
| `groupId` | String (UUID) | Yes | null | FK → family_groups(id) | Family group for shared budgets |
| `templateExpenseId` | String (UUID) | Yes | null | FK → expenses(id) | Original expense that became recurring |
| `amount` | double | No | - | > 0 | Expense amount in euros |
| `categoryId` | String (UUID) | No | - | FK → expense_categories(id) | Expense category |
| `merchant` | String | Yes | null | max 100 chars | Merchant/vendor name |
| `notes` | String | Yes | null | max 500 chars | Description/notes |
| `isGroupExpense` | bool | No | true | - | Whether expense affects group budget |
| `frequency` | String (enum) | No | - | daily/weekly/monthly/yearly | Recurrence frequency |
| `anchorDate` | DateTime | No | - | - | Reference date for recurrence calculation |
| `isPaused` | bool | No | false | - | Whether instance generation is paused |
| `lastInstanceCreatedAt` | DateTime | Yes | null | - | Last time an instance was generated |
| `nextDueDate` | DateTime | Yes | null | - | Calculated next occurrence (query optimization) |
| `budgetReservationEnabled` | bool | No | false | - | Whether to reserve budget for this expense |
| `defaultReimbursementStatus` | String (enum) | No | 'none' | none/reimbursable/reimbursed | Default reimbursement status for instances |
| `createdAt` | DateTime | No | NOW() | - | Template creation timestamp |
| `updatedAt` | DateTime | No | NOW() | - | Last modification timestamp |

#### Validation Rules

1. **Amount**: Must be greater than 0
2. **Frequency**: Must be one of: `daily`, `weekly`, `monthly`, `yearly`
3. **Reimbursement Status**: Must be one of: `none`, `reimbursable`, `reimbursed`
4. **Merchant**: Max 100 characters
5. **Notes**: Max 500 characters
6. **Next Due Date**: Must be calculated correctly from anchor date and frequency
7. **Category ID**: Must reference an existing expense category
8. **User ID**: Must reference an authenticated user
9. **Group ID**: If set, must reference an existing family group

#### State Transitions

```
┌─────────────┐
│   CREATED   │ (isPaused=false)
└──────┬──────┘
       │
       ├──────────────────────────────────┐
       │                                  │
       ▼                                  ▼
┌─────────────┐                    ┌──────────┐
│   ACTIVE    │ ──pause()──────▶   │  PAUSED  │
│ (isPaused=  │ ◀──resume()────    │ (isPaused│
│   false)    │                    │  =true)  │
└──────┬──────┘                    └──────────┘
       │
       │ delete()
       ▼
┌─────────────┐
│   DELETED   │ (record removed or soft-deleted)
└─────────────┘
```

**State Rules**:
- **ACTIVE**: System generates expense instances when `nextDueDate` arrives
- **PAUSED**: No instances generated; remains paused indefinitely until user resumes
- **Budget Reservation**: Only active templates with `budgetReservationEnabled=true` reserve budget

#### Relationships

- **One-to-Many** with `RecurringExpenseInstance`: One template generates many instances
- **Many-to-One** with `User`: Many templates belong to one user
- **Many-to-One** with `FamilyGroup`: Many templates belong to one group (nullable)
- **Many-to-One** with `ExpenseCategory`: Many templates use one category
- **One-to-One** with `Expense` (optional): Template may reference original expense

#### Indexes

```sql
-- User isolation (list user's recurring expenses)
CREATE INDEX recurring_expenses_user_idx ON recurring_expenses(user_id);

-- Find active templates due for creation
CREATE INDEX recurring_expenses_active_idx
ON recurring_expenses(is_paused, next_due_date)
WHERE is_paused = false;

-- Budget reservation calculations
CREATE INDEX recurring_expenses_reservation_idx
ON recurring_expenses(budget_reservation_enabled, user_id)
WHERE is_paused = false AND budget_reservation_enabled = true;

-- Group isolation
CREATE INDEX recurring_expenses_group_idx ON recurring_expenses(group_id);
```

---

### 2. RecurringExpenseInstance (Mapping)

Audit trail mapping that tracks which expense instances were generated from which templates.

#### Fields

| Field | Type | Nullable | Default | Constraints | Description |
|-------|------|----------|---------|-------------|-------------|
| `id` | int | No | AUTO | PK | Auto-increment ID |
| `recurringExpenseId` | String (UUID) | No | - | FK → recurring_expenses(id) | Template that generated this instance |
| `expenseId` | String (UUID) | No | - | FK → expenses(id) or offline_expenses(id) | Generated expense instance |
| `scheduledDate` | DateTime | No | - | - | When instance was scheduled to occur |
| `createdAt` | DateTime | No | NOW() | - | When instance was actually created |

#### Validation Rules

1. **Recurring Expense ID**: Must reference an existing recurring template
2. **Expense ID**: Must reference an existing expense (local or synced)
3. **Scheduled Date**: Should align with template's recurrence frequency
4. **No Duplicates**: One expense can only be linked to one recurring template

#### Relationships

- **Many-to-One** with `RecurringExpense`: Many instances belong to one template
- **One-to-One** with `Expense`: One instance maps to one expense

#### Indexes

```sql
-- Find all instances for a template (for deletion, analytics)
CREATE INDEX recurring_instances_template_idx
ON recurring_expense_instances(recurring_expense_id);

-- Link expense back to template (check if expense is recurring instance)
CREATE INDEX recurring_instances_expense_idx
ON recurring_expense_instances(expense_id);
```

---

### 3. OfflineExpense (Extension)

Existing table extended with recurring expense fields.

#### New Fields Added

| Field | Type | Nullable | Default | Constraints | Description |
|-------|------|----------|---------|-------------|-------------|
| `recurringExpenseId` | String (UUID) | Yes | null | FK → recurring_expenses(id) | Link to template if this is a recurring instance |
| `isRecurringInstance` | bool | No | false | - | Quick flag to identify recurring instances |

#### Integration with Existing Fields

The existing `reimbursementStatus` field (from Feature 012) will be populated from the template's `defaultReimbursementStatus` when instances are created:

```dart
// When creating instance from template
OfflineExpensesCompanion.insert(
  // ... other fields
  reimbursementStatus: Value(template.defaultReimbursementStatus),
  recurringExpenseId: Value(template.id),
  isRecurringInstance: const Value(true),
)
```

---

## Drift Table Schemas

### RecurringExpenses Table

```dart
// lib/core/database/drift/tables/recurring_expenses_table.dart

import 'package:drift/drift.dart';

/// Drift table for recurring expense templates
///
/// Stores the configuration for recurring expenses, including frequency,
/// amount, category, and budget reservation settings.
@TableIndex(name: 'recurring_expenses_user_idx', columns: {#userId})
@TableIndex(name: 'recurring_expenses_active_idx', columns: {#isPaused, #nextDueDate})
@TableIndex(name: 'recurring_expenses_reservation_idx', columns: {#budgetReservationEnabled, #userId})
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
```

### RecurringExpenseInstances Table

```dart
// lib/core/database/drift/tables/recurring_expense_instances_table.dart

import 'package:drift/drift.dart';

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

### Modified OfflineExpenses Table

```dart
// Modification to existing lib/features/offline/data/local/offline_database.dart

// ADD to OfflineExpenses table:
class OfflineExpenses extends Table {
  // ... existing fields (id, userId, amount, date, etc.) ...

  // NEW: Link to recurring expense template (null for non-recurring expenses)
  TextColumn get recurringExpenseId => text().nullable()(); // References recurring_expenses(id)
  BoolColumn get isRecurringInstance => boolean().withDefault(const Constant(false))();

  // ... rest of existing fields ...
}
```

---

## Supabase Schema

### recurring_expenses Table

```sql
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

-- Indexes
CREATE INDEX idx_recurring_expenses_user_id ON public.recurring_expenses(user_id);
CREATE INDEX idx_recurring_expenses_group_id ON public.recurring_expenses(group_id);
CREATE INDEX idx_recurring_expenses_active ON public.recurring_expenses(is_paused, next_due_date)
  WHERE is_paused = false;
CREATE INDEX idx_recurring_expenses_reservation ON public.recurring_expenses(budget_reservation_enabled, user_id)
  WHERE is_paused = false AND budget_reservation_enabled = true;

-- Updated_at trigger
CREATE TRIGGER update_recurring_expenses_updated_at
  BEFORE UPDATE ON public.recurring_expenses
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Comments
COMMENT ON TABLE public.recurring_expenses IS
  'Templates for recurring expenses with frequency and budget reservation settings';
COMMENT ON COLUMN public.recurring_expenses.next_due_date IS
  'Calculated next occurrence date for query optimization (updated by trigger or app)';
```

### recurring_expense_instances Table

```sql
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

-- Indexes
CREATE INDEX idx_recurring_instances_template ON public.recurring_expense_instances(recurring_expense_id);
CREATE INDEX idx_recurring_instances_expense ON public.recurring_expense_instances(expense_id);

-- Comments
COMMENT ON TABLE public.recurring_expense_instances IS
  'Audit trail mapping generated expense instances to their recurring templates';
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

---

## RLS Policies

### recurring_expenses Policies

```sql
-- Enable RLS
ALTER TABLE public.recurring_expenses ENABLE ROW LEVEL SECURITY;

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
```

### recurring_expense_instances Policies

```sql
-- Enable RLS
ALTER TABLE public.recurring_expense_instances ENABLE ROW LEVEL SECURITY;

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

---

## Migration Strategy

### Phase 1: Drift Database Migration

```dart
// lib/features/offline/data/local/offline_database.dart

@DriftDatabase(tables: [
  OfflineExpenses,
  SyncQueueItems,
  OfflineExpenseImages,
  CachedCategories,
  IncomeSources,
  SavingsGoals,
  GroupExpenseAssignments,
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
      // Existing migrations
      if (from < 2) {
        await m.createTable(cachedCategories);
      }
      if (from < 3) {
        await m.createTable(incomeSources);
        await m.createTable(savingsGoals);
        await m.createTable(groupExpenseAssignments);
      }

      // NEW: Schema version 4 - Recurring expenses
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

### Phase 2: Supabase Migration

**File**: `supabase/migrations/20260116_001_create_recurring_expenses.sql`

1. Create `recurring_expenses` table
2. Create `recurring_expense_instances` table
3. Add indexes
4. Add triggers (updated_at)
5. Enable RLS
6. Create RLS policies
7. Add comments for documentation

**Migration Testing**:
1. Test on local Supabase instance first
2. Verify RLS policies work correctly (user isolation)
3. Test cascade deletions
4. Run on staging environment
5. Deploy to production

### Data Integrity Checks

After migration, verify:

```sql
-- Check 1: All recurring expenses have valid user_id
SELECT COUNT(*) FROM recurring_expenses
WHERE user_id NOT IN (SELECT id FROM auth.users);
-- Expected: 0

-- Check 2: All recurring expenses have valid category_id
SELECT COUNT(*) FROM recurring_expenses
WHERE category_id NOT IN (SELECT id FROM expense_categories);
-- Expected: 0

-- Check 3: All instances reference valid templates and expenses
SELECT COUNT(*) FROM recurring_expense_instances
WHERE recurring_expense_id NOT IN (SELECT id FROM recurring_expenses)
   OR expense_id NOT IN (SELECT id FROM expenses);
-- Expected: 0

-- Check 4: All recurring instances in OfflineExpenses have valid template
SELECT COUNT(*) FROM offline_expenses
WHERE is_recurring_instance = true
  AND recurring_expense_id NOT IN (SELECT id FROM recurring_expenses);
-- Expected: 0
```

---

## Synchronization Strategy

### Drift → Supabase (Upload)

**Trigger**: Background sync (15-minute intervals) or on-demand sync

```dart
// When creating a recurring expense locally
// 1. Insert into Drift database
final id = const Uuid().v4();
await database.into(database.recurringExpenses).insert(
  RecurringExpensesCompanion.insert(
    id: id,
    userId: userId,
    groupId: Value(groupId),
    amount: amount,
    categoryId: categoryId,
    frequency: frequency,
    anchorDate: anchorDate,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ),
);

// 2. Queue for sync
await syncQueue.enqueue(SyncQueueItem(
  operation: 'create',
  entityType: 'recurring_expense',
  entityId: id,
  payload: jsonEncode(recurringExpense.toJson()),
));

// 3. Background sync uploads to Supabase
// (handled by existing SyncQueueProcessor)
```

### Supabase → Drift (Download)

**Trigger**: Realtime subscriptions on `recurring_expenses` table

```dart
// Listen to Supabase Realtime
supabase
  .from('recurring_expenses')
  .stream(primaryKey: ['id'])
  .eq('user_id', userId)
  .listen((data) async {
    for (final json in data) {
      final remoteExpense = RecurringExpenseEntity.fromJson(json);

      // Upsert into local Drift database
      await database.into(database.recurringExpenses).insertOnConflictUpdate(
        remoteExpense.toCompanion(),
      );
    }
  });
```

### Conflict Resolution

**Strategy**: Last-write-wins (server timestamp wins)

```dart
// When sync conflict detected:
// 1. Compare updatedAt timestamps
// 2. Server version always wins (authoritative source)
// 3. Overwrite local version with server version
// 4. Log conflict for analytics

if (serverVersion.updatedAt.isAfter(localVersion.updatedAt)) {
  await database.update(database.recurringExpenses)
    ..where((tbl) => tbl.id.equals(id))
    ..write(serverVersion.toCompanion());
}
```

---

## Edge Cases and Constraints

### 1. Template Deletion with Instances

**Scenario**: User deletes a recurring expense template that has already generated instances.

**Behavior**:
- User is prompted: "Delete future occurrences only" OR "Delete all occurrences (including past)"
- **Option A** (future only): Delete template record, keep existing instances
- **Option B** (all): Delete template + cascade delete all linked instances via `recurring_expense_instances` mapping

**Implementation**:
```dart
Future<void> deleteRecurringExpense(String id, {bool deleteInstances = false}) async {
  if (deleteInstances) {
    // Get all expense IDs linked to this template
    final instances = await (database.select(database.recurringExpenseInstances)
      ..where((tbl) => tbl.recurringExpenseId.equals(id))).get();

    // Delete all expense instances
    for (final instance in instances) {
      await (database.delete(database.offlineExpenses)
        ..where((tbl) => tbl.id.equals(instance.expenseId))).go();
    }
  }

  // Delete template (cascade deletes mapping records)
  await (database.delete(database.recurringExpenses)
    ..where((tbl) => tbl.id.equals(id))).go();
}
```

### 2. Budget Period Changes

**Scenario**: User switches from monthly to yearly budget view.

**Behavior**: Budget reservation calculation adjusts dynamically:
- Monthly view: Reserve only for expenses due this month
- Yearly view: Reserve for all expenses due this year

**Implementation**: See `BudgetCalculator.calculateReservedBudget()` in contracts/recurring_expenses_api.md

### 3. Frequency Change After Reservation Enabled

**Scenario**: User changes frequency from monthly to yearly after enabling budget reservation.

**Behavior**:
- Update `frequency` field
- Recalculate `nextDueDate` from `anchorDate` using new frequency
- Budget reservation recalculates automatically (Riverpod invalidation)

### 4. Offline Instance Creation

**Scenario**: App is offline when recurring expense is due.

**Behavior**:
- Background task creates instance in `OfflineExpenses` table immediately
- Sync queue item created with `syncStatus='pending'`
- When online, sync queue uploads to Supabase
- No delay in budget impact (instance counts toward budget immediately)

### 5. Category Deletion Protection

**Scenario**: User tries to delete a category used by a recurring template.

**Behavior**:
- Foreign key constraint `ON DELETE RESTRICT` prevents deletion
- Error message: "Cannot delete category - used by recurring expenses"
- User must reassign category first

### 6. Timezone Boundary Edge Cases

**Scenario**: User in UTC+8 has recurring expense at midnight. What happens when they travel to UTC-5?

**Behavior**:
- All dates stored in UTC in Supabase
- Local calculations use `timezone` package with `tz.local`
- Recurring expense due "1st of month" always occurs at 00:00 local time
- TimezoneHandler ensures consistent behavior across timezones

---

## Query Performance Considerations

### Optimized Queries

```dart
// Query 1: Find active recurring expenses due now (background task)
// Uses index: recurring_expenses_active_idx
final dueExpenses = await (database.select(database.recurringExpenses)
  ..where((tbl) =>
    tbl.isPaused.equals(false) &
    tbl.nextDueDate.isSmallerOrEqualValue(DateTime.now())
  )
).get();

// Query 2: Calculate budget reservation for current month (cached)
// Uses index: recurring_expenses_reservation_idx
final reservations = await (database.select(database.recurringExpenses)
  ..where((tbl) =>
    tbl.budgetReservationEnabled.equals(true) &
    tbl.isPaused.equals(false) &
    tbl.userId.equals(userId)
  )
).get();

// Query 3: Get all instances for a template (deletion UI)
// Uses index: recurring_instances_template_idx
final instances = await (database.select(database.recurringExpenseInstances)
  ..where((tbl) => tbl.recurringExpenseId.equals(templateId))
).get();
```

### Expected Performance

- **Background task execution**: <100ms for 50 active templates
- **Budget reservation calculation**: <50ms for 20 active reservations (cached)
- **Template list query**: <30ms for 100 templates
- **Instance lookup**: <10ms (indexed foreign key)

---

## Security Considerations

### Multi-Tenant Isolation

1. **RLS Policies**: All queries filtered by `group_id` via RLS
2. **User Ownership**: Templates can only be modified by creator (`user_id`)
3. **Group Access**: All family group members can view templates
4. **Instance Creation**: Only template owner can create instances (background task runs with user auth)

### Data Validation

1. **Amount**: Server-side check constraint (amount > 0)
2. **Frequency**: Enum constraint prevents invalid values
3. **Category**: Foreign key ensures referential integrity
4. **Timestamps**: Server-managed to prevent client manipulation

### Audit Trail

- `created_at` / `updated_at`: Track template changes
- `recurring_expense_instances`: Complete history of generated instances
- `scheduledDate` vs `createdAt`: Detect delays or failures in background task

---

## Summary

This data model provides:

1. **Template-based recurring expenses** with flexible frequency options
2. **Budget reservation** calculations integrated with existing budget system
3. **Audit trail** for all generated instances
4. **Offline-first** architecture with bidirectional sync
5. **Multi-user isolation** via RLS policies
6. **Clean separation** between templates and instances
7. **Performance optimization** via strategic indexes
8. **Data integrity** via foreign key constraints and check constraints

The design reuses existing architectural patterns (Drift + Supabase, Riverpod, Clean Architecture) and integrates seamlessly with Feature 010 (Offline Sync) and Feature 012 (Reimbursements).
