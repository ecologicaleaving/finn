# Implementation Tasks: Custom Category Icons

**Feature**: `014-category-icons`
**Branch**: `014-category-icons`
**Status**: Ready for Implementation
**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

## Task Summary

**Total Tasks**: 42
- Phase 1 (Setup): 2 tasks
- Phase 2 (Foundational): 6 tasks
- Phase 3 (US1 - Display Icons): 10 tasks
- Phase 4 (US2 - Icon Picker): 11 tasks
- Phase 5 (US3 - Smart Defaults): 8 tasks
- Phase 6 (Polish): 5 tasks

**Parallel Opportunities**: 15 tasks marked [P] can run in parallel
**MVP Scope**: Phases 1-3 (Setup + Foundational + US1) = 18 tasks

---

## Phase 1: Setup (2 tasks)

**Purpose**: Add dependencies and configure build scripts

- [X] T001 [P] Add flutter_iconpicker dependency to pubspec.yaml (version ^3.2.4)
- [X] T002 [P] Update build scripts with --no-tree-shake-icons flag in build_and_install.ps1 and build_dev.sh

---

## Phase 2: Foundational (6 tasks) ⚠️ BLOCKS ALL USER STORIES

**Purpose**: Core infrastructure MUST be complete before ANY user story implementation

### Database Migrations

- [X] T003 Create migration 20260205_001_add_icon_name_to_categories.sql - Add nullable icon_name VARCHAR(100) column with index in supabase/migrations/
- [X] T004 Create migration 20260205_002_backfill_category_icons.sql - Backfill existing categories using Italian keyword matching in supabase/migrations/
- [X] T005 [OPTIONAL] Create migration 20260205_003_make_icon_name_not_null.sql - Make icon_name NOT NULL with DEFAULT 'category' (deploy only after verification) in supabase/migrations/

### Core Services

- [X] T006 [P] Create IconHelper service with getIconFromName(), getNameFromIcon(), isValidIconName() methods in lib/core/services/icon_helper.dart
- [X] T007 [P] Create IconMatchingService with getDefaultIconNameForCategory() and italianToEnglishIconKeywords map in lib/core/services/icon_matching_service.dart (extract logic from CategoryDropdown._getCategoryIcon lines 260-295)
- [X] T008 [P] Update pubspec.yaml assets section if needed for icon picker resources

**Checkpoint**: Foundation ready - user story implementation can now begin

---

## Phase 3: User Story 1 (P1) - View Categories with Visual Icons 🎯 MVP

**Goal**: Display visual icons alongside category names throughout the app

**Independent Test**: View expense list, category selector, and dashboard - verify each category shows its assigned icon

### Entity & Model Updates

- [X] T009 [P] [US1] Add iconName field to ExpenseCategoryEntity with getIcon() helper method in lib/features/categories/domain/entities/expense_category_entity.dart
- [X] T010 [P] [US1] Update ExpenseCategoryModel JSON serialization for icon_name in lib/features/categories/data/models/expense_category_model.dart

### Data Layer

- [X] T011 [US1] Verify CategoryRemoteDataSource includes icon_name in queries in lib/features/categories/data/datasources/category_remote_datasource.dart

### UI Updates - Category Display

- [X] T012 [P] [US1] Update CategorySelector _CategoryChip to display icon from category.iconName in lib/features/expenses/presentation/widgets/category_selector.dart (lines 94-140)
- [X] T013 [P] [US1] Update CategoryDropdown to use stored icon_name, replace _getCategoryIcon() with IconHelper in lib/features/expenses/presentation/widgets/category_selector.dart (lines 260-295)
- [X] T014 [P] [US1] Update _CategoryCard to display icons from iconName field in lib/features/expenses/presentation/widgets/category_selector.dart (lines 324-330)
- [X] T015 [P] [US1] Update expense list items to show category icons (find all expense list widgets)
- [X] T016 [P] [US1] Update dashboard category chips to show icons (find dashboard widgets)
- [X] T017 [P] [US1] Update budget screens to show category icons (find budget widgets)
- [ ] T018 [US1] Manual verification: Test icon display across all screens (expense list, category selector, dashboard, budgets)

**Checkpoint**: User Story 1 complete - icons display throughout app

---

## Phase 4: User Story 2 (P2) - Select Icons for Custom Categories

**Goal**: Users can choose icons from a comprehensive library when creating/editing categories

**Independent Test**: Create new category, select icon from picker, verify icon appears correctly in all contexts

### Repository & Data Layer

- [X] T019 [US2] Add updateCategoryIcon() method to CategoryRepository interface in lib/features/categories/domain/repositories/category_repository.dart
- [X] T020 [US2] Add optional iconName parameter to CategoryRepository.createCategory() in lib/features/categories/domain/repositories/category_repository.dart
- [X] T021 [US2] Implement updateCategoryIcon() in CategoryRepositoryImpl with validation in lib/features/categories/data/repositories/category_repository_impl.dart
- [X] T022 [US2] Update CategoryRepositoryImpl.createCategory() to accept iconName in lib/features/categories/data/repositories/category_repository_impl.dart
- [X] T023 [US2] Update CategoryRemoteDataSource interface with icon support in lib/features/categories/data/datasources/category_remote_datasource.dart
- [X] T024 [US2] Implement icon support in CategoryRemoteDataSourceImpl (update INSERT/UPDATE queries) in lib/features/categories/data/datasources/category_remote_datasource.dart

### Provider Layer

- [X] T025 [US2] Add updateCategoryIcon() action to CategoryActions in lib/features/categories/presentation/providers/category_actions_provider.dart
- [X] T026 [US2] Update CategoryActions.createCategory() to accept iconName in lib/features/categories/presentation/providers/category_actions_provider.dart

### UI - Icon Picker Widget

- [X] T027 [US2] Create BilingualIconPicker widget with flutter_iconpicker integration and Italian search in lib/shared/widgets/bilingual_icon_picker.dart
- [X] T028 [US2] Add icon picker to CategoryFormDialog with preview and submit handling in lib/features/categories/presentation/widgets/category_form_dialog.dart
- [ ] T029 [US2] Manual verification: Test icon picker UI and persistence (create category, edit icon, verify updates)

**Checkpoint**: User Story 2 complete - icon picker functional

---

## Phase 5: User Story 3 (P3) - Smart Default Icons

**Goal**: System automatically suggests appropriate icons based on category name analysis

**Independent Test**: Create categories with Italian names ("Spesa", "Benzina") and verify system pre-selects contextually relevant icons

### Smart Icon Selection

- [X] T030 [US3] Add getDefaultIconForCategoryName() to IconMatchingService in lib/core/services/icon_matching_service.dart
- [X] T031 [US3] Pre-select smart default icon in CategoryFormDialog (create mode) with real-time preview in lib/features/categories/presentation/widgets/category_form_dialog.dart
- [X] T032 [US3] Add name-based icon suggestion when picker opens in lib/shared/widgets/bilingual_icon_picker.dart
- [X] T033 [US3] Update CategoryActions.createCategory() to auto-set icon if not provided in lib/features/categories/presentation/providers/category_actions_provider.dart
- [ ] T034 [US3] Manual verification: Test smart icon suggestions for Italian category names ("Spesa", "Benzina", "Ristorante")
- [ ] T035 [US3] Manual verification: Test fallback to generic icon for unrecognized names
- [ ] T036 [US3] Manual verification: Run migration 20260205_002 and verify icon_name populated correctly
- [ ] T037 [US3] Manual verification: Test icon preview updates in real-time as user types category name

**Checkpoint**: User Story 3 complete - smart defaults working

---

## Phase 6: Polish & Documentation (5 tasks)

**Purpose**: Documentation and final verification

- [X] T038 [P] Update README.md with icon feature documentation (--no-tree-shake-icons requirement)
- [X] T039 [P] Add inline code comments for IconHelper and IconMatchingService
- [X] T040 [P] Update quickstart.md with migration steps in specs/014-category-icons/quickstart.md
- [ ] T041 Full end-to-end testing on physical device (install with --no-tree-shake-icons, test all features)
- [ ] T042 Cross-device testing for Realtime sync (edit icon on Device A, verify updates on Device B)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies - start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 - **BLOCKS all user stories**
- **Phase 3 (US1)**: Depends on Phase 2 completion
- **Phase 4 (US2)**: Depends on Phase 3 completion (needs entity/model changes)
- **Phase 5 (US3)**: Depends on Phase 4 completion (needs icon picker)
- **Phase 6 (Polish)**: Depends on all desired user stories

### User Story Dependencies

- **US1 (P1)**: Independent - can start after Phase 2
- **US2 (P2)**: Depends on US1 (needs entity/model with iconName)
- **US3 (P3)**: Depends on US2 (needs icon picker for suggestions)

### Within Each Phase

- Tasks marked [P] can run in parallel (different files, no dependencies)
- Entity before model, model before UI
- Core implementation before manual verification

### Parallel Opportunities

**Phase 1**: Both tasks can run in parallel

**Phase 2**:
- T006, T007, T008 can run in parallel (different files)
- T003, T004, T005 must run sequentially (database migrations)

**Phase 3**:
- T009, T010 can run in parallel
- T012, T013, T014, T015, T016, T017 can run in parallel after T009/T010

**Phase 6**:
- T038, T039, T040 can run in parallel

---

## Parallel Example: Phase 3 (US1)

```bash
# After Phase 2 completes, launch these in parallel:
Task T009: Add iconName to ExpenseCategoryEntity
Task T010: Update ExpenseCategoryModel JSON

# After T009/T010 complete, launch these in parallel:
Task T012: Update CategorySelector chips
Task T013: Update CategoryDropdown
Task T014: Update CategoryCard
Task T015: Update expense list items
Task T016: Update dashboard chips
Task T017: Update budget screens
```

---

## Implementation Strategy

### MVP First (Recommended)

1. ✅ Complete Phase 1: Setup (2 tasks)
2. ✅ Complete Phase 2: Foundational (6 tasks) - CRITICAL
3. ✅ Complete Phase 3: User Story 1 (10 tasks)
4. **STOP and VALIDATE**: Test icon display independently
5. If satisfactory, deploy Phase 1+2 migrations and US1 code

**MVP Deliverable**: Categories display with icons throughout the app

### Incremental Delivery

1. Phases 1-3 (MVP) → Test → Deploy
2. Add Phase 4 (US2) → Test icon picker → Deploy
3. Add Phase 5 (US3) → Test smart defaults → Deploy
4. Add Phase 6 (Polish) → Final verification → Deploy

Each phase adds value without breaking previous functionality.

---

## Critical Implementation Notes

### Build Flag (CRITICAL)

**ALL builds MUST include**: `--no-tree-shake-icons`

```bash
# Development
flutter run --flavor dev --no-tree-shake-icons

# Production
flutter build apk --flavor prod --no-tree-shake-icons
```

**Update**: build_and_install.ps1, build_dev.sh

### Migration Sequence

**DO NOT skip** - run in order:
1. Phase 1: Add nullable column (safe)
2. Phase 2: Backfill (safe)
3. Phase 3: NOT NULL (optional, after verification)

### Icon Naming Convention

- ✅ Correct: `'shopping_cart'`, `'local_gas_station'`, `'restaurant'`
- ❌ Wrong: `'shopping-cart'`, `'shoppingCart'`, `'SHOPPING_CART'`

### Reactive Updates

**No changes needed** - Existing `CategoryNotifier` with Supabase Realtime handles immediate icon updates automatically.

---

## Notes

- **[P]**: Parallelizable tasks (different files, no dependencies)
- **[US1/US2/US3]**: User story label for traceability
- **Verification Tasks**: Manual testing tasks for acceptance criteria
- **No Test Code**: Tests not requested in spec - excluded per instructions
- Each user story should be independently testable
- Commit after completing each logical group of tasks
