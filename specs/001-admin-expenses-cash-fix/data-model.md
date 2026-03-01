# Data Model

**Feature**: Cash Payment Default Fix & Admin Expense Management
**Branch**: `001-admin-expenses-cash-fix`
**Date**: 2026-01-18

This document defines data models, entities, and schema changes required for this feature.

---

## Entity Changes

### 1. ExpenseEntity (Modified)

**File**: `lib/features/expenses/domain/entities/expense_entity.dart`

**New Field Added**:
```dart
final String? lastModifiedBy;  // UUID of user who last modified this expense
```

**Updated Constructor**:
```dart
const ExpenseEntity({
  required this.id,
  required this.groupId,
  required this.createdBy,
  required this.amount,
  required this.date,
  this.categoryId,
  this.categoryName,
  required this.paymentMethodId,
  required this.paymentMethodName,
  required this.isGroupExpense,
  this.merchant,
  this.notes,
  this.receiptUrl,
  this.createdByName,
  required this.createdAt,
  required this.updatedAt,
  this.reimbursementStatus,
  this.reimbursedAt,
  this.recurringExpenseId,
  this.isRecurringInstance = false,
  this.lastModifiedBy,  // ← NEW
});
```

**New Helper Methods**:
```dart
/// Get display name for last modifier
/// Returns "You" if current user, actual name if available, or "(Unknown)" if user removed/unavailable
String getLastModifiedByName(String currentUserId, Map<String, String> memberNames) {
  if (lastModifiedBy == null || lastModifiedBy == createdBy) {
    return ''; // Not modified after creation
  }
  if (lastModifiedBy == currentUserId) {
    return 'You';
  }
  return memberNames[lastModifiedBy] ?? '(Removed User)';
}

/// Check if expense was modified after creation
bool get wasModified => lastModifiedBy != null && lastModifiedBy != createdBy;
```

**Rationale**: Supports FR-014 (display audit information visible to all users) and tracks who made changes for transparency.

---

### 2. ExpenseModel (Modified)

**File**: `lib/features/expenses/data/models/expense_model.dart`

**New Field in fromJson**:
```dart
factory ExpenseModel.fromJson(Map<String, dynamic> json) {
  return ExpenseModel(
    // ... existing fields
    lastModifiedBy: json['last_modified_by'] as String?,  // ← NEW
  );
}
```

**New Field in toJson**:
```dart
Map<String, dynamic> toJson() {
  return {
    // ... existing fields
    'last_modified_by': lastModifiedBy,  // ← NEW
  };
}
```

**Rationale**: Ensures database field mapping for audit trail persistence.

---

### 3. MemberSelectorState (New Model)

**File**: `lib/features/expenses/presentation/widgets/member_selector.dart` (embedded in same file)

**Purpose**: Manage state for member selection in admin expense creation/editing.

```dart
/// State model for member selector dropdown
class MemberSelectorState {
  const MemberSelectorState({
    required this.members,
    this.selectedMemberId,
    this.isLoading = false,
    this.errorMessage,
  });

  final List<MemberEntity> members;
  final String? selectedMemberId;
  final bool isLoading;
  final String? errorMessage;

  /// Get currently selected member
  MemberEntity? get selectedMember =>
      members.cast<MemberEntity?>().firstWhere(
        (m) => m?.id == selectedMemberId,
        orElse: () => null,
      );

  /// Get member name for display
  String getMemberName(String? memberId) {
    if (memberId == null) return '';
    return members
            .cast<MemberEntity?>()
            .firstWhere(
              (m) => m?.id == memberId,
              orElse: () => null,
            )
            ?.name ??
        '(Unknown)';
  }

  MemberSelectorState copyWith({
    List<MemberEntity>? members,
    String? selectedMemberId,
    bool? isLoading,
    String? errorMessage,
  }) {
    return MemberSelectorState(
      members: members ?? this.members,
      selectedMemberId: selectedMemberId ?? this.selectedMemberId,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
```

**Rationale**: Encapsulates member selection logic, provides type-safe access to member data.

---

### 4. ExpenseEditFormState (Conceptual - Not a Separate Model)

**Purpose**: Manage state in ManualExpenseScreen when in edit mode.

**Implementation**: Add boolean flag and expense reference to existing screen state:

```dart
// In ManualExpenseScreen state
final Expense? _expenseToEdit;  // Non-null when editing
final String? _originalUpdatedAt;  // For optimistic locking

bool get isEditMode => _expenseToEdit != null;
```

**Form Field Initialization**:
```dart
@override
void initState() {
  super.initState();

  if (isEditMode) {
    // Pre-populate form fields
    _amountController.text = _expenseToEdit!.amount.toString();
    _dateController.text = formatDate(_expenseToEdit!.date);
    _merchantController.text = _expenseToEdit?.merchant ?? '';
    _notesController.text = _expenseToEdit?.notes ?? '';
    _selectedCategoryId = _expenseToEdit!.categoryId;
    _selectedPaymentMethodId = _expenseToEdit!.paymentMethodId;
    _isGroupExpense = _expenseToEdit!.isGroupExpense;
    _originalUpdatedAt = _expenseToEdit!.updatedAt.toIso8601String();
  } else {
    // Initialize default payment method
    _initializeDefaultPaymentMethod();
  }
}
```

**Rationale**: Reuses existing ManualExpenseScreen state management, avoids creating unnecessary abstraction.

---

## Database Schema Changes

### Migration: Add Audit Fields to Expenses Table

**File**: `supabase/migrations/0XX_add_expense_audit_fields.sql` (number to be determined)

**Schema Change**:
```sql
-- Add last_modified_by column to expenses table
ALTER TABLE public.expenses
ADD COLUMN last_modified_by UUID REFERENCES public.profiles(id);

-- Set default value to created_by for existing rows
UPDATE public.expenses
SET last_modified_by = created_by
WHERE last_modified_by IS NULL;

-- Add comment
COMMENT ON COLUMN public.expenses.last_modified_by IS
'UUID of user who last modified this expense (for audit trail)';

-- Create index for efficient lookup
CREATE INDEX idx_expenses_last_modified_by
ON public.expenses(last_modified_by);
```

**Rollback Script**:
```sql
-- Remove index
DROP INDEX IF EXISTS idx_expenses_last_modified_by;

-- Remove column
ALTER TABLE public.expenses
DROP COLUMN IF EXISTS last_modified_by;
```

**Rationale**:
- Supports FR-014 requirement to display who last modified expenses
- Nullable column allows distinction between "not modified" and "modified by X"
- Index improves query performance when filtering/joining by modifier
- Backfills existing data to maintain consistency

---

## State Management Changes

### New Providers

#### 1. selectedMemberForExpenseProvider (StateProvider)

**File**: `lib/features/expenses/presentation/providers/expense_provider.dart`

```dart
/// Selected member ID for admin expense creation
/// Only used when current user is admin creating expense for another member
final selectedMemberForExpenseProvider = StateProvider.autoDispose<String?>((ref) => null);
```

**Usage**: In ManualExpenseScreen, admins can select which group member the expense is for.

**Rationale**: Simple state provider sufficient for temporary form state.

---

### Modified Providers

#### 1. expense FormNotifier (Enhanced)

**File**: `lib/features/expenses/presentation/providers/expense_form_notifier.dart`

**New Methods**:
```dart
/// Update existing expense with optimistic locking
Future<void> updateExpenseWithLock({
  required String expenseId,
  required String originalUpdatedAt,
  required Map<String, dynamic> updates,
}) async {
  state = const AsyncValue.loading();
  state = await AsyncValue.guard(() async {
    final currentUserId = _ref.read(currentUserIdProvider);
    updates['last_modified_by'] = currentUserId;
    updates['updated_at'] = DateTime.now().toIso8601String();

    try {
      await _repository.updateExpenseWithTimestamp(
        expenseId: expenseId,
        originalUpdatedAt: originalUpdatedAt,
        updates: updates,
      );
    } on ConflictException {
      throw Exception('Expense was modified by another user. Please refresh and try again.');
    }
  });
}
```

**Rationale**: Implements FR-012 (optimistic locking with first-save-wins semantics).

---

## Repository Method Changes

### ExpenseRepository (Interface Update)

**File**: `lib/features/expenses/domain/repositories/expense_repository.dart`

**New Method**:
```dart
/// Update expense with timestamp-based optimistic locking
/// Throws ConflictException if updated_at doesn't match (concurrent edit detected)
Future<void> updateExpenseWithTimestamp({
  required String expenseId,
  required String originalUpdatedAt,
  required Map<String, dynamic> updates,
});
```

### ExpenseRepositoryImpl (Implementation)

**File**: `lib/features/expenses/data/repositories/expense_repository_impl.dart`

**New Method Implementation**:
```dart
@override
Future<void> updateExpenseWithTimestamp({
  required String expenseId,
  required String originalUpdatedAt,
  required Map<String, dynamic> updates,
}) async {
  final result = await _remoteDatasource.updateExpenseWithTimestamp(
    expenseId: expenseId,
    originalUpdatedAt: originalUpdatedAt,
    updates: updates,
  );

  if (result['affected_rows'] == 0) {
    throw ConflictException('Expense was modified concurrently');
  }
}
```

### ExpenseRemoteDatasource (New Method)

**File**: `lib/features/expenses/data/datasources/expense_remote_datasource.dart`

**New Method**:
```dart
Future<Map<String, dynamic>> updateExpenseWithTimestamp({
  required String expenseId,
  required String originalUpdatedAt,
  required Map<String, dynamic> updates,
}) async {
  final response = await _supabase
      .from('expenses')
      .update(updates)
      .eq('id', expenseId)
      .eq('updated_at', originalUpdatedAt)
      .select('id, updated_at');

  if (response.isEmpty) {
    return {'affected_rows': 0};
  }

  return {'affected_rows': 1, 'data': response.first};
}
```

**Rationale**: Implements timestamp-based optimistic locking at database level using Supabase WHERE clause.

---

## Validation Rules

### Member Selection (Admin Only)

**Rule**: Only group administrators can select a member for expense creation.

**Implementation**:
```dart
// In ManualExpenseScreen
final isAdmin = ref.watch(isGroupAdminProvider);
final selectedMemberId = ref.watch(selectedMemberForExpenseProvider);

// Show member selector only if admin
if (isAdmin) {
  MemberSelector(
    userId: currentUserId,
    selectedId: selectedMemberId,
    onChanged: (memberId) {
      ref.read(selectedMemberForExpenseProvider.notifier).state = memberId;
    },
  )
}

// On save, use selected member or default to current user
final expenseCreator = isAdmin && selectedMemberId != null
    ? selectedMemberId
    : currentUserId;
```

### Concurrent Edit Detection

**Rule**: FR-012 requires first-save-wins with error notification on conflict.

**Implementation**:
```dart
try {
  await ref.read(expenseFormNotifierProvider.notifier).updateExpenseWithLock(
    expenseId: expense.id,
    originalUpdatedAt: originalUpdatedAt,
    updates: formData,
  );
  // Success - show confirmation
} on Exception catch (e) {
  if (e.toString().contains('modified by another user')) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.toString()),
        action: SnackBarAction(
          label: 'Refresh',
          onPressed: () => _refreshExpenseData(),
        ),
      ),
    );
  }
}
```

---

## State Transitions

### Expense Lifecycle with Audit Trail

```
┌─────────────┐
│   Created   │ (created_by = User A, last_modified_by = null)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ First Edit  │ (created_by = User A, last_modified_by = User A)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Admin Edit  │ (created_by = User A, last_modified_by = Admin B)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Concurrent  │ (First save wins, second save gets ConflictException)
│    Edit     │
└─────────────┘
```

**Key States**:
1. **Just Created**: `last_modified_by` is null (no modifications yet)
2. **Self-Modified**: `last_modified_by` equals `created_by`
3. **Admin-Modified**: `last_modified_by` differs from `created_by`
4. **Conflict Detected**: `updated_at` mismatch on save attempt

---

## Relationships

### Expense → User (Audit Trail)

```
expenses
├── created_by → profiles.id (who owns the expense)
└── last_modified_by → profiles.id (who last changed it)
```

**Cardinality**: Many-to-One (many expenses can have same creator/modifier)

**Cascade Behavior**:
- User profile deletion: RESTRICT (prevent deletion of users with expenses)
- Group member removal: No cascade (expense remains linked to removed user's profile)

---

## Summary of Changes

| Model/Schema | Change Type | Purpose |
|--------------|-------------|---------|
| ExpenseEntity | Add field: `lastModifiedBy` | Track audit trail |
| ExpenseModel | Add JSON mapping | Persist audit data |
| MemberSelectorState | New model | Member selection UI |
| expenses table | Add column: `last_modified_by` | Store modifier |
| expenses table | Add index: `idx_expenses_last_modified_by` | Query performance |
| ExpenseRepository | Add method: `updateExpenseWithTimestamp` | Optimistic locking |
| selectedMemberForExpenseProvider | New provider | Admin member selection state |
| expenseFormNotifier | Add method: `updateExpenseWithLock` | Conflict detection |

**Total New Models**: 1 (MemberSelectorState - inline definition)
**Total Modified Entities**: 2 (ExpenseEntity, ExpenseModel)
**Total Schema Changes**: 1 migration (add audit column)

---

**Data Model Completed**: 2026-01-18
**Ready for**: Quickstart Guide Generation
