# Quickstart: Custom Category Icons

**Feature**: `014-category-icons`
**Date**: 2026-02-05

## Overview

Quick setup guide for developing and testing the category icons feature locally.

## Prerequisites

- Flutter SDK 3.0+ installed
- Supabase CLI installed (for migrations)
- Access to development Supabase project

## Setup

### 1. Install Dependencies

Add flutter_iconpicker to `pubspec.yaml`:

```yaml
dependencies:
  flutter_iconpicker: ^3.2.4
```

Run:
```bash
flutter pub get
```

### 2. Run Database Migrations

Navigate to project root and run migrations:

```bash
# Phase 1: Add icon_name column
supabase migration up 20260205_001_add_icon_name_to_categories

# Phase 2: Backfill existing categories with smart defaults
supabase migration up 20260205_002_backfill_category_icons

# Verify migration
supabase db diff
```

**Verify in Database**:
```sql
SELECT id, name, icon_name
FROM expense_categories
LIMIT 10;
```

You should see `icon_name` populated with values like `'shopping_cart'`, `'restaurant'`, etc.

### 3. Build with Icon Support

**IMPORTANT**: Use the `--no-tree-shake-icons` flag to prevent Flutter from removing "unused" icons:

```bash
# Dev build
flutter build apk --flavor dev --no-tree-shake-icons

# Run on device
flutter run --flavor dev -d <device-id> --no-tree-shake-icons
```

**Add to build scripts** (`build_and_install.ps1`, `build_dev.sh`):
```bash
flutter build apk --flavor dev --no-tree-shake-icons
```

## Testing Icon Picker Locally

### Quick Test Scenario

1. **Launch app** with `--no-tree-shake-icons` flag
2. **Navigate** to category management (admin only)
3. **Create new category** → Icon picker should open
4. **Search** using Italian keywords:
   - "spesa" → should show shopping_cart icon
   - "casa" → should show home icon
   - "benzina" → should show local_gas_station icon
5. **Search** using English keywords:
   - "car" → should show car-related icons
   - "food" → should show food-related icons
6. **Select icon** → Icon should immediately appear in category list
7. **Create expense** with that category → Icon should display in expense selector

### Verify Reactive Updates

1. **Open app** on two devices (or emulator + physical device)
2. **Edit category icon** on Device 1
3. **Verify** Device 2 updates automatically without refresh (via Realtime)

## Testing Migration Backfill

### Test Data Setup

Create test categories with Italian names:

```sql
-- Insert test categories
INSERT INTO expense_categories (group_id, name, is_default, created_by)
VALUES
  ('your-group-id', 'Spesa Supermercato', false, 'your-user-id'),
  ('your-group-id', 'Benzina Auto', false, 'your-user-id'),
  ('your-group-id', 'Ristorante Pranzo', false, 'your-user-id'),
  ('your-group-id', 'Casa Affitto', false, 'your-user-id'),
  ('your-group-id', 'Unknown Category', false, 'your-user-id');
```

### Run Backfill Migration

```bash
supabase migration up 20260205_002_backfill_category_icons
```

### Verify Results

```sql
SELECT name, icon_name
FROM expense_categories
WHERE group_id = 'your-group-id';
```

**Expected Results**:
```
name                  | icon_name
----------------------|------------------
Spesa Supermercato    | shopping_cart
Benzina Auto          | local_gas_station
Ristorante Pranzo     | restaurant
Casa Affitto          | home
Unknown Category      | category (fallback)
```

## Common Issues

### Issue: Icons not displaying

**Cause**: Build was run without `--no-tree-shake-icons` flag

**Solution**:
```bash
flutter clean
flutter pub get
flutter run --no-tree-shake-icons
```

### Issue: Icon picker shows no icons

**Cause**: flutter_iconpicker package not installed

**Solution**:
```bash
flutter pub get
# Restart IDE/editor
```

### Issue: Migration fails with "column already exists"

**Cause**: Migration already run

**Solution**:
```bash
# Check migration status
supabase migration list

# If needed, rollback and re-run
supabase migration down 20260205_001_add_icon_name_to_categories
supabase migration up 20260205_001_add_icon_name_to_categories
```

### Issue: Realtime updates not working

**Cause**: Supabase Realtime not enabled or connection issue

**Solution**:
1. Check `category_provider.dart` - `_subscribeToRealtimeChanges()` should be called
2. Verify Supabase Realtime is enabled in project settings
3. Check network connectivity

## Development Workflow

### Adding New Icon Mappings

Edit `icon_matching_service.dart`:

```dart
static String getDefaultIconNameForCategory(String categoryName) {
  final name = categoryName.toLowerCase();

  // Add new mapping
  if (name.contains('your_keyword')) {
    return 'your_icon_name';
  }

  // ... rest of mappings
}
```

### Testing Icon Matching

```dart
void main() {
  test('icon matching for Italian keywords', () {
    expect(
      IconMatchingService.getDefaultIconNameForCategory('Spesa'),
      equals('shopping_cart'),
    );
    expect(
      IconMatchingService.getDefaultIconNameForCategory('Benzina'),
      equals('local_gas_station'),
    );
  });
}
```

## Useful Commands

```bash
# Clean build with icon support
flutter clean && flutter pub get && flutter run --no-tree-shake-icons

# Check database icon_name column
supabase db query "SELECT name, icon_name FROM expense_categories"

# Reset icon_name to NULL (for testing backfill)
supabase db query "UPDATE expense_categories SET icon_name = NULL"

# Test icon picker package
flutter run example/main.dart  # In flutter_iconpicker package directory
```

## Next Steps

After local testing:

1. Run `/speckit.tasks` to generate implementation task list
2. Execute tasks in priority order (P1 → P2 → P3)
3. Test on multiple devices (Android + iOS)
4. Deploy migrations to production (Phase 1, then Phase 2 after verification)

## References

- Feature spec: [spec.md](./spec.md)
- Data model: [data-model.md](./data-model.md)
- Research findings: [research.md](./research.md)
- flutter_iconpicker docs: https://pub.dev/packages/flutter_iconpicker
