# Tasks: Widget Functionality Fix and Category Selector Enhancement

**Input**: Design documents from `/specs/001-widget-category-fixes/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

Flutter mobile app structure:
- **Flutter code**: `lib/features/`, `lib/core/`, `lib/shared/`
- **Android native**: `android/app/src/main/kotlin/`, `android/app/src/main/res/`
- **iOS native**: `ios/Runner/`, `ios/WidgetExtension/`
- **Database**: Supabase migrations, Drift tables

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: iOS App Groups configuration and database migration for MRU tracking

- [X] T001 [P] Configure iOS App Groups in Xcode for widget data sharing (group.com.ecologicaleaving.fin) in ios/Runner.xcodeproj and ios/WidgetExtension
- [X] T002 [P] Create Supabase migration 065_enhance_user_category_usage_for_mru.sql to add last_used_at and use_count columns
- [X] T003 [P] Create composite index on user_category_usage (user_id, last_used_at DESC NULLS LAST) in migration 065
- [X] T004 Create PostgreSQL upsert_category_usage function in migration 065 for atomic usage tracking

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core data layer and services that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T005 [P] Update WidgetDataEntity in lib/features/widget/domain/entities/widget_data_entity.dart to use totalAmount and expenseCount fields instead of spent/limit
- [X] T006 [P] Extend CategoryEntity in lib/features/categories/domain/entities/category_entity.dart with lastUsedAt and useCount fields
- [X] T007 [P] Create CategoryUsageDao in lib/core/database/daos/category_usage_dao.dart with MRU query methods
- [X] T008 [P] Create Drift table definition in lib/core/database/drift/tables/category_usage.dart for local offline support
- [X] T009 Update WidgetRepository interface in lib/features/widget/domain/repositories/widget_repository.dart with new data format methods
- [X] T010 Implement WidgetRepositoryImpl in lib/features/widget/data/repositories/widget_repository_impl.dart to calculate total+count from expenses
- [X] T011 Update widget local datasource in lib/features/widget/data/datasources/widget_local_datasource.dart to cache new data format

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Widget Display of Personal Expenses (Priority: P1) 🎯 MVP

**Goal**: Display user's monthly expense total and count on home screen widget with real-time updates and error handling

**Independent Test**: Add widget to home screen, verify it shows current month expenses as "€342,50 • 12 spese", add expense in app, verify widget updates within 2 seconds

### Implementation for User Story 1

#### Data Layer
- [X] T012 [P] [US1] Create WidgetRemoteDataSource in lib/features/widget/data/datasources/widget_remote_datasource.dart for Supabase Realtime subscription
- [X] T013 [P] [US1] Update WidgetProvider in lib/features/widget/presentation/providers/widget_provider.dart to handle real-time push updates
- [X] T014 [US1] Modify WidgetUpdateService in lib/features/widget/presentation/services/widget_update_service.dart to trigger updates on Supabase events

#### Android Widget UI
- [X] T015 [P] [US1] Update Android widget layout XML in android/app/src/main/res/layout/widget_layout.xml with new design (total+count display, theme colors)
- [X] T016 [P] [US1] Create Android drawable resources for widget background in android/app/src/main/res/drawable/widget_background.xml using cream (#FFFBF5) color
- [X] T017 [P] [US1] Create Android drawable for error indicator icon in android/app/src/main/res/drawable/ic_error_indicator.xml (warning triangle)
- [X] T018 [US1] Update BudgetWidgetProvider.kt in android/app/src/main/kotlin/com/ecologicaleaving/fin/widget/BudgetWidgetProvider.kt to render total+count with deepForest text color

#### iOS Widget UI
- [X] T019 [P] [US1] Update iOS WidgetView.swift in ios/WidgetExtension/WidgetView.swift to display total+count in SwiftUI with theme colors
- [X] T020 [P] [US1] Update iOS WidgetProvider.swift in ios/WidgetExtension/WidgetProvider.swift to load new data format from UserDefaults with App Groups
- [X] T021 [US1] Add error indicator (SF Symbol exclamationmark.triangle.fill) to iOS widget view with conditional rendering

#### Real-time Updates & Error Handling
- [ ] T022 [US1] Implement Supabase Realtime subscription in WidgetRemoteDataSource to listen for expense INSERT/UPDATE/DELETE events filtered by user
- [ ] T023 [US1] Add app lifecycle listener in lib/app/app.dart to subscribe/unsubscribe from Realtime based on foreground/background state
- [ ] T024 [US1] Implement error state handling in WidgetProvider to show cached data with error indicator when refresh fails
- [ ] T025 [US1] Add staleness detection logic to mark widget data as outdated after 24 hours
- [ ] T026 [US1] Configure WorkManager periodic task in lib/app/background_tasks.dart for fallback 15-minute widget refresh

#### Integration & Testing
- [ ] T027 [US1] Test widget displays correct total+count when expense added/modified/deleted
- [ ] T028 [US1] Test widget shows error indicator when network fails but displays cached data
- [ ] T029 [US1] Test widget updates within 2 seconds when expense changes (foreground)
- [ ] T030 [US1] Verify widget applies Flourishing Finances theme colors correctly on both platforms

**Checkpoint**: Widget display should be fully functional with real-time updates, error handling, and correct visual design

---

## Phase 4: User Story 2 - Quick Expense Entry from Widget (Priority: P2)

**Goal**: Add "Scansiona scontrino" and "Inserimento manuale" buttons to widget that deep link to camera and manual entry screens

**Independent Test**: Tap "Scansiona" button on widget, verify camera opens; tap "Manuale" button, verify manual entry screen opens; complete expense via either method, verify widget updates

### Implementation for User Story 2

#### Deep Link Setup
- [ ] T031 [P] [US2] Verify Android intent filter for finapp:// scheme exists in android/app/src/main/AndroidManifest.xml (already configured per research)
- [ ] T032 [P] [US2] Verify iOS URL scheme for finapp exists in ios/Runner/Info.plist (already configured per research)
- [ ] T033 [US2] Update DeepLinkHandler in lib/features/widget/presentation/services/deep_link_handler.dart to handle finapp://scan-receipt and finapp://add-expense routes

#### Android Widget Buttons
- [ ] T034 [P] [US2] Create Android drawable for scan button in android/app/src/main/res/drawable/widget_button_scan.xml with sageGreen background
- [ ] T035 [P] [US2] Create Android drawable for manual button in android/app/src/main/res/drawable/widget_button_manual.xml with sageGreen background
- [ ] T036 [US2] Add scan and manual buttons to Android widget layout XML in android/app/src/main/res/layout/widget_layout.xml
- [ ] T037 [US2] Implement PendingIntent click handlers in BudgetWidgetProvider.kt for scan button (finapp://scan-receipt) and manual button (finapp://add-expense)

#### iOS Widget Buttons
- [ ] T038 [P] [US2] Add SwiftUI Link for scan button in ios/WidgetExtension/WidgetView.swift with URL("finapp://scan-receipt")
- [ ] T039 [P] [US2] Add SwiftUI Link for manual button in ios/WidgetExtension/WidgetView.swift with URL("finapp://add-expense")
- [ ] T040 [US2] Style iOS widget buttons with SF Symbols (doc.text.viewfinder for scan, plus for manual) and sageGreen color

#### Navigation Integration
- [ ] T041 [US2] Verify go_router route configuration for /scan-receipt → CameraScreen in lib/app/routes.dart
- [ ] T042 [US2] Verify go_router route configuration for /add-expense → ManualExpenseScreen in lib/app/routes.dart
- [ ] T043 [US2] Test deep link cold start (app not running) → tap widget button → verify correct screen opens
- [ ] T044 [US2] Test deep link warm start (app in background) → tap widget button → verify screen pushed onto navigation stack
- [ ] T045 [US2] Test expense completion via widget button → verify widget updates immediately with new expense data

**Checkpoint**: Widget buttons should deep link to correct screens in all scenarios (cold start, warm start, app already open) and widget updates after expense entry

---

## Phase 5: User Story 3 - Improved Category Selection (Priority: P3)

**Goal**: Replace category list with dropdown menu ordered by most-recently-used in manual expense entry screen

**Independent Test**: Open manual expense entry, verify categories appear in dropdown (not all visible), verify most recently used category appears first, select category and save expense

### Implementation for User Story 3

#### Database & Data Layer
- [ ] T046 [P] [US3] Run Supabase migration 065 to add last_used_at and use_count columns to user_category_usage table
- [ ] T047 [P] [US3] Implement getCategoriesByMRU query in CategoryRepository in lib/features/categories/data/repositories/category_repository_impl.dart with LEFT JOIN to user_category_usage
- [ ] T048 [US3] Create CategoryUsageService in lib/features/categories/domain/services/category_usage_service.dart to update usage on expense save

#### UI Components
- [ ] T049 [P] [US3] Create reusable DropdownField widget in lib/shared/widgets/dropdown_field.dart for consistent dropdown styling
- [ ] T050 [P] [US3] Create CategoryDropdown widget in lib/features/categories/presentation/widgets/category_dropdown.dart that accepts MRU-sorted categories
- [ ] T051 [US3] Update ManualExpenseScreen in lib/features/expenses/presentation/screens/manual_expense_screen.dart to use CategoryDropdown instead of CategorySelector

#### MRU Tracking Logic
- [ ] T052 [US3] Update CategoryProvider in lib/features/categories/presentation/providers/category_provider.dart to fetch categories with MRU order
- [ ] T053 [US3] Implement usage tracking in expense save flow - call upsert_category_usage RPC after expense creation in lib/features/expenses/data/repositories/expense_repository_impl.dart
- [ ] T054 [US3] Handle virgin categories (never used) by displaying them alphabetically after MRU categories in CategoryDropdown

#### Testing & Validation
- [ ] T055 [US3] Test category dropdown displays MRU order - create expenses in order (Food, Transport, Entertainment), verify dropdown shows Entertainment first
- [ ] T056 [US3] Test dropdown handles many categories (50+) with smooth scrolling and correct ordering
- [ ] T057 [US3] Test virgin categories appear at end in alphabetical order
- [ ] T058 [US3] Verify category usage tracking persists across app restarts and device changes (Supabase sync)

**Checkpoint**: Category dropdown should display MRU-ordered categories, update usage on expense save, and handle all edge cases (no categories, virgin categories, many categories)

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and final validation

- [ ] T059 [P] Add Italian localization strings for widget UI ("spese", "Scansiona scontrino", "Inserimento manuale", "Errore di caricamento") in lib/core/config/strings_it.dart
- [ ] T060 [P] Test widget dark mode support on both Android and iOS (verify color scheme switches correctly)
- [ ] T061 [P] Test widget on different screen sizes (small phone, large phone, tablet) and orientations
- [ ] T062 [P] Verify battery impact is acceptable (<2% per hour for foreground Realtime, <0.1% for periodic updates)
- [ ] T063 Verify widget data persistence across app uninstall/reinstall (cached data cleared as expected)
- [ ] T064 End-to-end integration test: Add widget → view expenses → tap manual button → add expense → verify widget updates → tap scan button → scan receipt → verify widget updates
- [ ] T065 Performance testing: Verify widget update latency <2 seconds for all scenarios (add/edit/delete expense)
- [ ] T066 [P] Code review: Verify all tasks follow Clean Architecture (domain/data/presentation layers)
- [ ] T067 [P] Update documentation in specs/001-widget-category-fixes/quickstart.md with developer setup instructions for widget testing

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-5)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Phase 6)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Independent but integrates with US1 widget display
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Completely independent from US1 and US2

### Within Each User Story

**User Story 1**:
1. Data layer tasks (T012-T014) before widget UI tasks
2. Android UI tasks (T015-T018) can run parallel to iOS UI tasks (T019-T021)
3. Real-time updates (T022-T026) after data layer complete
4. Integration testing (T027-T030) after all implementation complete

**User Story 2**:
1. Deep link setup verification (T031-T033) first
2. Android buttons (T034-T037) parallel to iOS buttons (T038-T040)
3. Navigation integration (T041-T042) before testing (T043-T045)

**User Story 3**:
1. Database migration (T046) before data layer (T047-T048)
2. UI components (T049-T051) parallel to data layer
3. MRU tracking (T052-T054) after data layer and UI complete
4. Testing (T055-T058) after all implementation

### Parallel Opportunities

- **Setup**: All T001-T004 can run in parallel
- **Foundational**: T005-T008 can run in parallel, then T009-T011 sequentially
- **US1 Data**: T012-T013 in parallel
- **US1 Android**: T015-T017 in parallel
- **US1 iOS**: T019-T020 in parallel
- **US2 Drawables**: T034-T035 in parallel
- **US2 Links**: T038-T039 in parallel
- **US3 Database**: T046-T047 in parallel
- **US3 UI**: T049-T050 in parallel
- **Polish**: T059-T062, T066-T067 in parallel

---

## Parallel Example: User Story 1

```bash
# Launch Android and iOS widget UI tasks together:
Task: "Update Android widget layout XML in android/app/src/main/res/layout/widget_layout.xml" (T015)
Task: "Create Android drawable resources for widget background" (T016)
Task: "Create Android drawable for error indicator icon" (T017)
Task: "Update iOS WidgetView.swift in ios/WidgetExtension/WidgetView.swift" (T019)
Task: "Update iOS WidgetProvider.swift in ios/WidgetExtension/WidgetProvider.swift" (T020)

# All work on different files, no conflicts
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T004)
2. Complete Phase 2: Foundational (T005-T011) - CRITICAL
3. Complete Phase 3: User Story 1 (T012-T030)
4. **STOP and VALIDATE**: Test widget display independently
   - Widget shows correct total+count
   - Widget updates in real-time (<2 seconds)
   - Widget handles errors gracefully
   - Widget matches design system
5. Deploy/demo if ready

### Incremental Delivery

1. **Foundation** (Setup + Foundational) → Database and entity models ready
2. **US1 Complete** → Widget displays expenses with real-time updates → MVP ACHIEVED ✓
3. **US2 Complete** → Widget has action buttons → Enhanced UX
4. **US3 Complete** → Category dropdown with MRU → Full feature set
5. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. **Together**: Complete Setup (Phase 1) and Foundational (Phase 2)
2. **Once Foundational done**:
   - Developer A: User Story 1 (Widget Display) - T012-T030
   - Developer B: User Story 2 (Widget Buttons) - T031-T045
   - Developer C: User Story 3 (Category Dropdown) - T046-T058
3. Stories complete and integrate independently
4. **Final validation together**: Polish phase (T059-T067)

---

## Task Count Summary

- **Total Tasks**: 67
- **Setup**: 4 tasks
- **Foundational**: 7 tasks (BLOCKING)
- **User Story 1 (P1)**: 19 tasks (MVP)
- **User Story 2 (P2)**: 15 tasks
- **User Story 3 (P3)**: 13 tasks
- **Polish**: 9 tasks

### Parallel Opportunities

- **Setup**: 4 tasks can run in parallel
- **Foundational**: 4 tasks can run in parallel (T005-T008)
- **US1**: 8 parallel opportunities (Android/iOS UI, data layer)
- **US2**: 6 parallel opportunities (Android/iOS buttons, deep link setup)
- **US3**: 4 parallel opportunities (database, UI components)
- **Polish**: 4 parallel opportunities

### Independent Test Criteria

**User Story 1**: Add widget to home screen → verify displays "€X,XX • Y spese" → add expense in app → verify widget updates within 2 seconds → disconnect network → verify shows cached data with error icon

**User Story 2**: Tap "Scansiona" button on widget → verify camera opens → capture receipt → verify widget updates with new expense. Tap "Manuale" button → verify manual entry opens → enter expense → verify widget updates

**User Story 3**: Open manual expense entry → tap category field → verify dropdown appears with MRU order → select category → save expense → reopen manual entry → verify previously selected category now appears first in dropdown

### Suggested MVP Scope

**Minimum Viable Product** = Setup + Foundational + User Story 1 (T001-T030)

This delivers a working widget that displays personal expenses with real-time updates - the core value proposition. User Stories 2 and 3 are valuable enhancements but not essential for the widget to provide utility.

---

## Notes

- All tasks follow strict format: `- [ ] [ID] [P?] [Story?] Description with file path`
- [P] = Parallelizable (different files, no blocking dependencies)
- [Story] = User story label (US1, US2, US3) for traceability
- Platform-specific code (Android Kotlin, iOS Swift) required for widget UI
- Italian-only app: all UI strings in Italian ("spese", not "expenses")
- Tests are not explicitly requested in spec, so no test tasks included
- Research findings incorporated: App Groups required for iOS, Supabase Realtime for push updates, MRU tracking extends existing table
- Existing infrastructure leveraged: home_widget ^0.6.0, app_links for deep linking, Supabase for backend
