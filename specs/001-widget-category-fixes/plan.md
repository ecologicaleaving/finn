# Implementation Plan: Widget Functionality Fix and Category Selector Enhancement

**Branch**: `001-widget-category-fixes` | **Date**: 2026-01-18 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-widget-category-fixes/spec.md`

## Summary

Fix non-functional home screen widget to display personal monthly expenses (total amount + count) with real-time push updates, update visual design to match current app theme, add "Scan Receipt" and "Manual Entry" action buttons, and convert category selector in manual expense entry screen from visible list to dropdown with most-recently-used ordering.

## Technical Context

**Language/Version**: Dart SDK >=3.0.0 <4.0.0, Flutter (latest stable)
**Primary Dependencies**:
- State Management: flutter_riverpod ^2.4.0, riverpod_annotation ^2.3.0
- Widget: home_widget ^0.6.0 (Android/iOS home screen widget)
- Database: drift ^2.14.0 (SQLite ORM), hive_flutter ^1.1.0 (caching)
- Backend: supabase_flutter ^2.0.0
- Navigation: go_router ^12.0.0, app_links ^6.4.1 (deep linking)
- UI: google_fonts ^6.2.1, fl_chart ^0.65.0
- Background: workmanager ^0.9.0
- Utilities: intl ^0.20.0 (Italian locale), dartz ^0.10.1 (Either), equatable ^2.0.5

**Storage**:
- Local: Drift (SQLite) - primary data persistence
- Cache: Hive - fast key-value storage
- Remote: Supabase - cloud backend
- Secure: secure_storage_service (credentials)

**Testing**: flutter_test, mockito ^5.4.0, integration_test, flutter_lints ^3.0.0

**Target Platform**:
- Android (flavors: production, dev)
- iOS (flavors: production, dev)
- Minimum versions determined by home_widget ^0.6.0

**Project Type**: Mobile (Flutter)

**Performance Goals**:
- Widget update latency: <2 seconds (from spec SC-003)
- Category dropdown response: <300ms
- Real-time push delivery: <2 seconds

**Constraints**:
- Widget must work when app not in foreground (FR-010)
- Offline-capable architecture (existing offline feature support)
- Italian locale only (it_IT)
- Battery efficiency for real-time updates
- Platform-specific widget rendering (Android/iOS)

**Scale/Scope**:
- Family budget tracking app
- Multi-user (family groups)
- Current features: expenses, budgets, recurring expenses, reimbursement tracking, AI receipt scanning
- ~50+ screens in app
- Existing widget implementation partially complete (entity/repository layer exists)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Status**: Constitution file contains template placeholders only - no project-specific principles defined yet.

**Action**: Proceeding with standard Flutter/mobile best practices:
- Clean Architecture (domain/data/presentation layers) - already established in codebase
- Test-driven development for new components
- Riverpod for state management consistency
- Platform-specific widget implementations (Android/iOS)
- Background task safety (respect battery constraints)

**Re-evaluation Required**: After Phase 1 design completion, verify against any future constitution updates.

## Project Structure

### Documentation (this feature)

```text
specs/001-widget-category-fixes/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   ├── widget_provider_contract.dart
│   ├── category_selector_widget_contract.dart
│   └── widget_deep_link_contract.dart
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
lib/
├── features/
│   ├── widget/                         # HOME SCREEN WIDGET FEATURE
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   ├── widget_data_entity.dart         # MODIFY: Change to total+count format
│   │   │   │   └── widget_config_entity.dart       # REVIEW: May need update
│   │   │   └── repositories/
│   │   │       └── widget_repository.dart          # MODIFY: Update interface
│   │   ├── data/
│   │   │   ├── repositories/
│   │   │   │   └── widget_repository_impl.dart     # MODIFY: Implement new data format
│   │   │   └── datasources/
│   │   │       ├── widget_local_datasource.dart    # MODIFY: Cache implementation
│   │   │       └── widget_remote_datasource.dart   # NEW: Real-time push receiver
│   │   └── presentation/
│   │       ├── providers/
│   │       │   ├── widget_provider.dart            # MODIFY: Add push update logic
│   │       │   └── widget_config_provider.dart     # REVIEW
│   │       ├── services/
│   │       │   ├── widget_update_service.dart      # MODIFY: Real-time push
│   │       │   ├── background_refresh_service.dart # REVIEW: May deprecate
│   │       │   └── deep_link_handler.dart          # MODIFY: Handle new buttons
│   │       └── widgets/
│   │           └── platform/
│   │               ├── android_widget.dart         # MODIFY: New UI design
│   │               └── ios_widget.dart             # MODIFY: New UI design
│   │
│   ├── expenses/
│   │   └── presentation/
│   │       ├── screens/
│   │       │   └── manual_expense_screen.dart      # MODIFY: Use new category dropdown
│   │       └── widgets/
│   │           └── category_selector.dart          # NEW: Dropdown version
│   │
│   ├── categories/
│   │   └── presentation/
│   │       ├── providers/
│   │       │   └── category_provider.dart          # MODIFY: Add usage tracking
│   │       └── widgets/
│   │           └── category_dropdown.dart          # NEW: MRU-ordered dropdown
│   │
│   └── scanner/
│       └── presentation/
│           └── screens/
│               └── camera_screen.dart              # REVIEW: Deep link entry point
│
├── shared/
│   └── widgets/
│       └── dropdown_field.dart                     # NEW: Reusable dropdown component
│
├── core/
│   ├── database/
│   │   ├── daos/
│   │   │   └── category_usage_dao.dart            # NEW: Track MRU for categories
│   │   └── drift/tables/
│   │       └── category_usage.dart                # NEW: Table for usage tracking
│   └── services/
│       └── push_notification_service.dart         # NEW: Real-time widget updates
│
└── platform_channels/                             # NEW DIRECTORY
    ├── android/
    │   └── widget_channel.dart                    # Platform channel for Android widget
    └── ios/
        └── widget_channel.dart                    # Platform channel for iOS widget

android/
├── app/src/main/kotlin/.../
│   └── WidgetProvider.kt                          # MODIFY: Render new widget UI
└── app/src/main/res/
    ├── layout/
    │   └── widget_layout.xml                      # MODIFY: New design + buttons
    └── drawable/
        ├── widget_background.xml                  # MODIFY: Updated theme colors
        └── widget_button_*.xml                    # NEW: Button drawables

ios/
├── Runner/
│   └── WidgetExtension/                           # MODIFY: iOS widget extension
│       ├── WidgetProvider.swift                   # MODIFY: New data format
│       ├── WidgetView.swift                       # MODIFY: New UI design
│       └── IntentHandler.swift                    # MODIFY: Handle button taps
└── Podfile                                        # REVIEW: Dependencies

test/
├── features/
│   ├── widget/
│   │   ├── domain/
│   │   │   └── entities/
│   │   │       └── widget_data_entity_test.dart   # MODIFY: Test new format
│   │   ├── data/
│   │   │   └── repositories/
│   │   │       └── widget_repository_impl_test.dart # MODIFY: Test total+count
│   │   └── presentation/
│   │       └── providers/
│   │           └── widget_provider_test.dart      # MODIFY: Test push updates
│   └── categories/
│       └── presentation/
│           └── widgets/
│               └── category_dropdown_test.dart    # NEW: Test MRU ordering
└── integration/
    ├── widget_update_flow_test.dart               # NEW: End-to-end widget update
    └── category_selection_flow_test.dart          # NEW: Dropdown interaction test
```

**Structure Decision**: Mobile app structure using Flutter's feature-first organization. Each feature follows Clean Architecture (domain/data/presentation). Widget implementation requires both Dart (Flutter) and platform-specific code (Kotlin for Android, Swift for iOS) due to home screen widget nature. Category dropdown is pure Flutter widget. Existing architecture is well-established; this feature extends it.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| N/A | No constitution violations | Constitution not yet defined for project |

---

## Phase 0: Research & Technical Decisions

**Status**: PENDING

**Research Tasks**:

1. **home_widget ^0.6.0 Real-time Update Mechanism**
   - How to trigger widget updates immediately from Flutter app?
   - Platform-specific update APIs (Android: AppWidgetManager, iOS: WidgetKit timeline)
   - Background task limitations and battery impact
   - Push notification to widget communication pattern

2. **Widget Data Persistence & Caching Strategy**
   - UserDefaults (iOS) vs SharedPreferences (Android) for widget data
   - Data format for total + count serialization
   - Error indicator state storage
   - Cached data staleness detection

3. **Deep Link Handling for Widget Buttons**
   - app_links ^6.4.1 integration with home_widget
   - URL scheme design for "Scan Receipt" vs "Manual Entry"
   - Handling deep links when app is cold-started vs already running
   - Android Intent vs iOS URL scheme differences

4. **Category Usage Tracking for MRU Ordering**
   - Drift table schema for category usage history
   - Efficient query for "most recently used" (index strategy)
   - Per-user vs per-group tracking
   - Usage timestamp update strategy (on selection vs on save)

5. **Platform-Specific Widget UI Design**
   - Android widget layout XML best practices (RemoteViews limitations)
   - iOS WidgetKit SwiftUI view implementation
   - Applying "Flourishing Finances" theme colors to platform widgets
   - Button rendering constraints (Android: PendingIntent, iOS: Button in SwiftUI)

6. **Real-time Push Architecture**
   - Supabase Realtime subscriptions for expense changes
   - Foreground vs background update delivery
   - Battery optimization strategies
   - Fallback to periodic refresh if push fails

**Output File**: `research.md`

---

## Phase 1: Data Model & Contracts

**Status**: PENDING (blocked by Phase 0)

**Data Model Updates**:

1. **WidgetDataEntity** (modify existing):
   ```dart
   class WidgetDataEntity {
     final double totalAmount;        // Sum of personal expenses (current month)
     final int expenseCount;          // Count of expenses (current month)
     final String currency;           // €
     final String month;              // "Gennaio 2026"
     final DateTime lastUpdated;
     final bool hasError;             // Error indicator flag
     final String? errorMessage;      // Optional error details
     final bool isDarkMode;

     String get formattedDisplay;     // "€342,50 • 12 expenses"
     bool get isStale;                // >2 seconds since update
   }
   ```

2. **CategoryUsage** (new Drift table):
   ```dart
   class CategoryUsage extends Table {
     TextColumn get id => text()();
     TextColumn get userId => text()();
     TextColumn get categoryId => text().references(Categories, #id)();
     DateTimeColumn get lastUsedAt => dateTime()();
     IntColumn get useCount => integer().withDefault(const Constant(1))();

     @override
     Set<Column> get primaryKey => {id};
   }
   ```

3. **CategoryEntity** (extend existing):
   ```dart
   class CategoryEntity {
     // ... existing fields ...
     final DateTime? lastUsedAt;      // NEW: For MRU sorting
     final int useCount;              // NEW: Frequency tracking
   }
   ```

**Contracts**:

1. **WidgetProviderContract** (`contracts/widget_provider_contract.dart`):
   - Interface for platform channel communication
   - Methods: updateWidgetData(), sendErrorState(), handleDeepLink()
   - Event streams for push updates

2. **CategorySelectorContract** (`contracts/category_selector_widget_contract.dart`):
   - Dropdown widget API
   - Props: categories (MRU-sorted), onSelect, selectedCategoryId
   - Callbacks: onSelect(CategoryEntity)

3. **WidgetDeepLinkContract** (`contracts/widget_deep_link_contract.dart`):
   - Deep link URL schemes
   - finapp://scan-receipt
   - finapp://manual-entry
   - Routing logic specification

**Additional Artifacts**:

- `data-model.md`: Complete entity relationship diagram
- `quickstart.md`: Developer setup for widget testing

**Output Files**:
- `data-model.md`
- `contracts/widget_provider_contract.dart`
- `contracts/category_selector_widget_contract.dart`
- `contracts/widget_deep_link_contract.dart`
- `quickstart.md`

---

## Phase 2: Implementation Task Breakdown

**Status**: NOT STARTED (use `/speckit.tasks` command)

This phase is executed by the `/speckit.tasks` command, which will generate:
- `tasks.md`: Dependency-ordered task list with task IDs (T001, T002, etc.)
- User story mapping (US1, US2, US3 from spec.md)
- Parallelization markers for independent tasks
- File path references for each task

**Prerequisites**:
- Phase 0 research complete
- Phase 1 data models and contracts defined
- No unresolved NEEDS CLARIFICATION markers

---

## Notes

**Existing Widget Implementation**: The project already has widget infrastructure at `lib/features/widget/` with entity/repository layers. Current `WidgetDataEntity` includes spent/limit/percentage calculations. This needs refactoring to total+count format per clarifications.

**Theme Colors**: "Flourishing Finances" palette defined in `lib/core/theme/app_colors.dart`:
- Primary: sageGreen (#7A9B76), deepForest (#3D5A3C)
- Accents: terracotta (#A8BFC4), warmSand (#F5EFE7), cream (#FFFBF5)
- Semantic: amberHoney (warning), softCoral (error), mistyBlue (info)

**State Management**: Riverpod providers already exist for widget (`widgetUpdateProvider`, `widgetConfigProvider`). These will be modified to support real-time push updates.

**Category Management**: Category infrastructure exists at `lib/features/categories/` with `category_selector.dart` widget. This will be replaced with dropdown version while maintaining existing API.

**Receipt Scanner**: Fully functional at `lib/features/scanner/` with camera screen and AI-powered extraction. Widget button will deep link to existing `camera_screen.dart`.

**Manual Expense**: Comprehensive screen at `lib/features/expenses/presentation/screens/manual_expense_screen.dart` with all expense fields. Only category selector widget needs modification.

**Testing Strategy**: Follow existing patterns - unit tests with Mockito for repositories/providers, widget tests for UI components, integration tests for end-to-end flows.

**Localization**: App is Italian-only (it_IT). All UI strings must be in Italian. Widget text: "spese" (expenses), error messages in Italian.

**Platform Considerations**:
- Android: RemoteViews has limited layout capabilities, no direct state management
- iOS: WidgetKit requires timeline provider, limited to periodic updates unless using App Intents (iOS 16+)
- Both platforms require separate UI implementation despite shared data layer
