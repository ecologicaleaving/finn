# Implementation Plan: Cash Payment Default Fix & Admin Expense Management

**Branch**: `001-admin-expenses-cash-fix` | **Date**: 2026-01-18 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-admin-expenses-cash-fix/spec.md`

## Summary

This feature addresses two critical enhancements to the expense management system:
1. **Bug Fix**: Resolve payment method default selection issue where "Contanti" (Cash) appears selected but requires manual reselection before saving
2. **Admin Capabilities**: Enable group administrators to create and modify expenses on behalf of any group member

**Technical Approach**:
- Fix payment method initialization by setting default value in parent component state when payment methods load
- Extend manual expense screen with conditional member selector for administrators
- Create dedicated expense edit screen (currently missing from codebase)
- Leverage existing permission checks (`canEdit` already supports admin access)
- Add audit trail fields to track who created/modified expenses for transparency

## Technical Context

**Language/Version**: Dart 3.0+ / Flutter SDK
**Primary Dependencies**:
- State Management: flutter_riverpod ^2.4.0
- Backend: supabase_flutter ^2.0.0
- Local Storage: drift ^2.14.0, hive_flutter ^1.1.0
- Navigation: go_router ^12.0.0

**Storage**:
- Remote: Supabase PostgreSQL (expenses, payment_methods, family_groups tables)
- Local: Drift SQLite (offline caching)
- Secure: flutter_secure_storage (credentials)

**Testing**: flutter_test, mockito, integration_test SDK
**Target Platform**: Android (API 24+), iOS 15+, Web
**Project Type**: Mobile application with Clean Architecture (feature-based modules)
**Performance Goals**:
- Expense save latency <500ms p95
- Payment method selector dropdown render <100ms
- Real-time sync latency <2s for expense updates

**Constraints**:
- Must maintain offline-first capability
- Row Level Security (RLS) policies enforce data access
- Payment method changes must be atomic with expense saves
- UI must follow existing design system patterns

**Scale/Scope**:
- Expected concurrent users per group: 2-10
- Total expenses per group: ~1000-5000 annually
- Payment methods per user: 4 default + 0-10 custom
- Group admin count: 1 per group (creator)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**Status**: No project constitution found at `.specify/memory/constitution.md`

**Default Checks Applied**:
- ✅ **Simplicity**: Changes are minimal and focused on two specific issues
- ✅ **Existing Patterns**: Reuses existing providers, widgets, and repository patterns
- ✅ **No New Dependencies**: All required packages already in pubspec.yaml
- ✅ **Backwards Compatibility**: Changes are additive (admin features) or bug fixes (payment default)
- ✅ **Test Coverage**: Existing test infrastructure supports new scenarios

**Complexity Justification**: None required - implementation follows established codebase patterns.

## Project Structure

### Documentation (this feature)

```text
specs/001-admin-expenses-cash-fix/
├── spec.md               # Feature specification
├── plan.md               # This file (/speckit.plan command output)
├── research.md           # Phase 0 output (technical decisions)
├── data-model.md         # Phase 1 output (entity changes)
├── quickstart.md         # Phase 1 output (developer guide)
├── contracts/            # Phase 1 output (API contracts - N/A for this feature)
├── checklists/           # Quality validation checklists
│   └── requirements.md   # Spec quality checklist (completed)
└── tasks.md              # Phase 2 output (/speckit.tasks command - NOT created yet)
```

### Source Code (repository root)

```text
lib/
├── core/
│   ├── config/
│   │   ├── constants.dart
│   │   ├── env.dart
│   │   └── default_payment_methods.dart
│   ├── enums/
│   ├── errors/
│   └── utils/
├── shared/
│   ├── services/
│   │   ├── supabase_client.dart
│   │   └── secure_storage_service.dart
│   └── widgets/
│       ├── custom_text_field.dart
│       ├── primary_button.dart
│       └── navigation_guard.dart
└── features/
    ├── auth/
    │   ├── domain/entities/user_entity.dart
    │   └── presentation/providers/auth_provider.dart
    ├── groups/
    │   ├── domain/
    │   │   └── entities/
    │   │       ├── family_group_entity.dart
    │   │       └── member_entity.dart
    │   └── presentation/
    │       └── providers/
    │           └── group_provider.dart (isGroupAdminProvider, groupMembersProvider)
    ├── payment_methods/
    │   ├── domain/
    │   │   ├── entities/payment_method_entity.dart
    │   │   └── repositories/payment_method_repository.dart
    │   ├── data/
    │   │   ├── datasources/payment_method_remote_datasource.dart
    │   │   └── repositories/payment_method_repository_impl.dart
    │   └── presentation/
    │       ├── providers/payment_method_provider.dart
    │       └── widgets/payment_method_selector.dart ⚠️ FIX REQUIRED
    └── expenses/
        ├── domain/
        │   ├── entities/expense_entity.dart ⚠️ MAY NEED AUDIT FIELDS
        │   └── repositories/expense_repository.dart
        ├── data/
        │   ├── datasources/expense_remote_datasource.dart
        │   ├── models/expense_model.dart
        │   └── repositories/expense_repository_impl.dart
        └── presentation/
            ├── providers/
            │   ├── expense_provider.dart
            │   └── expense_form_notifier.dart
            ├── screens/
            │   ├── manual_expense_screen.dart ⚠️ ADD MEMBER SELECTOR
            │   ├── expense_detail_screen.dart
            │   └── expense_edit_screen.dart ✨ NEW - TO BE CREATED
            └── widgets/
                ├── payment_method_selector.dart ⚠️ FIX DEFAULT SELECTION
                └── member_selector.dart ✨ NEW - TO BE CREATED

supabase/
└── migrations/
    ├── 052_create_payment_methods_table.sql (existing)
    ├── 053_add_payment_method_to_expenses.sql (existing)
    └── 0XX_add_expense_audit_fields.sql ✨ NEW - IF NEEDED

test/
├── features/
│   ├── expenses/
│   │   ├── domain/entities/expense_entity_test.dart
│   │   ├── presentation/
│   │   │   ├── screens/manual_expense_screen_test.dart
│   │   │   └── widgets/payment_method_selector_test.dart
│   │   └── data/repositories/expense_repository_impl_test.dart
│   └── payment_methods/
│       └── presentation/widgets/payment_method_selector_test.dart
└── integration_test/
    └── expense_management_test.dart
```

**Structure Decision**: Mobile application using Clean Architecture with feature-based organization. Each feature follows domain/data/presentation layering. The app uses Riverpod for state management and Supabase for backend services with offline-first Drift caching.

**Key Modifications**:
1. ⚠️ `payment_method_selector.dart`: Fix default value initialization
2. ⚠️ `manual_expense_screen.dart`: Add conditional member selector for admins
3. ✨ `expense_edit_screen.dart`: Create new dedicated edit screen
4. ✨ `member_selector.dart`: Create new widget for selecting group members
5. ⚠️ `expense_entity.dart`: Potentially add `lastModifiedBy` field (research needed)
6. ✨ Database migration: Potentially add audit columns (research needed)

## Complexity Tracking

> **No violations** - all changes follow existing architectural patterns and use current dependencies.

---

## Phase 0: Research & Technical Decisions

**Status**: To be completed

The following unknowns need research before proceeding to Phase 1:

1. **Audit Trail Implementation**:
   - Decision needed: Store `lastModifiedBy` in expense entity or rely on Supabase audit triggers?
   - Research: Current audit capabilities in Supabase RLS and triggers
   - Impact: Determines if database migration is required

2. **Member Selector UX Pattern**:
   - Decision needed: Dropdown vs. bottom sheet vs. modal for member selection
   - Research: Existing selector patterns in codebase (CategorySelector, PaymentMethodSelector)
   - Impact: UI consistency and development effort

3. **Payment Method Default Initialization**:
   - Decision needed: Fix in widget vs. fix in parent screen's initState
   - Research: Riverpod best practices for async provider initialization
   - Impact: Code maintainability and reusability

4. **Optimistic Locking Strategy**:
   - Decision needed: Implement version field or timestamp-based conflict detection
   - Research: Supabase conflict resolution patterns
   - Impact: Database schema changes and repository logic

5. **Expense Edit Screen Route**:
   - Decision needed: Reuse ManualExpenseScreen with edit mode vs. create separate ExpenseEditScreen
   - Research: Current navigation patterns and screen reusability
   - Impact: Code duplication vs. complexity

**Output**: `research.md` will document decisions, rationales, and alternatives for each unknown.

---

## Phase 1: Design & Contracts

**Status**: Pending Phase 0 completion

### Deliverables:

1. **data-model.md**:
   - Updated ExpenseEntity with audit fields (if decided in Phase 0)
   - MemberSelectorState model
   - ExpenseEditFormState model

2. **contracts/** (N/A):
   - No new API contracts - using existing Supabase RLS policies
   - Existing endpoints/RPC functions are sufficient

3. **quickstart.md**:
   - Developer guide for implementing payment method fix
   - Developer guide for implementing admin expense management
   - Testing scenarios and validation steps

4. **Agent Context Update**:
   - Run `.specify/scripts/powershell/update-agent-context.ps1 -AgentType claude`
   - No new technologies added - all dependencies already in project

---

## Next Steps

1. ✅ Specification created and validated (`/speckit.specify` complete)
2. ✅ Clarifications resolved (`/speckit.clarify` complete)
3. 🔄 **CURRENT**: Implementation planning (`/speckit.plan` in progress)
4. ⏭️ Execute Phase 0 research (within this command)
5. ⏭️ Execute Phase 1 design (within this command)
6. ⏭️ Generate task breakdown (`/speckit.tasks` command)
7. ⏭️ Implement tasks (`/speckit.implement` command)

---

**Generated**: 2026-01-18 | **Planning Agent**: Claude Sonnet 4.5
