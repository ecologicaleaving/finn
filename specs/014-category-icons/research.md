# Research: Custom Category Icons Implementation

**Feature**: `014-category-icons`
**Date**: 2026-02-05
**Purpose**: Document research findings and design decisions for category icon support

## Executive Summary

This feature adds customizable icon support to expense categories by extending the existing category management infrastructure. Research confirms that the app already uses a hardcoded icon matching system in `CategoryDropdown._getCategoryIcon()` which can be replaced with database-stored icon names. All technical unknowns have been resolved through codebase analysis and package research.

## Research Findings

### 1. Icon Picker Package Selection

**Question**: Which Flutter icon picker package best supports Material Icons with search and categorization?

**Decision**: Use **flutter_iconpicker** (version ^3.2.4) as the primary icon picker package.

**Rationale**:
- Native Material Icons support with `IconPack.material`
- Built-in search functionality supporting text filtering
- Adaptive dialog design (works on Android, iOS, web)
- Active maintenance and stable in production environments
- No additional icon fonts required (uses built-in Material Icons)
- Supports both single selection (`showIconPicker`) and custom icon packs

**Package Details**:
```yaml
dependencies:
  flutter_iconpicker: ^3.2.4
```

**Key API**:
```dart
IconData? result = await showIconPicker(
  context,
  iconPackModes: [IconPack.material],
  title: Text('Select Icon'),
  searchHintText: 'Search icons',
);
```

**Build Configuration**:
```bash
flutter build --no-tree-shake-icons
```
This flag prevents Flutter from removing "unused" Material Icons during tree-shaking.

**Alternatives Considered**:
1. **flutter_iconpicker_plus** - Rejected: Similar features but less active maintenance
2. **material_symbols_icons** - Rejected: Only provides icons, no picker UI
3. **Custom implementation** - Rejected: Too time-consuming, reinventing the wheel

---

### 2. Bilingual Search Implementation Strategy

**Question**: How to implement bilingual icon search supporting both Italian keywords and English Material Icons names?

**Decision**: Implement a **custom icon translation map** that maps Italian keywords to Material Icons names, combined with flutter_iconpicker's search.

**Rationale**:
- The flutter_iconpicker package provides English-only search (Material Icons use English names)
- Italian users expect to search using Italian terms ("spesa", "ristorante", "casa")
- A translation map provides the best UX
- Existing hardcoded icon mapping in `CategoryDropdown._getCategoryIcon()` already demonstrates Italian keyword patterns

**Italian-English Translation Map** (curated for expense categories):
```dart
// Shopping & Food
'spesa': 'shopping_cart'
'alimentari': 'local_grocery_store'
'cibo': 'restaurant'
'ristorante': 'restaurant'

// Transportation
'benzina': 'local_gas_station'
'carburante': 'local_gas_station'
'trasporti': 'directions_bus'
'taxi': 'local_taxi'
'macchina': 'directions_car'

// Home & Utilities
'casa': 'home'
'affitto': 'apartment'
'bollette': 'receipt_long'
'utenze': 'receipt_long'

// Health & Wellness
'salute': 'medical_services'
'farmacia': 'local_pharmacy'
'sport': 'fitness_center'
'palestra': 'fitness_center'

// Entertainment
'svago': 'celebration'
'divertimento': 'celebration'

// Shopping
'abbigliamento': 'checkroom'
'vestiti': 'checkroom'
'tecnologia': 'devices'
'elettronica': 'devices'

// Education & Work
'istruzione': 'school'
'scuola': 'school'

// Travel & Leisure
'viaggio': 'flight'
'vacanza': 'beach_access'

// Gifts & Special
'regalo': 'card_giftcard'
'animali': 'pets'
'pet': 'pets'
```

---

### 3. Riverpod Reactive State for Immediate UI Updates

**Question**: How to ensure icon changes propagate immediately across all screens?

**Decision**: Leverage existing Riverpod reactive state pattern with Supabase Realtime subscriptions.

**Rationale**:
- Existing `CategoryNotifier` already implements real-time sync via Supabase Realtime
- When a category's icon changes, the `_handleRealtimeChange()` callback triggers `loadCategories()`
- All widgets watching `categoryProvider(groupId)` automatically rebuild
- **No additional work required** - the pattern already exists and works perfectly

**Existing Implementation** (`lib/features/categories/presentation/providers/category_provider.dart`):
```dart
void _subscribeToRealtimeChanges() {
  _categoriesChannel = _supabaseClient
      .channel('expense-categories-changes-$_groupId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'expense_categories',
        callback: _handleRealtimeChange,
      )
      .subscribe();
}

void _handleRealtimeChange(PostgresChangePayload payload) {
  switch (payload.eventType) {
    case PostgresChangeEvent.update:  // Icon changes trigger this
      loadCategories();  // Reloads all categories, widgets auto-rebuild
      break;
  }
}
```

**How It Works**:
1. User updates category icon → Update sent to Supabase
2. Supabase broadcasts PostgreSQL `UPDATE` event
3. `_handleRealtimeChange()` receives event, calls `loadCategories()`
4. All widgets watching `categoryProvider` rebuild with new icons

---

### 4. Smart Default Icon Matching for Migration

**Question**: How to automatically assign appropriate icons to existing categories during migration?

**Decision**: Create a deterministic icon matching service using Italian keyword patterns.

**Rationale**:
- Existing `CategoryDropdown._getCategoryIcon()` already demonstrates effective matching
- Migration should replicate this logic for consistency
- Deterministic matching ensures repeatable results
- Fallback to `Icons.category` for unrecognized names

**Smart Matching Logic** (mirrors existing `_getCategoryIcon()`):
```dart
static String getDefaultIconName(String categoryName) {
  final name = categoryName.toLowerCase();

  if (name.contains('spesa') || name.contains('alimentari')) return 'shopping_cart';
  if (name.contains('ristorante') || name.contains('cibo')) return 'restaurant';
  if (name.contains('benzina') || name.contains('carburante')) return 'local_gas_station';
  if (name.contains('trasporti') || name.contains('taxi')) return 'directions_bus';
  if (name.contains('casa') || name.contains('affitto')) return 'home';
  if (name.contains('bollette') || name.contains('utenze')) return 'receipt_long';
  if (name.contains('salute') || name.contains('farmacia')) return 'medical_services';
  if (name.contains('sport') || name.contains('palestra')) return 'fitness_center';
  if (name.contains('svago') || name.contains('divertimento')) return 'celebration';
  if (name.contains('abbigliamento') || name.contains('vestiti')) return 'checkroom';
  if (name.contains('tecnologia') || name.contains('elettronica')) return 'devices';
  if (name.contains('istruzione') || name.contains('scuola')) return 'school';
  if (name.contains('viaggio') || name.contains('vacanza')) return 'flight';
  if (name.contains('regalo')) return 'card_giftcard';
  if (name.contains('animali') || name.contains('pet')) return 'pets';

  return 'category'; // Default fallback
}
```

---

### 5. Supabase Migration Best Practices

**Question**: What's the safest approach for adding the nullable `icon_name` column?

**Decision**: Use **nullable column with backfill migration** pattern.

**Rationale**:
- Adding nullable columns is safe and non-breaking
- Backfilling can happen in separate transaction after column creation
- Allows rollback if issues occur
- Matches pattern from existing migrations (e.g., `20260116_001_create_recurring_expenses.sql`)

**Migration Strategy** (3-phase):

**Phase 1**: Add Nullable Column
**Phase 2**: Backfill Existing Categories
**Phase 3**: Make Column NOT NULL (optional future step)

---

## Dependencies Analysis

### External Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| flutter_iconpicker | ^3.2.4 | Icon picker dialog with Material Icons |
| Riverpod | 2.4.0 (existing) | State management (no changes) |
| Supabase Flutter | 2.0.0 (existing) | Backend SDK (no changes) |

**New Dependencies Required**: Only `flutter_iconpicker` package.

### Risk Areas

1. **Build Flag Requirement** - Must use `--no-tree-shake-icons` flag
2. **Icon Name Validation** - Store only valid Material Icon names
3. **Migration Accuracy** - Smart matching may assign wrong icons (users can fix via UI)

---

## Technical Decisions Summary

| Decision | Choice | Alternative Rejected |
|----------|--------|---------------------|
| Icon Picker Package | flutter_iconpicker | Custom implementation |
| Icon Storage | Database column (icon_name) | Enum or JSON field |
| Bilingual Search | Translation map | AI fuzzy matching |
| Reactive Updates | Existing Riverpod+Realtime | Manual refresh |
| Migration Strategy | Nullable→Backfill→NOT NULL | Direct NOT NULL |

---

## Critical Files Identified

1. `lib/features/categories/domain/entities/expense_category_entity.dart` - Add `iconName` field
2. `lib/features/categories/data/models/expense_category_model.dart` - Add JSON serialization
3. `lib/features/expenses/presentation/widgets/category_selector.dart` - Replace hardcoded `_getCategoryIcon()`
4. `lib/features/categories/data/datasources/category_remote_datasource.dart` - Update queries
5. `lib/features/categories/presentation/widgets/category_form_dialog.dart` - Add icon picker

---

## Conclusion

All research questions resolved. Feature is technically feasible using existing patterns with minimal new dependencies. Reactive updates work automatically through existing Riverpod+Realtime infrastructure.

**Next**: Generate `data-model.md` with complete entity and schema definitions.
