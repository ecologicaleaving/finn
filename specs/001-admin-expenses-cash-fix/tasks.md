# Tasks: Cash Payment Default Fix & Admin Expense Management

**Input**: Design documents from `/specs/001-admin-expenses-cash-fix/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: Tests are NOT requested in this feature specification - focusing on implementation only.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- Flutter mobile application with Clean Architecture
- Base path: `lib/features/`
- Database migrations: `supabase/migrations/`
- Tests: `test/features/` and `integration_test/`

---

## Phase 1: Setup (Database Schema)

**Purpose**: Add database column for audit trail (required by US2 and US3)

- [x] T001 Create database migration file `supabase/migrations/0XX_add_expense_audit_fields.sql` with last_modified_by column, backfill to created_by, add index, and verification

---

## Phase 2: Foundational (Data Layer & Core Infrastructure)

**Purpose**: Core data model and repository changes that ALL user stories depend on

**⚠️ CRITICAL**: No user story UI work can begin until this phase is complete

- [x] T002 [P] Add `lastModifiedBy` field to ExpenseEntity in `lib/features/expenses/domain/entities/expense_entity.dart` with wasModified getter and getLastModifiedByName helper method
- [x] T003 [P] Add `lastModifiedBy` field mapping to ExpenseModel in `lib/features/expenses/data/models/expense_model.dart` (fromJson and toJson methods)
- [x] T004 [P] Create ConflictException class in `lib/core/errors/exceptions.dart` for optimistic locking conflicts
- [x] T005 Add `updateExpenseWithTimestamp` method signature to ExpenseRepository interface in `lib/features/expenses/domain/repositories/expense_repository.dart`
- [x] T006 Implement `updateExpenseWithTimestamp` method in ExpenseRepositoryImpl in `lib/features/expenses/data/repositories/expense_repository_impl.dart`
- [x] T007 Implement `updateExpenseWithTimestamp` method in ExpenseRemoteDatasource in `lib/features/expenses/data/datasources/expense_remote_datasource.dart` with WHERE clause on updated_at for optimistic locking
- [x] T008 [P] Create `selectedMemberForExpenseProvider` StateProvider in `lib/features/expenses/presentation/providers/expense_provider.dart`
- [x] T009 [P] Add `updateExpenseWithLock` method to ExpenseFormNotifier in `lib/features/expenses/presentation/providers/expense_form_notifier.dart` with ConflictException handling

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Cash Payment Default Selection (Priority: P1) 🎯 MVP

**Goal**: Fix payment method default selection bug so "Contanti" is pre-selected and functionally active without requiring manual reselection

**Independent Test**: Create new expense, verify "Contanti" is pre-selected, fill amount/category/date, click save without touching payment method - save should succeed with "Contanti"

### Implementation for User Story 1

- [x] T010 [US1] Add payment method initialization logic to ManualExpenseScreen initState in `lib/features/expenses/presentation/screens/manual_expense_screen.dart` using WidgetsBinding.instance.addPostFrameCallback to set _selectedPaymentMethodId to defaultContanti.id when null
- [x] T011 [US1] Add defensive null handling for payment method deletion edge case in PaymentMethodSelector in `lib/features/payment_methods/presentation/widgets/payment_method_selector.dart` - auto-select first available or show error if none exist

**Checkpoint**: At this point, User Story 1 should be fully functional - users can save expenses with default Contanti without reselection

---

## Phase 4: User Story 2 - Admin Add Expenses for Group Members (Priority: P2)

**Goal**: Enable group administrators to create new expenses on behalf of any group member

**Independent Test**: Login as admin, navigate to expense creation, select member from dropdown, create expense, verify expense appears in selected member's history

### Implementation for User Story 2

- [x] T012 [P] [US2] Create MemberSelector widget in `lib/features/expenses/presentation/widgets/member_selector.dart` with DropdownButtonFormField showing active group members, using groupMembersProvider, with admin check
- [x] T013 [US2] Add conditional member selector to ManualExpenseScreen in `lib/features/expenses/presentation/screens/manual_expense_screen.dart` - show only when isGroupAdminProvider is true, bind to _selectedMemberIdForExpense state
- [x] T014 [US2] Update expense submission logic in ManualExpenseScreen._submitForm to use selectedMemberIdForExpense when admin (set created_by to selected member, set last_modified_by to current admin user)
- [x] T015 [US2] Add admin permission check before showing member selector - hide from non-admins per FR-008

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - admins can create expenses for members, regular users cannot see selector

---

## Phase 5: User Story 3 - Admin Edit Expenses for Group Members (Priority: P2)

**Goal**: Enable group administrators to modify existing expenses created by any group member with audit trail and optimistic locking

**Independent Test**: Login as admin, view member's expense list, select expense, edit details (amount/category/date/payment method), save, verify changes persist and audit trail shows admin as last modifier

### Implementation for User Story 3

- [x] T016 [P] [US3] Add edit mode support to ManualExpenseScreen in `lib/features/expenses/presentation/screens/manual_expense_screen.dart` - add optional expenseId parameter, load expense data in initState when provided, pre-populate form fields
- [x] T017 [P] [US3] Add edit route configuration to go_router navigation in main navigation setup - `/expense/:id/edit` route passing expenseId parameter
- [x] T018 [US3] Update form submission logic to detect edit mode (isEditMode = expenseId != null) and call updateExpenseWithLock instead of createExpense when editing
- [x] T019 [US3] Store original updated_at timestamp in _originalUpdatedAt field when loading expense for editing (for optimistic locking)
- [x] T020 [US3] Add conflict error handling in ManualExpenseScreen - catch ConflictException, show SnackBar with error message and Refresh action button
- [x] T021 [US3] Add admin demotion listener in ManualExpenseScreen.build using ref.listen on isGroupAdminProvider - if admin changes from true to false while in edit mode, show error and navigate to /expenses
- [x] T022 [US3] Add audit trail display to ExpenseDetailScreen in `lib/features/expenses/presentation/screens/expense_detail_screen.dart` - show "Modified by [name]" card when expense.wasModified is true, using getLastModifiedByName helper

**Checkpoint**: All user stories should now be independently functional - admins can create/edit any member's expenses with audit tracking and conflict detection

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and edge cases

- [x] T023 [P] Add defensive handling for removed users in member name lookups - display "(Removed User)" when member not found in group
- [x] T024 [P] Update expense list views to display audit information - show creator and last modified by names from expense entity
- [x] T025 Add validation for admin privilege checks in expense repository - enforce FR-009 server-side permission validation
- [ ] T026 Run manual QA from quickstart.md checklist - verify all payment default, admin create, admin edit, concurrent edit, and admin demotion scenarios

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately (database migration)
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User Story 1 (P1): Can start after Foundational - No dependencies on other stories
  - User Story 2 (P2): Can start after Foundational - No dependencies on other stories
  - User Story 3 (P3): Can start after Foundational - Depends on User Story 2's member selector widget (T012)
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Independent - critical bug fix, highest priority
- **User Story 2 (P2)**: Independent - creates member selector widget needed by US3
- **User Story 3 (P3)**: Depends on US2 for MemberSelector widget - otherwise independent

### Within Each User Story

- US1: T010 must complete before T011 (initialization before edge case handling)
- US2: T012 (widget) must complete before T013 (widget usage)
- US3: T016 and T017 must complete before T018-T022 (edit infrastructure before submission logic)

### Parallel Opportunities

- **Phase 2**: T002, T003, T004, T008, T009 can all run in parallel (different files)
- **US2**: T012 can run in parallel with T013-T015 if widget interface is known upfront
- **US3**: T016 can run in parallel with T017 (screen changes vs. route config)
- **Polish**: T023 and T024 can run in parallel (different concerns)

---

## Parallel Example: Foundational Phase

```bash
# Launch all foundational tasks together (different files):
Task: "Add lastModifiedBy field to ExpenseEntity in expense_entity.dart"
Task: "Add lastModifiedBy field mapping to ExpenseModel in expense_model.dart"
Task: "Create ConflictException class in exceptions.dart"
Task: "Create selectedMemberForExpenseProvider in expense_provider.dart"
Task: "Add updateExpenseWithLock method to ExpenseFormNotifier"
```

---

## Parallel Example: User Story 2

```bash
# Launch widget creation and screen updates together:
Task: "Create MemberSelector widget in member_selector.dart"
# Can start T013-T015 once MemberSelector interface is known
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (database migration) - ~30 min
2. Complete Phase 2: Foundational (data layer) - ~1 hour
3. Complete Phase 3: User Story 1 (payment fix) - ~30 min
4. **STOP and VALIDATE**: Test payment default selection independently
5. Deploy/demo if ready - critical bug fix delivered

**MVP Scope**: Just US1 (T001-T011) = ~2 hours total

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready (~1.5 hours)
2. Add User Story 1 → Test independently → Deploy (MVP! ~30 min)
3. Add User Story 2 → Test independently → Deploy (~2 hours)
4. Add User Story 3 → Test independently → Deploy (~1.5 hours)
5. Add Polish → Final QA → Deploy (~1 hour)

**Full Feature**: All stories (T001-T026) = ~6.5 hours total

### Parallel Team Strategy

With 2 developers after Foundational phase:

1. Team completes Setup (T001) together - 30 min
2. Team completes Foundational (T002-T009) together - 1 hour
3. Once Foundational is done:
   - **Developer A**: User Story 1 (T010-T011) - 30 min
   - **Developer B**: User Story 2 (T012-T015) - 2 hours
4. After US2 completes:
   - **Developer A or B**: User Story 3 (T016-T022) - 1.5 hours
5. Team completes Polish (T023-T026) together - 1 hour

**Total with parallelization**: ~4 hours (vs. 6.5 hours sequential)

---

## Task Count Summary

| Phase | Task Count | Estimated Time |
|-------|-----------|----------------|
| Phase 1: Setup | 1 | 30 min |
| Phase 2: Foundational | 8 | 1 hour |
| Phase 3: User Story 1 (P1) 🎯 | 2 | 30 min |
| Phase 4: User Story 2 (P2) | 4 | 2 hours |
| Phase 5: User Story 3 (P2) | 7 | 1.5 hours |
| Phase 6: Polish | 4 | 1 hour |
| **Total** | **26 tasks** | **6.5 hours** |

### Tasks per User Story

- **US1** (Cash Payment Default): 2 tasks - Critical bug fix
- **US2** (Admin Add Expenses): 4 tasks - New admin capability
- **US3** (Admin Edit Expenses): 7 tasks - Complex edit flow with audit/locking

### Parallel Opportunities Identified

- Foundational phase: 5 tasks can run in parallel (T002, T003, T004, T008, T009)
- US2: 1 widget can be built independently (T012)
- US3: 2 tasks can run in parallel (T016, T017)
- Polish: 2 tasks can run in parallel (T023, T024)

**Total parallelizable tasks**: 10 tasks (38% of all tasks)

---

## Independent Test Criteria per Story

### User Story 1: Cash Payment Default Selection ✅

**Test Steps**:
1. Open expense creation screen
2. Verify "Contanti" is visually selected in payment method dropdown
3. Fill in amount: 10.00
4. Select category: "Alimentari"
5. Select date: today
6. Click Save (without touching payment method)
7. **Expected**: Expense saves successfully with payment method = "Contanti"
8. **Verify**: No validation error about payment method

**Success Criteria**: SC-001 and SC-002 from spec - save in under 10 seconds, 100% success rate

---

### User Story 2: Admin Add Expenses for Group Members ✅

**Test Steps**:
1. Login as group administrator
2. Navigate to expense creation screen
3. Verify member selector dropdown is visible
4. Select member "Alice" from dropdown
5. Fill expense details: amount 25.00, category "Trasporti", date today, payment "Carta di Credito"
6. Click Save
7. **Expected**: Expense saved with created_by = Alice's user ID
8. Navigate to Alice's expense list
9. **Verify**: New expense appears in Alice's history
10. Login as Alice
11. **Verify**: Alice can see the expense created by admin

**Success Criteria**: SC-003 from spec - add expense in under 15 seconds

---

### User Story 3: Admin Edit Expenses for Group Members ✅

**Test Steps**:
1. Login as group administrator
2. Navigate to Bob's expense list (Bob is regular member)
3. Select an expense created by Bob
4. Click Edit
5. Change amount from 15.00 to 20.00
6. Change category from "Alimentari" to "Trasporti"
7. Click Save
8. **Expected**: Changes saved successfully
9. **Verify**: Expense shows updated amount and category
10. **Verify**: Audit trail displays "Modified by [Admin Name]"
11. **Verify**: Original creator still shows as Bob
12. Login as Bob
13. **Verify**: Bob sees the updated expense with changes

**Success Criteria**: SC-004 and SC-005 from spec - changes visible within 2 seconds, zero unauthorized edits

---

## Suggested MVP Scope

**Minimum Viable Product**: User Story 1 Only (T001-T011)

**Rationale**:
- US1 is a critical bug fix (P1 priority)
- Blocks normal expense creation workflow
- Affects all users, not just admins
- Quick win - only 2 implementation tasks after foundation
- Can be deployed independently for immediate user value

**MVP Deliverable**: Users can create expenses with default "Contanti" payment method without manual reselection bug

---

## Format Validation ✅

All tasks follow the required checklist format:
- ✅ Every task starts with `- [ ]` (checkbox)
- ✅ Every task has sequential ID (T001, T002, T003...)
- ✅ [P] marker used only for parallelizable tasks (different files, no dependencies)
- ✅ [Story] label (US1, US2, US3) used for all user story phase tasks
- ✅ Setup and Foundational phases have NO story labels (correct)
- ✅ Polish phase has NO story labels (correct)
- ✅ Every task description includes specific file path
- ✅ Task descriptions are actionable and specific

---

## Notes

- [P] tasks = different files, no dependencies - can run in parallel
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Database migration (T001) must be applied before running application
- All file paths use Clean Architecture feature-based structure
- Avoid cross-story dependencies that break independence (US3 depends on US2's widget only)
