# Research & Technical Decisions

**Feature**: Cash Payment Default Fix & Admin Expense Management
**Branch**: `001-admin-expenses-cash-fix`
**Date**: 2026-01-18

This document records all technical decisions made during Phase 0 research, including rationale and alternatives considered.

---

## 1. Audit Trail Implementation

### Decision: Use Existing `updated_at` + Add `last_modified_by` Column

**Rationale**:
- Database already has `updated_at` timestamps on all tables (verified in migrations 001_initial_schema.sql)
- Supabase doesn't provide automatic "modified by" tracking - must be explicit
- FR-014 requires visibility of "who last modified" for all users
- Simple column addition is less complex than trigger-based audit logging

**Implementation**:
- Add `last_modified_by` UUID column to `expenses` table
- Set to `created_by` on initial insert
- Update to current user ID on any modification
- Display both `created_by` and `last_modified_by` in UI

**Alternatives Considered**:
1. **Supabase Audit Triggers** - Rejected: Overkill for simple "who modified" tracking; adds complexity
2. **Separate Audit Log Table** - Rejected: Not needed for basic requirement; only if full history tracking required
3. **Updated_at Only** - Rejected: Doesn't track WHO modified, only WHEN

**Impact**:
- ✅ Database migration required: `ALTER TABLE expenses ADD COLUMN last_modified_by UUID`
- ✅ Update ExpenseEntity and ExpenseModel to include new field
- ✅ Modify expense save logic to set last_modified_by

---

## 2. Member Selector UX Pattern

### Decision: Dropdown (DropdownButtonFormField) - Consistent with Payment Method Selector

**Rationale**:
- Matches existing `PaymentMethodSelector` pattern (found in `payment_method_selector.dart`)
- Category picker uses Dialog (found in `category_picker_dialog.dart`) but categories have more complex needs
- Group members typically 2-10 users - fits well in dropdown
- Maintains UI consistency across expense form selectors

**Implementation**:
- Create `MemberSelector` widget similar to `PaymentMethodSelector`
- Use `DropdownButtonFormField<String>` with member IDs as values
- Show member names with optional avatar/icon
- Display only for administrators (conditional rendering)
- Default to current user for admin (allows creating for self or others)

**Alternatives Considered**:
1. **Dialog (like CategoryPicker)** - Rejected: Overkill for small member list; adds extra tap
2. **Bottom Sheet** - Rejected: Inconsistent with other selectors; too heavy for simple selection
3. **Radio List** - Rejected: Takes too much vertical space in form

**Impact**:
- ✅ Create new widget: `lib/features/expenses/presentation/widgets/member_selector.dart`
- ✅ Add conditional rendering in `manual_expense_screen.dart`
- ✅ Use existing `groupMembersProvider` from groups feature

---

## 3. Payment Method Default Initialization

### Decision: Fix in Parent Screen (ManualExpenseScreen.initState)

**Rationale**:
- Root cause: `PaymentMethodSelector` sets `effectiveValue` for display but doesn't call `onChanged`
- Widget should remain stateless and reusable
- Parent screen controls form state - initialization belongs there
- Aligns with Riverpod best practice: widgets observe, screens manage state

**Implementation**:
- In `ManualExpenseScreen.initState()`, watch `paymentMethodProvider(userId)`
- Use `WidgetsBinding.instance.addPostFrameCallback` to set `_selectedPaymentMethodId` after first build
- Set to `paymentMethodState.defaultContanti?.id` if `_selectedPaymentMethodId` is null
- Widget remains unchanged - continues to use `effectiveValue` for display

**Code Pattern**:
```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final paymentMethodState = ref.read(paymentMethodProvider(userId));
    if (_selectedPaymentMethodId == null && paymentMethodState.defaultContanti != null) {
      setState(() {
        _selectedPaymentMethodId = paymentMethodState.defaultContanti!.id;
      });
    }
  });
}
```

**Alternatives Considered**:
1. **Fix in Widget (useEffect/autoDispose)** - Rejected: Makes widget stateful; violates separation of concerns
2. **Provider-level Default** - Rejected: Form state should be explicit, not implicit in provider
3. **Add Callback to Widget** - Rejected: Widget already has onChanged; problem is parent not calling it

**Impact**:
- ✅ Modify `manual_expense_screen.dart` initState only
- ✅ No changes to `payment_method_selector.dart` widget
- ✅ Maintains widget reusability and testability

---

## 4. Optimistic Locking Strategy

### Decision: Timestamp-Based Conflict Detection (updated_at comparison)

**Rationale**:
- `updated_at` column already exists on expenses table
- Supabase supports atomic compare-and-swap with WHERE clauses
- No schema migration required
- Simpler than version numbers - leverages existing infrastructure

**Implementation**:
- On edit screen load, store original `updated_at` timestamp
- On save, include WHERE clause: `WHERE id = $1 AND updated_at = $2`
- If update affects 0 rows, conflict detected
- Show error message: "Expense was modified by another user. Please refresh and try again."
- User must refresh to see latest data and retry

**SQL Pattern**:
```sql
UPDATE expenses
SET amount = $new_amount,
    updated_at = NOW(),
    last_modified_by = $user_id
WHERE id = $expense_id
  AND updated_at = $original_timestamp
RETURNING *;
```

**Alternatives Considered**:
1. **Version Number Column** - Rejected: Requires migration; timestamp serves same purpose
2. **Last-Write-Wins (No Locking)** - Rejected: Violates FR-012 (first-save-wins requirement)
3. **Pessimistic Locking (SELECT FOR UPDATE)** - Rejected: Complex; not well-supported in Supabase RLS
4. **Automatic Merge** - Rejected: Too complex for expense data; users should decide

**Impact**:
- ✅ No database migration required
- ✅ Add conflict detection logic in `expense_repository_impl.dart`
- ✅ Handle `ConflictException` in UI layer
- ✅ Add error message and refresh prompt

---

## 5. Expense Edit Screen Route

### Decision: Reuse ManualExpenseScreen with Edit Mode Parameter

**Rationale**:
- DRY principle - avoid duplicating form logic
- ManualExpenseScreen already has all necessary form fields
- Edit mode differences are minimal (pre-populate fields, change title, update vs. create)
- Existing codebase pattern: screens handle both create and edit modes

**Implementation**:
- Add optional `Expense? expenseToEdit` parameter to `ManualExpenseScreen`
- If `expenseToEdit` is non-null, screen operates in edit mode:
  - Pre-populate all form fields from expense
  - Change screen title to "Modifica Spesa"
  - Save button calls `updateExpense` instead of `createExpense`
  - Navigation route: `/expense/:id/edit` passes expense ID, screen loads expense data
- Form validation and submission logic shared between modes

**Route Configuration** (go_router):
```dart
GoRoute(
  path: 'expense/:id/edit',
  builder: (context, state) {
    final expenseId = state.pathParameters['id']!;
    return ManualExpenseScreen(expenseId: expenseId); // Screen loads expense internally
  },
),
```

**Alternatives Considered**:
1. **Separate ExpenseEditScreen** - Rejected: Code duplication; maintenance burden
2. **Unified Form Widget + Two Screens** - Rejected: Over-engineered; adds abstraction layer
3. **Modal Sheet Instead of Screen** - Rejected: Editing requires full screen space; better UX as dedicated route

**Impact**:
- ✅ Modify `manual_expense_screen.dart` to support edit mode
- ✅ Add route in navigation configuration
- ✅ Load expense data when `expenseId` parameter provided
- ✅ Conditional logic for create vs. update operations

---

## 6. Admin Demotion Real-Time Detection

### Decision: Riverpod Auto-Invalidation + Navigation Guard

**Rationale**:
- Riverpod providers auto-refresh when dependencies change
- Supabase Realtime already tracks group membership changes
- Navigation guard pattern exists in codebase (`navigation_guard.dart`)
- Immediate feedback prevents security issues

**Implementation**:
- `isGroupAdminProvider` watches `groupProvider` which listens to Realtime
- When group data updates (member role changed), provider auto-invalidates
- In edit screen, watch `isGroupAdminProvider` in build method
- If admin status becomes false while viewing, show error snackbar and navigate away
- Use existing `NavigationGuard` pattern for consistency

**Code Pattern**:
```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final isAdmin = ref.watch(isGroupAdminProvider);

  // Listen for admin status changes
  ref.listen<bool>(isGroupAdminProvider, (previous, next) {
    if (previous == true && next == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Access revoked: Admin privileges removed')),
      );
      context.go('/expenses'); // Navigate to safe screen
    }
  });

  // ... rest of build
}
```

**Alternatives Considered**:
1. **Polling/Manual Refresh** - Rejected: Slow response; poor UX
2. **WebSocket Listener** - Rejected: Supabase Realtime already provides this
3. **Periodic Permission Check** - Rejected: Wasteful; Riverpod provides reactive solution

**Impact**:
- ✅ No new code needed - leverage existing Realtime subscription
- ✅ Add listener in edit screen widget
- ✅ Handle navigation on permission revocation

---

## 7. Removed User Expense Handling

### Decision: Allow Historical Operations + Display "Removed User" in UI

**Rationale**:
- Per clarification A1: "Allow the operation - expense remains linked to the removed user's historical record"
- Historical data integrity important for auditing
- User removal doesn't delete their profile UUID - just removes group membership
- Expense foreign key references `profiles.id`, not `group_members.id`

**Implementation**:
- No database constraints to change
- When displaying expenses for removed user:
  - Show member name as "(Removed User)" if lookup fails
  - Gray out or add icon indicator
  - Still allow admin to view/edit expense
- Member selector filters out removed users (only show active members)

**UI Display Pattern**:
- In expense list: "Created by: (Removed User)"
- In audit trail: "Last modified by: John Doe" (if modifier still active)
- In member selector: Only active group members appear

**Alternatives Considered**:
1. **Block Operations on Removed Users** - Rejected: Violates clarification A1
2. **Cascade Delete Expenses** - Rejected: Loses historical data; violates audit requirements
3. **Reassign to Admin** - Rejected: Falsifies history; clarification specifies maintaining link

**Impact**:
- ✅ No database changes needed
- ✅ Add defensive null handling for member name lookups
- ✅ UI indicates removed user status

---

## 8. Default Payment Method Deletion Handling

### Decision: Auto-Select First Available + Error if None Exist

**Rationale**:
- Per clarification A5: "Auto-select first available payment method - if none exist, show error requiring payment method setup"
- Robust fallback behavior prevents blocking users
- Graceful degradation: system continues working with alternative
- Error case (no methods) should rarely occur since defaults exist

**Implementation**:
- In `PaymentMethodSelector.build()`:
  - If `defaultContanti` is null (deleted/deactivated)
  - Set `effectiveValue = paymentMethodState.allMethods.firstOrNull?.id`
  - If `allMethods` is empty, show error widget instead of dropdown
- Error widget displays: "No payment methods available. Please contact administrator."
- Admin can re-create "Contanti" or users can create custom methods

**Code Pattern**:
```dart
// In PaymentMethodSelector
final effectiveValue = selectedId
  ?? paymentMethodState.defaultContanti?.id
  ?? paymentMethodState.allMethods.firstOrNull?.id;

if (paymentMethodState.isEmpty) {
  return const ListTile(
    leading: Icon(Icons.error, color: Colors.red),
    title: Text('No payment methods available'),
    subtitle: Text('Please contact administrator to set up payment methods'),
  );
}
```

**Alternatives Considered**:
1. **Prevent Deletion of Contanti** - Rejected: Too restrictive; users should have flexibility
2. **Force Re-Creation** - Rejected: Can't force user action; better to show helpful error
3. **Allow Null Payment Method** - Rejected: Violates database NOT NULL constraint

**Impact**:
- ✅ Modify `payment_method_selector.dart` fallback logic
- ✅ Add empty state error widget
- ✅ No database changes (existing NOT NULL constraint enforces requirement)

---

## Summary of Decisions

| Research Area | Decision | Migration Required | New Files |
|---------------|----------|-------------------|-----------|
| 1. Audit Trail | Add `last_modified_by` column | ✅ Yes | 0 |
| 2. Member Selector | Dropdown widget | ❌ No | 1 (member_selector.dart) |
| 3. Payment Default Fix | Parent screen initState | ❌ No | 0 |
| 4. Optimistic Locking | Timestamp-based (updated_at) | ❌ No | 0 |
| 5. Edit Screen | Reuse ManualExpenseScreen | ❌ No | 0 |
| 6. Admin Demotion | Riverpod auto-invalidation | ❌ No | 0 |
| 7. Removed Users | Allow historical operations | ❌ No | 0 |
| 8. Payment Deletion | Auto-select first available | ❌ No | 0 |

**Total New Files**: 1 (MemberSelector widget)
**Total Migrations**: 1 (Add last_modified_by column)

---

**Research Completed**: 2026-01-18
**Ready for**: Phase 1 (Design & Contracts)
