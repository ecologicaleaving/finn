# Tasks: Recurring Expenses and Reimbursements Management

**Input**: Design documents from `/specs/013-recurring-expenses/`
**Prerequisites**: plan.md, spec.md, data-model.md, contracts/recurring_expenses_api.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [x] T001 [P] Create recurrence frequency enum in lib/core/enums/recurrence_frequency.dart
- [x] T002 [P] Create recurring expenses Drift table in lib/core/database/tables/recurring_expenses_table.dart
- [x] T003 [P] Create recurring expense instances Drift table in lib/core/database/tables/recurring_expense_instances_table.dart
- [x] T004 Add recurring expense tables to Drift database configuration in lib/core/database/drift_database.dart

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T005 Implement Drift database migration (schema version 4) to add recurring_expenses and recurring_expense_instances tables in lib/core/database/drift_database.dart
- [x] T006 Add recurringExpenseId and isRecurringInstance fields to OfflineExpenses table in lib/features/offline/data/local/offline_database.dart
- [x] T007 [P] Create Supabase migration file at supabase/migrations/20260116_001_create_recurring_expenses.sql with tables, indexes, RLS policies, and triggers
- [x] T008 [P] Create RecurringExpense domain entity in lib/features/expenses/domain/entities/recurring_expense.dart
- [x] T009 [P] Create RecurringExpenseEntity data model in lib/features/expenses/data/models/recurring_expense_entity.dart with fromDrift, toCompanion, fromJson, toJson methods
- [x] T010 [P] Create RecurringExpenseRepository interface in lib/features/expenses/domain/repositories/recurring_expense_repository.dart with all methods (create, update, pause, resume, delete, get, getAll, generateInstance, getInstances)
- [x] T011 [P] Create RecurringExpenseLocalDataSource in lib/features/expenses/data/datasources/recurring_expense_local_datasource.dart for Drift operations
- [x] T012 [P] Create recurring_expenses_dao.dart data access object in lib/core/database/daos/recurring_expenses_dao.dart
- [x] T013 Implement RecurringExpenseRepositoryImpl in lib/features/expenses/data/repositories/recurring_expense_repository_impl.dart with all repository methods
- [x] T014 [P] Create RecurrenceCalculator domain service in lib/features/expenses/domain/services/recurrence_calculator.dart with calculateNextDueDate and calculateBudgetReservation methods
- [x] T015 [P] Create RecurringExpenseScheduler service in lib/core/services/recurring_expense_scheduler.dart with registerPeriodicCheck and cancelPeriodicCheck methods
- [x] T016 Register background task for recurring expense instance generation in lib/app/background_tasks.dart
- [x] T017 Implement background task callback to check for due recurring expenses and generate instances in lib/app/background_tasks.dart

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 (P1) - Mark Expenses as Recurring

**Goal**: Users can mark expenses as recurring with frequency configuration and automatic instance generation

**Independent Test**: Create a new expense, mark it as recurring, set frequency (daily/weekly/monthly/yearly), save it, and verify the expense is saved with recurring configuration. Background task generates instances automatically when due.

### Implementation for User Story 1

- [x] T018 [P] [US1] SKIPPED - Project uses Riverpod providers directly without use case layer
- [x] T019 [P] [US1] SKIPPED - Project uses Riverpod providers directly without use case layer
- [x] T020 [P] [US1] SKIPPED - Project uses Riverpod providers directly without use case layer
- [x] T021 [P] [US1] SKIPPED - Project uses Riverpod providers directly without use case layer
- [x] T022 [P] [US1] SKIPPED - Project uses Riverpod providers directly without use case layer
- [x] T023 [P] [US1] Create recurringExpenseProvider in lib/features/expenses/presentation/providers/recurring_expense_provider.dart (single expense by ID)
- [x] T024 [P] [US1] Create recurringExpenseListProvider in lib/features/expenses/presentation/providers/recurring_expense_provider.dart (all recurring expenses)
- [x] T025 [US1] Add recurring expense fields to ExpenseFormScreen in lib/features/expenses/presentation/screens/expense_form_screen.dart (toggle, frequency selector, budget reservation checkbox)
- [x] T026 [US1] Implement recurring expense creation logic in ExpenseFormScreen when user marks expense as recurring in lib/features/expenses/presentation/screens/expense_form_screen.dart
- [x] T027 [US1] Implement recurring expense editing logic in ExpenseFormScreen for existing recurring expenses in lib/features/expenses/presentation/screens/expense_form_screen.dart
- [x] T028 [US1] Add recurring indicator badge to expense list items when expense is a recurring template or instance in lib/features/expenses/presentation/widgets/expense_list_item.dart
- [x] T029 [US1] Display recurring expense details (frequency, next due date, budget reservation status) in expense detail view in lib/features/expenses/presentation/screens/expense_detail_screen.dart
- [x] T030 [US1] Implement Supabase Realtime subscription for recurring_expenses table in lib/features/expenses/data/datasources/recurring_expense_remote_datasource.dart
- [x] T031 [US1] Implement sync queue integration for recurring expense create/update/delete operations in lib/features/expenses/data/repositories/recurring_expense_repository_impl.dart

**Checkpoint**: At this point, User Story 1 should be fully functional - users can mark expenses as recurring, set frequency, and background tasks generate instances automatically

---

## Phase 4: User Story 2 (P2) - Budget Reservation for Recurring Expenses

**Goal**: Users can reserve budget for recurring expenses to see available budget after accounting for known future commitments

**Independent Test**: Create recurring expenses with budget reservation enabled, verify budget overview shows total budget and available budget after reservations, and verify calculations adjust when reservations are added/removed.

### Implementation for User Story 2

- [x] T032 [P] [US2] Create BudgetReservationCalculator service in lib/core/services/budget_reservation_calculator.dart with calculateReservedBudget and calculateAvailableBudget methods
- [x] T033 [P] [US2] Extend BudgetCalculator utility in lib/core/utils/budget_calculator.dart with calculateReservedBudget, calculateAvailableBudget, and getBudgetBreakdown methods
- [x] T034 [P] [US2] Create currentMonthReservedBudgetProvider in lib/features/budgets/presentation/providers/budget_reservation_provider.dart
- [x] T035 [US2] Update budget overview widget to display reserved budget amount in lib/features/budgets/presentation/widgets/budget_overview_card.dart
- [x] T036 [US2] Update budget overview widget to display available budget (total - spent - reserved + reimbursed) in lib/features/budgets/presentation/widgets/budget_overview_card.dart
- [x] T037 [US2] Create BudgetReservationDisplay widget in lib/features/expenses/presentation/widgets/budget_reservation_display.dart to show reservation breakdown
- [x] T038 [US2] Add budget reservation breakdown section to budget screen in lib/features/budgets/presentation/screens/budget_screen.dart
- [x] T039 [US2] Implement budget reservation toggle in expense form for recurring expenses in lib/features/expenses/presentation/screens/expense_form_screen.dart
- [x] T040 [US2] Add provider invalidation for budgetReservationProvider when recurring expenses change in lib/features/expenses/presentation/providers/recurring_expense_provider.dart

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently - budget reservations calculate correctly and display in budget overview

---

## Phase 5: User Story 3 (P3) - Recurring Expenses Management Screen

**Goal**: Users can access a dedicated screen in Settings to view and manage all recurring expenses in one place

**Independent Test**: Navigate to Settings > Recurring Expenses, verify all recurring expenses are listed with frequency/amount/category, and verify users can view details, pause/resume, edit, and delete recurring expenses from this screen.

### Implementation for User Story 3

- [x] T041 [P] [US3] Create RecurringExpensesScreen in lib/features/expenses/presentation/screens/recurring_expenses_screen.dart with list of all recurring expenses
- [x] T042 [P] [US3] Create RecurringExpenseCard widget in lib/features/expenses/presentation/widgets/recurring_expense_card.dart to display individual recurring expense with frequency, amount, category, and status
- [x] T043 [US3] Implement pause/resume actions in RecurringExpenseCard widget in lib/features/expenses/presentation/widgets/recurring_expense_card.dart
- [x] T044 [US3] Implement delete action with confirmation dialog (future only vs all occurrences) in RecurringExpenseCard widget in lib/features/expenses/presentation/widgets/recurring_expense_card.dart
- [x] T045 [US3] Add filtering options (active/paused, with/without budget reservation) to RecurringExpensesScreen in lib/features/expenses/presentation/screens/recurring_expenses_screen.dart
- [x] T046 [US3] Add "Recurring Expenses" menu item to Settings screen in lib/features/settings/presentation/screens/settings_screen.dart
- [x] T047 [US3] Implement navigation from Settings to RecurringExpensesScreen in lib/features/settings/presentation/screens/settings_screen.dart
- [x] T048 [US3] Add empty state UI when no recurring expenses exist in lib/features/expenses/presentation/screens/recurring_expenses_screen.dart
- [x] T049 [US3] Implement pull-to-refresh for recurring expenses list in lib/features/expenses/presentation/screens/recurring_expenses_screen.dart

**Checkpoint**: All user stories 1, 2, and 3 should now be independently functional - users can manage all recurring expenses from Settings

---

## Phase 6: User Story 4 (P3) - Reimbursements Management Screen

**Goal**: Users can access a dedicated screen in Settings to view and manage all expenses marked as reimbursable or reimbursed

**Independent Test**: Navigate to Settings > Reimbursements, verify all expenses with reimbursement status are displayed, verify filtering by status (reimbursable vs reimbursed), verify summary totals, and verify users can mark reimbursable expenses as reimbursed.

### Implementation for User Story 4

- [x] T050 [P] [US4] Create ReimbursementsScreen in lib/features/expenses/presentation/screens/reimbursements_screen.dart with list of all reimbursable/reimbursed expenses
- [x] T051 [P] [US4] Create reimbursementsListProvider in lib/features/expenses/presentation/providers/reimbursements_provider.dart to fetch expenses with reimbursement status
- [x] T052 [US4] Implement filtering/grouping by reimbursement status (reimbursable vs reimbursed) in lib/features/expenses/presentation/screens/reimbursements_screen.dart
- [x] T053 [US4] Add summary section showing total pending reimbursements and total reimbursed amounts in lib/features/expenses/presentation/screens/reimbursements_screen.dart
- [x] T054 [US4] Implement quick action to mark reimbursable expense as reimbursed from list in lib/features/expenses/presentation/screens/reimbursements_screen.dart
- [x] T055 [US4] Add search and filter capabilities to find specific reimbursements in lib/features/expenses/presentation/screens/reimbursements_screen.dart
- [x] T056 [US4] Add "Reimbursements" menu item to Settings screen in lib/features/settings/presentation/screens/settings_screen.dart
- [x] T057 [US4] Implement navigation from Settings to ReimbursementsScreen in lib/features/settings/presentation/screens/settings_screen.dart
- [x] T058 [US4] Add empty state UI when no reimbursements exist in lib/features/expenses/presentation/screens/reimbursements_screen.dart
- [x] T059 [US4] Implement pull-to-refresh for reimbursements list in lib/features/expenses/presentation/screens/reimbursements_screen.dart

**Checkpoint**: All user stories should now be independently functional - complete recurring expenses and reimbursements management

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and final validation

- [x] T060 [P] Add error handling and user feedback (snackbars/dialogs) for recurring expense operations across all screens (already implemented in provider)
- [x] T061 [P] Add loading states and shimmer effects for async operations in recurring expense screens (already implemented with LoadingIndicator)
- [x] T062 [P] Implement optimistic UI updates for recurring expense create/update/delete operations (already implemented in provider)
- [ ] T063 [P] Add analytics tracking for recurring expense feature usage (create, pause, resume, delete, budget reservation toggle) - SKIPPED (requires analytics service setup)
- [x] T064 Add timezone handling validation for recurring expense calculations in lib/features/expenses/domain/services/recurrence_calculator.dart (already implemented with timezone package)
- [x] T065 Implement edge case handling for month-end recurring expenses (31st → Feb 28/29) in lib/features/expenses/domain/services/recurrence_calculator.dart (already implemented with _addMonths/_addYears helpers)
- [x] T066 Add validation to prevent category deletion if used by recurring expenses in lib/features/categories/data/repositories/category_repository_impl.dart
- [ ] T067 [P] Add unit tests for RecurrenceCalculator in test/features/expenses/domain/services/recurrence_calculator_test.dart - DEFERRED (testing infrastructure)
- [ ] T068 [P] Add unit tests for BudgetReservationCalculator in test/core/services/budget_reservation_calculator_test.dart - DEFERRED (testing infrastructure)
- [ ] T069 [P] Add unit tests for RecurringExpenseRepository in test/features/expenses/data/repositories/recurring_expense_repository_test.dart - DEFERRED (testing infrastructure)
- [ ] T070 [P] Add widget tests for RecurringExpensesScreen in test/features/expenses/presentation/screens/recurring_expenses_screen_test.dart - DEFERRED (testing infrastructure)
- [ ] T071 [P] Add widget tests for ReimbursementsScreen in test/features/expenses/presentation/screens/reimbursements_screen_test.dart - DEFERRED (testing infrastructure)
- [ ] T072 Add integration test for complete recurring expense lifecycle (create → pause → resume → delete) in test/integration/recurring_expense_flow_test.dart - DEFERRED (testing infrastructure)
- [ ] T073 Add integration test for background task expense instance generation in test/integration/recurring_expense_scheduler_test.dart - DEFERRED (testing infrastructure)
- [ ] T074 Verify Supabase migration runs successfully on staging environment - DEFERRED (requires deployment)
- [ ] T075 Run data integrity checks on recurring_expenses and recurring_expense_instances tables - DEFERRED (requires deployment)
- [ ] T076 Performance test: Verify background task executes within 100ms for 50 active templates - DEFERRED (requires deployment)
- [ ] T077 Performance test: Verify budget reservation calculation completes within 50ms for 20 active reservations - DEFERRED (requires deployment)
- [ ] T078 Test offline functionality: Verify recurring expense instances are created locally when offline and synced when online - DEFERRED (requires deployment)
- [x] T079 Update feature documentation in docs/features/recurring-expenses.md (if docs folder exists) - SKIPPED (no docs folder)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Integrates with US1 but independently testable (works with existing expenses if recurring expenses don't exist)
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Provides management UI for US1 but independently testable
- **User Story 4 (P3)**: Can start after Foundational (Phase 2) - Uses existing reimbursement functionality from Feature 012, completely independent of US1-3

### Within Each User Story

#### User Story 1 (P1)
- T018-T022 (use cases) can run in parallel [P]
- T023-T024 (providers) can run in parallel [P]
- T025-T027 (form screen modifications) must run sequentially (same file)
- T028-T029 can run in parallel [P] (different files)
- T030-T031 can run in parallel [P] (different files)

#### User Story 2 (P2)
- T032-T034 can run in parallel [P] (different files)
- T035-T037 can run in parallel [P] (different files)
- T038-T040 must run sequentially (depend on previous tasks)

#### User Story 3 (P3)
- T041-T042 can run in parallel [P] (different files)
- T043-T045 must run sequentially (modify same file - recurring_expense_card.dart and recurring_expenses_screen.dart)
- T046-T047 must run sequentially (same file - settings_screen.dart)
- T048-T049 must run sequentially (same file - recurring_expenses_screen.dart)

#### User Story 4 (P3)
- T050-T051 can run in parallel [P] (different files)
- T052-T055 must run sequentially (modify same file - reimbursements_screen.dart)
- T056-T057 must run sequentially (same file - settings_screen.dart)
- T058-T059 must run sequentially (same file - reimbursements_screen.dart)

### Parallel Opportunities

**Phase 1 (Setup)**: All tasks can run in parallel
- T001, T002, T003 in parallel → T004 (depends on all)

**Phase 2 (Foundational)**: Many tasks can run in parallel
- T005-T006 (database migrations) can run in parallel with T007 (Supabase migration)
- T008-T009 (domain entities) can run in parallel
- T010 (repository interface) → then T011-T012 in parallel → then T013
- T014-T015 can run in parallel

**Phase 3 (US1)**: Use cases, providers, and different screen modifications can run in parallel
- Launch T018-T022 together (all use cases)
- Launch T023-T024 together (providers)
- Launch T028-T031 together (different files)

**Phase 4 (US2)**: Services, providers, and widgets can run in parallel
- Launch T032-T034 together
- Launch T035-T037 together

**Phase 5 (US3)**: Screen and widget creation can run in parallel
- Launch T041-T042 together

**Phase 6 (US4)**: Screen and provider creation can run in parallel
- Launch T050-T051 together

**Phase 7 (Polish)**: Most tests and validations can run in parallel
- Launch T060-T063, T067-T071 together (all independent tests and improvements)

---

## Parallel Example: User Story 1

```bash
# Launch all use cases for User Story 1 together:
Task: T018 "Create CreateRecurringExpense use case"
Task: T019 "Create UpdateRecurringExpense use case"
Task: T020 "Create PauseRecurringExpense use case"
Task: T021 "Create ResumeRecurringExpense use case"
Task: T022 "Create GenerateExpenseInstance use case"

# Then launch providers in parallel:
Task: T023 "Create recurringExpenseProvider (single)"
Task: T024 "Create recurringExpenseListProvider (all)"

# Then launch independent widget/screen updates:
Task: T028 "Add recurring indicator to expense list items"
Task: T029 "Display recurring details in expense detail view"
Task: T030 "Implement Supabase Realtime subscription"
Task: T031 "Implement sync queue integration"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T004)
2. Complete Phase 2: Foundational (T005-T017) - CRITICAL
3. Complete Phase 3: User Story 1 (T018-T031)
4. **STOP and VALIDATE**: Test User Story 1 independently
   - Create recurring expense with different frequencies
   - Verify background task generates instances
   - Verify instances are created correctly
   - Test pause/resume functionality
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 (P1) → Test independently → Deploy/Demo (MVP: Recurring expenses work!)
3. Add User Story 2 (P2) → Test independently → Deploy/Demo (Budget reservations work!)
4. Add User Story 3 (P3) → Test independently → Deploy/Demo (Management screen works!)
5. Add User Story 4 (P3) → Test independently → Deploy/Demo (Reimbursements screen works!)
6. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (critical path)
2. Once Foundational is done:
   - **Developer A**: User Story 1 (P1) - Core recurring expense functionality
   - **Developer B**: User Story 4 (P3) - Reimbursements screen (completely independent)
   - **Developer C**: Can start User Story 2 (P2) after Developer A completes foundational providers
3. After US1 is complete:
   - **Developer A**: User Story 3 (P3) - Recurring expenses management screen
   - **Developer B**: Continue User Story 4 or help with Polish
4. Stories complete and integrate independently

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Background task runs every 15 minutes - test by advancing device time in debug mode
- Budget reservation calculations use cents for precision
- All recurring expense dates use user's local timezone
- Supabase RLS policies ensure multi-tenant isolation
- Offline-first: recurring expense instances created locally, synced when online
