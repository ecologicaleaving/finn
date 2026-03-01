# Implementation Plan: Custom Category Icons

**Branch**: `014-category-icons` | **Date**: 2026-02-05 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/014-category-icons/spec.md`

## Summary

Add customizable icon support to expense categories, allowing users to select Material Design icons from a picker with bilingual (Italian/English) search. Icons are stored in the database and displayed throughout the app using reactive state management for immediate updates.

**Key Deliverables**:
- Database migration adding `icon_name` column to categories table
- Icon picker UI with flutter_iconpicker package
- Smart default icon assignment for existing categories
- Bilingual search (Italian + English keywords)
- Reactive icon updates via existing Riverpod + Supabase Realtime

## Technical Context

**Language/Version**: Dart 3.0+ / Flutter 3.0+
**Primary Dependencies**:
  - Riverpod 2.4.0 (state management - existing)
  - Supabase Flutter 2.0.0 (backend - existing)
  - flutter_iconpicker ^3.2.4 (NEW - icon picker UI)
**Storage**: Supabase (PostgreSQL) - `expense_categories` table extended with `icon_name` column
**Testing**: Flutter test framework (unit + widget tests)
**Target Platform**: Android/iOS mobile app
**Project Type**: Mobile (Flutter Clean Architecture)
**Performance Goals**: Icon picker loads < 500ms, icon updates propagate < 200ms
**Constraints**: Build flag `--no-tree-shake-icons` required to prevent icon removal
**Scale/Scope**: ~15-20 default categories per group, support for 1000+ Material Icons

## Constitution Check

*Constitution file is empty (template only) - No violations to check.*

✅ **GATE PASSED** - Proceeding to implementation.

## Project Structure

### Documentation (this feature)

```text
specs/014-category-icons/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output ✅ COMPLETE
├── data-model.md        # Phase 1 output ✅ COMPLETE
├── contracts/           # Phase 1 output ✅ COMPLETE
│   ├── category_repository.dart
│   ├── icon_matching_service.dart
│   └── icon_helper.dart
├── quickstart.md        # Phase 1 output ✅ COMPLETE
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
lib/
├── features/
│   ├── categories/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── expense_category_entity.dart  # Add iconName field
│   │   │   └── repositories/
│   │   │       └── category_repository.dart      # Add updateCategoryIcon()
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   └── expense_category_model.dart   # Add icon_name JSON
│   │   │   └── datasources/
│   │   │       └── category_remote_datasource.dart  # Update queries
│   │   └── presentation/
│   │       ├── providers/
│   │       │   └── category_provider.dart        # Already reactive ✅
│   │       └── widgets/
│   │           └── category_form_dialog.dart     # Add icon picker
│   └── expenses/
│       └── presentation/
│           └── widgets/
│               └── category_selector.dart         # Replace _getCategoryIcon()
├── core/
│   └── services/
│       ├── icon_matching_service.dart             # NEW: Smart icon matching
│       └── icon_helper.dart                       # NEW: Icon name <-> IconData
└── shared/
    └── widgets/
        └── bilingual_icon_picker.dart             # NEW: Custom icon picker

supabase/migrations/
├── 20260205_001_add_icon_name_to_categories.sql   # Phase 1: Add column
├── 20260205_002_backfill_category_icons.sql       # Phase 2: Backfill icons
└── 20260205_003_make_icon_name_not_null.sql       # Phase 3: NOT NULL (optional)

pubspec.yaml                                        # Add flutter_iconpicker dependency
```

**Structure Decision**: Flutter mobile app using Clean Architecture (existing pattern). New code follows existing feature-based organization (domain/data/presentation). New core services added for icon utilities.

## Phase Summary

### Phase 0: Research ✅ COMPLETE

**Deliverables**:
- [research.md](./research.md) - Resolved all technical unknowns
  - Icon picker package: flutter_iconpicker ^3.2.4
  - Bilingual search: Custom translation map
  - Reactive updates: Existing Riverpod+Realtime (no changes needed)
  - Smart defaults: Italian keyword matching service
  - Migration strategy: Nullable→Backfill→NOT NULL

**Key Findings**:
- No new state management required (Riverpod + Supabase Realtime already handles reactive updates)
- Build flag `--no-tree-shake-icons` required to prevent icon removal
- Existing `CategoryDropdown._getCategoryIcon()` logic can be reused for migration

### Phase 1: Design ✅ COMPLETE

**Deliverables**:
- [data-model.md](./data-model.md) - Database schema and entity changes
  - Added `iconName` field to ExpenseCategoryEntity
  - Added `icon_name` JSON serialization to ExpenseCategoryModel
  - 3-phase migration scripts (add column, backfill, optional NOT NULL)

- [contracts/](./contracts/) - Repository and service interfaces
  - `category_repository.dart` - Added `updateCategoryIcon()` method
  - `icon_matching_service.dart` - Smart Italian keyword matching
  - `icon_helper.dart` - Icon name <-> IconData conversion

- [quickstart.md](./quickstart.md) - Local development and testing guide

- Agent context updated: CLAUDE.md now includes Flutter + Supabase tech stack

### Phase 2: Tasks (Next Step)

**Command**: `/speckit.tasks`

This will generate `tasks.md` with:
- Task dependencies and ordering
- User story phase assignments (P1→P2→P3)
- File paths for each implementation task

## Critical Implementation Notes

### Build Configuration

**IMPORTANT**: Add `--no-tree-shake-icons` flag to all build commands:

```bash
# Development
flutter run --flavor dev --no-tree-shake-icons

# Production build
flutter build apk --flavor prod --no-tree-shake-icons
```

**Update build scripts**:
- `build_and_install.ps1`
- `build_dev.sh`
- Any CI/CD pipeline configs

### Migration Sequence

**DO NOT skip phases** - run migrations in order:

1. **Phase 1** (safe): Add nullable `icon_name` column
2. **Phase 2** (safe): Backfill existing categories with smart defaults
3. **Phase 3** (optional): Make column NOT NULL (only after full deployment verification)

### Reactive State Management

**No changes needed** - The existing `CategoryNotifier` with Supabase Realtime already handles immediate icon updates across all screens. Icon changes propagate automatically via:

```
User updates icon → Supabase UPDATE event → CategoryNotifier.loadCategories() → Widgets rebuild
```

### Icon Naming Convention

Store icon names as Material Icons identifiers (lowercase with underscores):
- ✅ Correct: `'shopping_cart'`, `'local_gas_station'`, `'restaurant'`
- ❌ Incorrect: `'shopping-cart'`, `'shoppingCart'`, `'SHOPPING_CART'`

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Build fails without `--no-tree-shake-icons` | Document in README, add to all build scripts |
| Invalid icon names stored | Validate at application level, fallback to `Icons.category` |
| Migration assigns wrong icons | Users can immediately change via UI |
| Icon picker performance | Lazy loading in GridView, search filters reduce visible icons |

## Next Steps

1. Run `/speckit.tasks` to generate implementation task list
2. Review tasks with user for prioritization
3. Execute tasks in dependency order
4. Test on emulator + physical device (Android + iOS)
5. Deploy Phase 1 migration to production
6. Monitor for 1-2 weeks
7. Deploy Phase 2 migration (backfill)
8. Optionally deploy Phase 3 (NOT NULL constraint)

## Artifacts Summary

| Document | Status | Purpose |
|----------|--------|---------|
| spec.md | ✅ Complete | Feature requirements and acceptance criteria |
| research.md | ✅ Complete | Technical research and design decisions |
| data-model.md | ✅ Complete | Database schema and entity changes |
| contracts/ | ✅ Complete | Repository and service interfaces |
| quickstart.md | ✅ Complete | Local development and testing guide |
| plan.md | ✅ Complete | This file - implementation plan |
| tasks.md | ⏳ Pending | `/speckit.tasks` command |

**Ready for task generation** - Run `/speckit.tasks` to proceed.
