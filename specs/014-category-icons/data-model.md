# Data Model: Custom Category Icons

**Feature**: `014-category-icons`
**Date**: 2026-02-05

## Overview

This document defines the data model changes required to support custom category icons. The feature extends the existing `expense_categories` table with an `icon_name` column storing Material Icons identifiers.

## Entity Changes

### ExpenseCategoryEntity

**File**: `lib/features/categories/domain/entities/expense_category_entity.dart`

**New Field**:
```dart
/// Material Icons name for category display (e.g., 'shopping_cart', 'restaurant')
/// If null, falls back to default icon matching logic
final String? iconName;
```

**Updated Constructor**:
```dart
const ExpenseCategoryEntity({
  required this.id,
  required this.name,
  required this.groupId,
  required this.isDefault,
  this.createdBy,
  required this.createdAt,
  required this.updatedAt,
  this.expenseCount,
  this.iconName,  // NEW
});
```

**New Helper Method**:
```dart
/// Get the icon for this category
/// Returns stored icon or default based on name matching
IconData getIcon() {
  if (iconName != null) {
    return IconHelper.getIconFromName(iconName!);
  }
  return IconMatchingService.getDefaultIconForCategory(name);
}
```

## Model Changes

### ExpenseCategoryModel

**File**: `lib/features/categories/data/models/expense_category_model.dart`

**fromJson** (add icon_name parsing):
```dart
iconName: json['icon_name'] as String?,  // NEW
```

**toJson** (add icon_name serialization):
```dart
if (iconName != null) 'icon_name': iconName,  // NEW
```

## Database Schema

### Current Schema
```sql
CREATE TABLE public.expense_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(50) NOT NULL,
  group_id UUID NOT NULL REFERENCES public.family_groups(id) ON DELETE CASCADE,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  UNIQUE(group_id, name)
);
```

### New Column
```sql
icon_name VARCHAR(100) NULL
```

**Properties**:
- **Type**: VARCHAR(100) - Stores Material Icons names (e.g., "shopping_cart", "local_gas_station")
- **Nullable**: Yes - Allows gradual migration and fallback to name-based matching
- **No FK Constraints**: Icon names validated at application level
- **Index**: Optional index for faster icon-based queries

## Migration Scripts

### Phase 1: Add Nullable Column
**File**: `supabase/migrations/20260205_001_add_icon_name_to_categories.sql`

```sql
-- Add icon_name column (nullable for safe migration)
ALTER TABLE public.expense_categories
  ADD COLUMN IF NOT EXISTS icon_name VARCHAR(100) NULL;

-- Add index for faster icon lookups
CREATE INDEX IF NOT EXISTS idx_expense_categories_icon_name
  ON public.expense_categories(icon_name)
  WHERE icon_name IS NOT NULL;

-- Add column comment
COMMENT ON COLUMN public.expense_categories.icon_name IS
  'Material Icons name for category display. Falls back to name-based matching if NULL.';
```

### Phase 2: Backfill Existing Categories
**File**: `supabase/migrations/20260205_002_backfill_category_icons.sql`

```sql
-- Backfill icons using Italian keyword matching
UPDATE public.expense_categories
SET icon_name = CASE
  WHEN LOWER(name) LIKE '%spesa%' OR LOWER(name) LIKE '%alimentari%' THEN 'shopping_cart'
  WHEN LOWER(name) LIKE '%ristorante%' OR LOWER(name) LIKE '%cibo%' THEN 'restaurant'
  WHEN LOWER(name) LIKE '%benzina%' OR LOWER(name) LIKE '%carburante%' THEN 'local_gas_station'
  WHEN LOWER(name) LIKE '%trasporti%' OR LOWER(name) LIKE '%taxi%' THEN 'directions_bus'
  WHEN LOWER(name) LIKE '%casa%' OR LOWER(name) LIKE '%affitto%' THEN 'home'
  WHEN LOWER(name) LIKE '%bollette%' OR LOWER(name) LIKE '%utenze%' THEN 'receipt_long'
  WHEN LOWER(name) LIKE '%salute%' OR LOWER(name) LIKE '%farmacia%' THEN 'medical_services'
  WHEN LOWER(name) LIKE '%sport%' OR LOWER(name) LIKE '%palestra%' THEN 'fitness_center'
  WHEN LOWER(name) LIKE '%svago%' OR LOWER(name) LIKE '%divertimento%' THEN 'celebration'
  WHEN LOWER(name) LIKE '%abbigliamento%' OR LOWER(name) LIKE '%vestiti%' THEN 'checkroom'
  WHEN LOWER(name) LIKE '%tecnologia%' OR LOWER(name) LIKE '%elettronica%' THEN 'devices'
  WHEN LOWER(name) LIKE '%istruzione%' OR LOWER(name) LIKE '%scuola%' THEN 'school'
  WHEN LOWER(name) LIKE '%viaggio%' OR LOWER(name) LIKE '%vacanza%' THEN 'flight'
  WHEN LOWER(name) LIKE '%regalo%' THEN 'card_giftcard'
  WHEN LOWER(name) LIKE '%animali%' OR LOWER(name) LIKE '%pet%' THEN 'pets'
  ELSE 'category'
END
WHERE icon_name IS NULL;
```

### Phase 3: Make Column NOT NULL (Optional Future Step)
**File**: `supabase/migrations/20260205_003_make_icon_name_not_null.sql`

```sql
-- Set default value for future inserts
ALTER TABLE public.expense_categories
  ALTER COLUMN icon_name SET DEFAULT 'category';

-- Make column NOT NULL
ALTER TABLE public.expense_categories
  ALTER COLUMN icon_name SET NOT NULL;
```

## Rollback Strategy

```sql
-- Rollback all phases
DROP INDEX IF EXISTS idx_expense_categories_icon_name;
ALTER TABLE public.expense_categories DROP COLUMN IF EXISTS icon_name;
```

## Repository Interface Changes

### CategoryRepository

**File**: `lib/features/categories/domain/repositories/category_repository.dart`

**New Method**:
```dart
/// Update a category icon
Future<Either<Failure, ExpenseCategoryEntity>> updateCategoryIcon({
  required String categoryId,
  required String iconName,
});
```

**Updated Method Signature**:
```dart
Future<Either<Failure, ExpenseCategoryEntity>> createCategory({
  required String groupId,
  required String name,
  String? iconName,  // NEW: Optional icon name
});
```

## Data Flow

1. **Create Category**: User creates category → Optional icon selected → Stored in `icon_name` column
2. **Update Icon**: User edits category → Selects new icon → `updateCategoryIcon()` called → Realtime update propagates
3. **Display Icon**: Widget reads category → Checks `iconName` field → If null, falls back to `IconMatchingService`
4. **Migration**: Existing categories → Smart matching assigns default icons → Stored in `icon_name`

## Validation Rules

- Icon names must be valid Material Icons identifiers (enforced at application level)
- Invalid icon names fall back to `Icons.category`
- NULL icon_name triggers fallback to name-based matching

## Backward Compatibility

- **Nullable Column**: Existing code continues to work
- **Fallback Logic**: NULL values use existing `_getCategoryIcon()` matching
- **No Breaking Changes**: UI gracefully degrades if icon_name is NULL
