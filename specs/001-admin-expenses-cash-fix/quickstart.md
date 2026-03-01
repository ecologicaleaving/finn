# Developer Quickstart Guide

**Feature**: Cash Payment Default Fix & Admin Expense Management
**Branch**: `001-admin-expenses-cash-fix`
**Date**: 2026-01-18

This guide provides step-by-step instructions for implementing the feature, including setup, development, testing, and deployment.

---

## Prerequisites

Before starting implementation:

1. ✅ Read the [spec.md](./spec.md) (feature specification)
2. ✅ Read the [research.md](./research.md) (technical decisions)
3. ✅ Read the [data-model.md](./data-model.md) (schema and entity changes)
4. ✅ Ensure you're on branch `001-admin-expenses-cash-fix`
5. ✅ Have local development environment running (Flutter, Supabase local)

**Verify Branch**:
```bash
git branch --show-current
# Should output: 001-admin-expenses-cash-fix
```

---

## Implementation Order

Follow this sequence to avoid dependency issues:

### Phase 1: Database Migration (30 min)
1. Create migration file
2. Test locally
3. Apply to development database

### Phase 2: Data Layer (1 hour)
1. Update ExpenseEntity
2. Update ExpenseModel
3. Add repository methods
4. Update datasource

### Phase 3: UI Components (2 hours)
1. Create MemberSelector widget
2. Fix PaymentMethodSelector initialization
3. Update ManualExpenseScreen

### Phase 4: Business Logic (1.5 hours)
1. Add providers
2. Implement optimistic locking
3. Add admin permission checks
4. Handle edge cases

### Phase 5: Testing (2 hours)
1. Unit tests
2. Widget tests
3. Integration tests
4. Manual QA

**Total Estimated Time**: 6.5-7 hours

---

## Phase 1: Database Migration

### Step 1.1: Create Migration File

Create: `supabase/migrations/0XX_add_expense_audit_fields.sql`

```sql
-- Migration: Add audit trail to expenses
-- Feature: 001-admin-expenses-cash-fix
-- Date: 2026-01-18

-- Add last_modified_by column
ALTER TABLE public.expenses
ADD COLUMN last_modified_by UUID REFERENCES public.profiles(id);

-- Backfill existing rows (set to creator)
UPDATE public.expenses
SET last_modified_by = created_by
WHERE last_modified_by IS NULL;

-- Add comment for documentation
COMMENT ON COLUMN public.expenses.last_modified_by IS
'UUID of user who last modified this expense (tracks audit trail for admin edits)';

-- Create index for query performance
CREATE INDEX idx_expenses_last_modified_by
ON public.expenses(last_modified_by);

-- Verify migration
DO $$
BEGIN
  ASSERT (SELECT COUNT(*) FROM public.expenses WHERE last_modified_by IS NOT NULL) =
         (SELECT COUNT(*) FROM public.expenses),
  'Migration failed: Not all expenses have last_modified_by set';
END $$;
```

### Step 1.2: Test Migration Locally

```bash
# Reset local database (if needed)
supabase db reset

# Apply migration
supabase migration up

# Verify column exists
supabase db diff
```

### Step 1.3: Verify in Database

```sql
-- Check column was added
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'expenses'
  AND column_name = 'last_modified_by';

-- Verify backfill
SELECT created_by, last_modified_by, COUNT(*)
FROM expenses
GROUP BY created_by, last_modified_by;
```

---

## Phase 2: Data Layer Changes

### Step 2.1: Update ExpenseEntity

**File**: `lib/features/expenses/domain/entities/expense_entity.dart`

**Changes**:
```dart
class ExpenseEntity extends Equatable {
  const ExpenseEntity({
    // ... existing fields
    this.lastModifiedBy,  // ← ADD THIS
  });

  // ... existing fields
  final String? lastModifiedBy;  // ← ADD THIS

  @override
  List<Object?> get props => [
    // ... existing fields
    lastModifiedBy,  // ← ADD THIS
  ];

  // ← ADD THESE HELPER METHODS
  /// Check if expense was modified after creation
  bool get wasModified => lastModifiedBy != null && lastModifiedBy != createdBy;

  /// Get display name for last modifier
  String getLastModifiedByName(String currentUserId, Map<String, String> memberNames) {
    if (lastModifiedBy == null || lastModifiedBy == createdBy) {
      return ''; // Not modified after creation
    }
    if (lastModifiedBy == currentUserId) {
      return 'You';
    }
    return memberNames[lastModifiedBy] ?? '(Removed User)';
  }

  ExpenseEntity copyWith({
    // ... existing parameters
    String? lastModifiedBy,  // ← ADD THIS
  }) {
    return ExpenseEntity(
      // ... existing assignments
      lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,  // ← ADD THIS
    );
  }
}
```

### Step 2.2: Update ExpenseModel

**File**: `lib/features/expenses/data/models/expense_model.dart`

**Changes**:
```dart
class ExpenseModel extends ExpenseEntity {
  const ExpenseModel({
    // ... existing fields
    super.lastModifiedBy,  // ← ADD THIS
  });

  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    return ExpenseModel(
      // ... existing fields
      lastModifiedBy: json['last_modified_by'] as String?,  // ← ADD THIS
    );
  }

  Map<String, dynamic> toJson() {
    return {
      // ... existing fields
      'last_modified_by': lastModifiedBy,  // ← ADD THIS
    };
  }
}
```

### Step 2.3: Add Repository Method

**File**: `lib/features/expenses/domain/repositories/expense_repository.dart`

**Add Method**:
```dart
abstract class ExpenseRepository {
  // ... existing methods

  /// Update expense with optimistic locking
  /// Throws ConflictException if updated_at doesn't match
  Future<void> updateExpenseWithTimestamp({
    required String expenseId,
    required String originalUpdatedAt,
    required Map<String, dynamic> updates,
  });
}
```

### Step 2.4: Implement Repository Method

**File**: `lib/features/expenses/data/repositories/expense_repository_impl.dart`

**Add Implementation**:
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
    throw ConflictException('Expense was modified by another user');
  }
}
```

### Step 2.5: Add Datasource Method

**File**: `lib/features/expenses/data/datasources/expense_remote_datasource.dart`

**Add Method**:
```dart
Future<Map<String, dynamic>> updateExpenseWithTimestamp({
  required String expenseId,
  required String originalUpdatedAt,
  required Map<String, dynamic> updates,
}) async {
  // Add updated_at to ensure it's included
  updates['updated_at'] = DateTime.now().toIso8601String();

  final response = await _supabase
      .from('expenses')
      .update(updates)
      .eq('id', expenseId)
      .eq('updated_at', originalUpdatedAt)  // Optimistic lock check
      .select('id, updated_at');

  if (response.isEmpty) {
    return {'affected_rows': 0};  // Conflict detected
  }

  return {'affected_rows': 1, 'data': response.first};
}
```

### Step 2.6: Add ConflictException

**File**: `lib/core/errors/exceptions.dart`

**Add Exception Class**:
```dart
/// Exception thrown when concurrent edit detected (optimistic locking)
class ConflictException implements Exception {
  final String message;
  const ConflictException(this.message);

  @override
  String toString() => message;
}
```

---

## Phase 3: UI Components

### Step 3.1: Create MemberSelector Widget

**File**: `lib/features/expenses/presentation/widgets/member_selector.dart`

**Full Implementation**:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../groups/presentation/providers/group_provider.dart';

/// Widget for selecting a group member (admin-only)
class MemberSelector extends ConsumerWidget {
  const MemberSelector({
    super.key,
    required this.userId,
    this.selectedId,
    required this.onChanged,
    this.enabled = true,
  });

  final String userId;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(groupMembersProvider);

    return membersAsync.when(
      data: (members) {
        // Filter out removed users (only active members)
        final activeMembers = members.where((m) => m.isActive).toList();

        if (activeMembers.isEmpty) {
          return const ListTile(
            leading: Icon(Icons.error, color: Colors.red),
            title: Text('No active members'),
          );
        }

        return DropdownButtonFormField<String>(
          value: selectedId ?? userId,  // Default to current user
          decoration: const InputDecoration(
            labelText: 'Spesa per',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person),
            helperText: 'Seleziona il membro a cui attribuire la spesa',
          ),
          items: activeMembers.map((member) {
            return DropdownMenuItem<String>(
              value: member.id,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    child: Text(
                      member.name[0].toUpperCase(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(member.name),
                  if (member.id == userId)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Chip(
                        label: Text('Tu', style: TextStyle(fontSize: 10)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
          onChanged: enabled ? onChanged : null,
        );
      },
      loading: () => const CircularProgressIndicator(),
      error: (error, stack) => ListTile(
        leading: const Icon(Icons.error, color: Colors.red),
        title: const Text('Error loading members'),
        subtitle: Text(error.toString()),
      ),
    );
  }
}
```

### Step 3.2: Fix PaymentMethodSelector Initialization

**File**: `lib/features/expenses/presentation/screens/manual_expense_screen.dart`

**Add initState logic**:
```dart
@override
void initState() {
  super.initState();

  // Initialize default payment method after first build
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final userId = ref.read(currentUserIdProvider);
    if (userId != null) {
      final paymentMethodState = ref.read(paymentMethodProvider(userId));

      // Set default if not already selected
      if (_selectedPaymentMethodId == null && paymentMethodState.defaultContanti != null) {
        setState(() {
          _selectedPaymentMethodId = paymentMethodState.defaultContanti!.id;
        });
      }
    }
  });
}
```

### Step 3.3: Add Member Selector to ManualExpenseScreen

**File**: `lib/features/expenses/presentation/screens/manual_expense_screen.dart`

**Add state variable**:
```dart
class _ManualExpenseScreenState extends ConsumerState<ManualExpenseScreen> {
  // ... existing state
  String? _selectedMemberIdForExpense;  // ← ADD THIS

  // ... rest of class
}
```

**Add to form (after payment method selector)**:
```dart
// In build method, after PaymentMethodSelector
if (isAdmin)  // Only show for admins
  Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: MemberSelector(
      userId: currentUserId!,
      selectedId: _selectedMemberIdForExpense,
      onChanged: (memberId) {
        setState(() {
          _selectedMemberIdForExpense = memberId;
        });
      },
    ),
  ),
```

### Step 3.4: Display Audit Trail in UI

**File**: `lib/features/expenses/presentation/screens/expense_detail_screen.dart`

**Add audit trail section**:
```dart
// In build method, after other expense details
if (expense.wasModified)
  Card(
    child: ListTile(
      leading: const Icon(Icons.history),
      title: const Text('Modifica'),
      subtitle: Text(
        'Modificato da ${expense.getLastModifiedByName(currentUserId, memberNamesMap)}',
      ),
      trailing: Text(
        formatDate(expense.updatedAt),
        style: theme.textTheme.bodySmall,
      ),
    ),
  ),
```

---

## Phase 4: Business Logic

### Step 4.1: Add Providers

**File**: `lib/features/expenses/presentation/providers/expense_provider.dart`

**Add state provider**:
```dart
/// Selected member ID for admin expense creation
final selectedMemberForExpenseProvider = StateProvider.autoDispose<String?>((ref) => null);
```

### Step 4.2: Update Form Submission

**File**: `lib/features/expenses/presentation/screens/manual_expense_screen.dart`

**Update _submitForm method**:
```dart
Future<void> _submitForm() async {
  if (!_formKey.currentState!.validate()) return;

  final currentUserId = ref.read(currentUserIdProvider);
  final isAdmin = ref.read(isGroupAdminProvider);

  // Determine expense creator
  final creatorId = (isAdmin && _selectedMemberIdForExpense != null)
      ? _selectedMemberIdForExpense!
      : currentUserId!;

  final expenseData = {
    'amount': double.parse(_amountController.text),
    'date': _selectedDate.toIso8601String(),
    'category_id': _selectedCategoryId,
    'payment_method_id': _selectedPaymentMethodId,
    'merchant': _merchantController.text.trim().isEmpty ? null : _merchantController.text.trim(),
    'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    'is_group_expense': _isGroupExpense,
    'created_by': creatorId,  // ← Admin can create for others
    'last_modified_by': currentUserId,  // ← Always set to current user
  };

  // Submit...
}
```

### Step 4.3: Implement Optimistic Locking

**File**: `lib/features/expenses/presentation/providers/expense_form_notifier.dart`

**Add method**:
```dart
Future<void> updateExpenseWithLock({
  required String expenseId,
  required String originalUpdatedAt,
  required Map<String, dynamic> updates,
}) async {
  state = const AsyncValue.loading();

  state = await AsyncValue.guard(() async {
    final currentUserId = _ref.read(currentUserIdProvider);
    updates['last_modified_by'] = currentUserId;

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

### Step 4.4: Handle Admin Demotion

**File**: `lib/features/expenses/presentation/screens/manual_expense_screen.dart`

**Add listener in build method**:
```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final isAdmin = ref.watch(isGroupAdminProvider);

  // Listen for admin status changes
  ref.listen<bool>(isGroupAdminProvider, (previous, next) {
    if (previous == true && next == false && widget.isEditMode) {
      // Admin was demoted while editing - revoke access
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access revoked: Admin privileges removed'),
          backgroundColor: Colors.red,
        ),
      );
      context.go('/expenses');  // Navigate away
    }
  });

  // ... rest of build
}
```

---

## Phase 5: Testing

### Step 5.1: Unit Tests

**File**: `test/features/expenses/domain/entities/expense_entity_test.dart`

**Add tests**:
```dart
group('ExpenseEntity audit trail', () {
  test('wasModified returns false when lastModifiedBy is null', () {
    final expense = ExpenseEntity(
      // ... required fields
      createdBy: 'user-1',
      lastModifiedBy: null,
    );

    expect(expense.wasModified, false);
  });

  test('wasModified returns false when lastModifiedBy equals createdBy', () {
    final expense = ExpenseEntity(
      // ... required fields
      createdBy: 'user-1',
      lastModifiedBy: 'user-1',
    );

    expect(expense.wasModified, false);
  });

  test('wasModified returns true when lastModifiedBy differs from createdBy', () {
    final expense = ExpenseEntity(
      // ... required fields
      createdBy: 'user-1',
      lastModifiedBy: 'admin-2',
    );

    expect(expense.wasModified, true);
  });

  test('getLastModifiedByName returns empty string when not modified', () {
    final expense = ExpenseEntity(
      // ... required fields
      createdBy: 'user-1',
      lastModifiedBy: null,
    );

    expect(expense.getLastModifiedByName('current-user', {}), '');
  });

  test('getLastModifiedByName returns "You" for current user', () {
    final expense = ExpenseEntity(
      // ... required fields
      createdBy: 'user-1',
      lastModifiedBy: 'user-2',
    );

    expect(expense.getLastModifiedByName('user-2', {}), 'You');
  });

  test('getLastModifiedByName returns member name from map', () {
    final expense = ExpenseEntity(
      // ... required fields
      createdBy: 'user-1',
      lastModifiedBy: 'user-2',
    );

    final memberNames = {'user-2': 'John Doe'};
    expect(expense.getLastModifiedByName('user-1', memberNames), 'John Doe');
  });

  test('getLastModifiedByName returns "(Removed User)" when member not found', () {
    final expense = ExpenseEntity(
      // ... required fields
      createdBy: 'user-1',
      lastModifiedBy: 'user-removed',
    );

    expect(expense.getLastModifiedByName('user-1', {}), '(Removed User)');
  });
});
```

### Step 5.2: Widget Tests

**File**: `test/features/expenses/presentation/widgets/payment_method_selector_test.dart`

**Add test**:
```dart
testWidgets('initializes with default Contanti when selectedId is null', (tester) async {
  // Setup provider override with default Contanti
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        paymentMethodProvider('user-1').overrideWith((ref) {
          return PaymentMethodState(
            defaultContanti: PaymentMethodEntity(id: 'contanti-id', name: 'Contanti'),
            // ... other fields
          );
        }),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PaymentMethodSelector(
            userId: 'user-1',
            selectedId: null,  // Not selected
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();

  // Verify dropdown shows Contanti
  expect(find.text('Contanti'), findsOneWidget);
});
```

### Step 5.3: Integration Tests

**File**: `integration_test/expense_management_test.dart`

**Add tests**:
```dart
testWidgets('admin can create expense for another member', (tester) async {
  // Setup: Login as admin
  // Navigate to expense creation screen
  // Select member from dropdown
  // Fill form
  // Submit
  // Verify expense created with correct created_by
});

testWidgets('payment method defaults to Contanti on load', (tester) async {
  // Navigate to expense creation
  // Verify payment method selector shows Contanti
  // Submit form without touching payment method
  // Verify expense saved with Contanti payment method
});

testWidgets('concurrent edit shows error message', (tester) async {
  // Open expense for editing
  // Simulate concurrent update (change updated_at in database)
  // Try to save
  // Verify error message appears
  // Verify refresh option available
});
```

### Step 5.4: Manual QA Checklist

Run through these scenarios manually:

**Payment Method Default Fix**:
- [ ] Create new expense - verify "Contanti" is pre-selected
- [ ] Save expense without touching payment method - verify save succeeds
- [ ] Verify payment method saved as "Contanti"
- [ ] Delete "Contanti" payment method - verify first available method selected
- [ ] Delete all payment methods - verify error message shown

**Admin Create Expense**:
- [ ] Login as admin
- [ ] Create expense screen shows member selector
- [ ] Select different member from dropdown
- [ ] Save expense - verify created_by is selected member
- [ ] Expense appears in selected member's expense list
- [ ] Login as non-admin - verify member selector not shown

**Admin Edit Expense**:
- [ ] Login as admin
- [ ] View another member's expense
- [ ] Edit button is visible
- [ ] Edit and save - verify last_modified_by updated
- [ ] Verify audit trail shows "Modified by Admin Name"
- [ ] Original creator information preserved

**Concurrent Edit Conflict**:
- [ ] Open expense in two browser windows as different users
- [ ] Edit in first window and save
- [ ] Edit in second window and try to save
- [ ] Verify error message: "Expense was modified by another user"
- [ ] Click refresh - verify latest data loaded

**Admin Demotion**:
- [ ] Login as admin
- [ ] Open another member's expense for editing
- [ ] Have another admin demote you to regular member
- [ ] Verify access revoked immediately
- [ ] Verify redirect to expenses list
- [ ] Verify error message shown

---

## Deployment Checklist

Before deploying to production:

### Database
- [ ] Migration tested locally
- [ ] Migration tested in staging environment
- [ ] Rollback script prepared and tested
- [ ] Index performance verified

### Code
- [ ] All unit tests passing
- [ ] All integration tests passing
- [ ] Code reviewed by teammate
- [ ] No linter warnings
- [ ] Documentation updated

### QA
- [ ] Manual QA checklist completed
- [ ] Edge cases tested
- [ ] Performance acceptable (<500ms save latency)
- [ ] Offline mode works correctly

### Monitoring
- [ ] Error tracking configured for ConflictException
- [ ] Metrics tracking for admin expense creation
- [ ] Alerts configured for migration failures

---

## Troubleshooting

### Issue: Payment method still requires reselection

**Diagnosis**: initState callback not firing or payment method state not loaded yet

**Solution**:
```dart
// Verify provider is loaded
final paymentMethodState = ref.read(paymentMethodProvider(userId));
print('Default Contanti: ${paymentMethodState.defaultContanti?.id}');

// Check if post-frame callback is firing
WidgetsBinding.instance.addPostFrameCallback((_) {
  print('Post-frame callback fired');
  // ... initialization logic
});
```

### Issue: Member selector not showing for admin

**Diagnosis**: isGroupAdminProvider returning false

**Solution**:
```dart
// Verify admin status
final isAdmin = ref.read(isGroupAdminProvider);
print('Is Admin: $isAdmin');

// Check group data
final group = ref.read(groupProvider).group;
final currentUser = ref.read(currentUserProvider);
print('Group creator: ${group?.createdBy}');
print('Current user: ${currentUser?.id}');
print('Match: ${group?.isAdmin(currentUser!.id)}');
```

### Issue: Optimistic locking not detecting conflicts

**Diagnosis**: updated_at comparison failing

**Solution**:
```sql
-- Verify timestamp format matches
SELECT id, updated_at::text
FROM expenses
WHERE id = 'expense-id';

-- Check query is using correct WHERE clause
-- Should be: WHERE id = $1 AND updated_at = $2
```

---

## Support

For issues or questions:
1. Check [spec.md](./spec.md) for requirements
2. Check [research.md](./research.md) for technical decisions
3. Check [data-model.md](./data-model.md) for schema details
4. Ask in #dev-support Slack channel

---

**Guide Version**: 1.0
**Last Updated**: 2026-01-18
