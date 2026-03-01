# Research: MRU Category Ordering Implementation with Drift

**Date**: 2026-01-18
**Context**: Feature 001-widget-category-fixes requires category dropdown to show "most recently used first" ordering
**Current Status**: `user_category_usage` table exists for virgin category tracking, but only tracks `first_used_at` (not suitable for MRU ordering)

---

## Decision: Enhanced Usage Tracking Strategy

**Recommendation**: Extend the existing `user_category_usage` table to track both first usage (for virgin detection) and last usage (for MRU ordering). This approach:
- ✅ Reuses existing infrastructure (table, RLS policies, entities)
- ✅ Maintains backward compatibility with virgin category detection
- ✅ Provides efficient MRU ordering with minimal schema changes
- ✅ Tracks usage per-user (correct granularity for family expense app)
- ✅ Supports efficient queries with composite indexes

---

## Rationale

### Why Per-User Tracking?
The app has a **family group** model where multiple users share expense categories. Each user should see categories ordered by **their own** usage patterns, not the group's aggregate usage. This provides:
- **Personalization**: Each family member sees categories in their preferred order
- **Accuracy**: Reflects individual spending habits (e.g., one person uses "Groceries" frequently, another uses "Entertainment")
- **Privacy**: Usage patterns remain user-specific within the family group

### Why Extend `user_category_usage` vs. New Table?
Current table structure:
```sql
CREATE TABLE user_category_usage (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES profiles(id),
  category_id UUID NOT NULL REFERENCES expense_categories(id),
  first_used_at TIMESTAMPTZ NOT NULL,
  UNIQUE(user_id, category_id)
);
```

**Advantages of extending this table**:
1. Already has the correct granularity (per-user, per-category)
2. RLS policies already configured for user isolation
3. Entity models already exist in Flutter codebase
4. One record per user-category pair (efficient storage)
5. Adding `last_used_at` and `use_count` columns is a simple migration

**Alternative rejected**: Separate `category_usage_mru` table would duplicate the user-category relationship and complicate queries.

### Why Update on Expense Save (Not Selection)?
- **Accuracy**: Only committed expenses reflect actual category usage
- **Intent**: Users may select categories while exploring but change their mind
- **Data Quality**: Prevents noise from abandoned expense drafts
- **Consistency**: Matches how the existing `first_used_at` field is populated

---

## Table Schema Enhancement

### Migration Strategy

**New Migration**: `065_enhance_user_category_usage_for_mru.sql`

```sql
-- Migration: Enhance user_category_usage table for MRU category ordering
-- Feature: Widget Category Fixes (001-widget-category-fixes)
-- Task: [To be assigned]

-- Add new columns for MRU tracking
ALTER TABLE public.user_category_usage
  ADD COLUMN IF NOT EXISTS last_used_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS use_count INTEGER NOT NULL DEFAULT 1;

-- Backfill last_used_at from first_used_at for existing records
UPDATE public.user_category_usage
SET last_used_at = first_used_at
WHERE last_used_at IS NULL;

-- Drop the old index (no longer optimal)
DROP INDEX IF EXISTS idx_user_category_usage_lookup;

-- Create composite index optimized for MRU queries
-- Supports: ORDER BY last_used_at DESC with user_id filter
CREATE INDEX idx_user_category_mru
  ON public.user_category_usage(user_id, last_used_at DESC);

-- Create index for virgin category checks (still needed)
CREATE INDEX idx_user_category_virgin
  ON public.user_category_usage(user_id, category_id);

-- Add comment
COMMENT ON COLUMN public.user_category_usage.last_used_at IS 'Timestamp of most recent expense creation in this category (for MRU ordering)';
COMMENT ON COLUMN public.user_category_usage.use_count IS 'Total number of expenses created in this category (for analytics)';
```

### Updated Table Schema

```sql
CREATE TABLE public.user_category_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  category_id UUID NOT NULL REFERENCES public.expense_categories(id) ON DELETE CASCADE,
  first_used_at TIMESTAMPTZ NOT NULL DEFAULT now(),    -- Virgin detection
  last_used_at TIMESTAMPTZ NOT NULL DEFAULT now(),     -- MRU ordering
  use_count INTEGER NOT NULL DEFAULT 1,                -- Usage frequency
  UNIQUE(user_id, category_id)
);

-- Indexes
CREATE INDEX idx_user_category_mru
  ON public.user_category_usage(user_id, last_used_at DESC);

CREATE INDEX idx_user_category_virgin
  ON public.user_category_usage(user_id, category_id);
```

**RLS Policies**: No changes needed (existing policies already cover the new columns)

---

## Update Strategy

### When to Update Usage Timestamps

**Trigger Point**: After successful expense save (create or edit with category change)

**Update Logic**:
```sql
-- Upsert operation (UPSERT in Supabase)
INSERT INTO user_category_usage (user_id, category_id, first_used_at, last_used_at, use_count)
VALUES (?, ?, now(), now(), 1)
ON CONFLICT (user_id, category_id)
DO UPDATE SET
  last_used_at = now(),
  use_count = user_category_usage.use_count + 1;
```

**Implementation Location**: `expense_repository_impl.dart` after expense save

**Error Handling**: Usage tracking failures should NOT block expense creation (fire-and-forget with error logging)

### What NOT to Track

- ❌ Category dropdown selection (only committed expenses)
- ❌ Expense edits that don't change category (no-op)
- ❌ Expense deletions (do not decrement use_count - historical data remains)

---

## Query Pattern for MRU-Ordered Categories

### Drift DAO Implementation

**1. Update Entity** (`user_category_usage_entity.dart`):
```dart
class UserCategoryUsageEntity extends Equatable {
  final String id;
  final String userId;
  final String categoryId;
  final DateTime firstUsedAt;
  final DateTime lastUsedAt;       // NEW
  final int useCount;              // NEW

  const UserCategoryUsageEntity({
    required this.id,
    required this.userId,
    required this.categoryId,
    required this.firstUsedAt,
    required this.lastUsedAt,
    required this.useCount,
  });

  @override
  List<Object?> get props => [
    id, userId, categoryId, firstUsedAt, lastUsedAt, useCount,
  ];
}
```

**2. Update Model** (`user_category_usage_model.dart`):
```dart
class UserCategoryUsageModel extends UserCategoryUsageEntity {
  const UserCategoryUsageModel({
    required super.id,
    required super.userId,
    required super.categoryId,
    required super.firstUsedAt,
    required super.lastUsedAt,
    required super.useCount,
  });

  factory UserCategoryUsageModel.fromJson(Map<String, dynamic> json) {
    return UserCategoryUsageModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      categoryId: json['category_id'] as String,
      firstUsedAt: DateTime.parse(json['first_used_at'] as String),
      lastUsedAt: DateTime.parse(json['last_used_at'] as String),
      useCount: json['use_count'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'category_id': categoryId,
      'first_used_at': firstUsedAt.toIso8601String(),
      'last_used_at': lastUsedAt.toIso8601String(),
      'use_count': useCount,
    };
  }
}
```

**3. Repository Method** (`category_repository.dart`):
```dart
/// Get categories for a user ordered by most recently used first.
///
/// Categories the user has never used will appear at the end in alphabetical order.
Future<Either<Failure, List<ExpenseCategoryEntity>>> getCategoriesByMRU({
  required String userId,
  required String groupId,
});
```

**4. Repository Implementation** (`category_repository_impl.dart`):
```dart
@override
Future<Either<Failure, List<ExpenseCategoryEntity>>> getCategoriesByMRU({
  required String userId,
  required String groupId,
}) async {
  try {
    final categories = await remoteDataSource.getCategoriesByMRU(
      userId: userId,
      groupId: groupId,
    );
    return Right(categories.map((c) => c.toEntity()).toList());
  } on ServerException catch (e) {
    return Left(ServerFailure(e.message));
  } catch (e) {
    return Left(ServerFailure(e.toString()));
  }
}
```

**5. Remote DataSource Query** (`category_remote_datasource.dart`):
```dart
/// Get categories ordered by MRU for a specific user.
Future<List<ExpenseCategoryModel>> getCategoriesByMRU({
  required String userId,
  required String groupId,
}) async {
  try {
    // Query with LEFT JOIN to include never-used categories
    final response = await _supabaseClient
        .from('expense_categories')
        .select('''
          *,
          user_category_usage!left(last_used_at, use_count)
        ''')
        .eq('group_id', groupId)
        .eq('user_category_usage.user_id', userId)
        .order('user_category_usage.last_used_at', ascending: false, nullsLast: true)
        .order('name', ascending: true); // Alphabetical for never-used categories

    if (response == null) {
      throw ServerException('Failed to fetch categories');
    }

    return (response as List)
        .map((json) => ExpenseCategoryModel.fromJson(json))
        .toList();
  } catch (e) {
    throw ServerException('Failed to fetch MRU categories: $e');
  }
}
```

**Query Explanation**:
- `LEFT JOIN` ensures categories never used by this user still appear in results
- `ORDER BY last_used_at DESC NULLS LAST` puts most recently used first, never-used last
- Secondary `ORDER BY name ASC` alphabetizes never-used categories for consistency
- Uses `idx_user_category_mru` index for efficient sorting

---

## Handling Categories Never Used

### Default Sort Order for Virgin Categories

**Strategy**: Categories the user has never used appear **at the end** of the dropdown in **alphabetical order**.

**Rationale**:
- Users are most likely to select categories they've used before
- Alphabetical ordering for virgin categories is predictable and scannable
- Matches user expectations (commonly used items at top, everything else sorted logically)

**Implementation**: The SQL query handles this with `NULLS LAST` + secondary `ORDER BY name`

### Cold Start (User Has No Expense History)

When a user first joins the app and has no expenses:
- **All categories** appear in alphabetical order (no MRU data exists)
- As soon as they create their first expense, that category moves to the top
- Over time, the list personalizes based on their usage patterns

---

## Drift Table Integration (Offline Support)

The app uses Drift for offline caching. The `user_category_usage` table should be added to the Drift schema for offline MRU support.

### Drift Table Definition

**File**: `lib/core/database/drift/tables/user_category_usage_table.dart` (NEW)

```dart
import 'package:drift/drift.dart';

/// Drift table: User Category Usage for MRU ordering
/// Tracks category usage per user for most-recently-used sorting
@TableIndex(name: 'user_category_mru_idx', columns: {#userId, #lastUsedAt})
@TableIndex(name: 'user_category_virgin_idx', columns: {#userId, #categoryId})
class UserCategoryUsageTable extends Table {
  // Primary Key
  TextColumn get id => text()();

  // Relationships
  TextColumn get userId => text()(); // References profiles(id)
  TextColumn get categoryId => text()(); // References expense_categories(id)

  // Timestamps
  DateTimeColumn get firstUsedAt => dateTime()(); // Virgin detection
  DateTimeColumn get lastUsedAt => dateTime()(); // MRU ordering
  IntColumn get useCount => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'UNIQUE(user_id, category_id)',
  ];
}
```

### Add to Database

**File**: `lib/features/offline/data/local/offline_database.dart`

```dart
import '../../../../core/database/drift/tables/user_category_usage_table.dart';

@DriftDatabase(tables: [
  // ... existing tables ...
  CachedCategories,
  UserCategoryUsageTable, // NEW
])
class OfflineDatabase extends _$OfflineDatabase {
  @override
  int get schemaVersion => 5; // Increment version

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // ... existing migrations ...
      if (from < 5) {
        // Add user category usage table for MRU ordering
        await m.createTable(userCategoryUsageTable);
      }
    },
  );
}
```

### Offline Query Pattern

When offline, the category provider can query the local Drift database:

```dart
Future<List<ExpenseCategoryEntity>> getCategoriesByMRU({
  required String userId,
  required String groupId,
}) async {
  final query = (select(cachedCategories)
    ..where((c) => c.groupId.equals(groupId)))
    .join([
      leftOuterJoin(
        userCategoryUsageTable,
        userCategoryUsageTable.categoryId.equalsExp(cachedCategories.id) &
        userCategoryUsageTable.userId.equals(userId),
      ),
    ])
    ..orderBy([
      OrderingTerm(
        expression: userCategoryUsageTable.lastUsedAt,
        mode: OrderingMode.desc,
      ),
      OrderingTerm(
        expression: cachedCategories.name,
        mode: OrderingMode.asc,
      ),
    ]);

  final rows = await query.get();
  return rows.map((row) => row.readTable(cachedCategories).toEntity()).toList();
}
```

---

## Code Examples

### 1. Update Usage After Expense Save

**File**: `lib/features/expenses/data/repositories/expense_repository_impl.dart`

```dart
@override
Future<Either<Failure, ExpenseEntity>> createExpense({
  required String groupId,
  required String userId,
  required double amount,
  required DateTime date,
  String? categoryId,
  // ... other params
}) async {
  try {
    // Create the expense
    final expense = await remoteDataSource.createExpense(
      groupId: groupId,
      userId: userId,
      amount: amount,
      date: date,
      categoryId: categoryId,
      // ... other params
    );

    // Update category usage (fire-and-forget, don't block on failure)
    if (categoryId != null) {
      _updateCategoryUsage(userId: userId, categoryId: categoryId)
          .catchError((error) {
        print('Failed to update category usage: $error');
      });
    }

    return Right(expense.toEntity());
  } catch (e) {
    return Left(ServerFailure(e.toString()));
  }
}

/// Update category usage tracking (fire-and-forget)
Future<void> _updateCategoryUsage({
  required String userId,
  required String categoryId,
}) async {
  await remoteDataSource.updateCategoryUsage(
    userId: userId,
    categoryId: categoryId,
  );
}
```

**File**: `lib/features/expenses/data/datasources/expense_remote_datasource.dart`

```dart
/// Update category usage tracking (upsert)
Future<void> updateCategoryUsage({
  required String userId,
  required String categoryId,
}) async {
  await _supabaseClient.from('user_category_usage').upsert({
    'user_id': userId,
    'category_id': categoryId,
    'first_used_at': DateTime.now().toIso8601String(), // Only used on INSERT
    'last_used_at': DateTime.now().toIso8601String(),
    'use_count': 1, // Will be incremented by trigger or ON CONFLICT clause
  }, onConflict: 'user_id,category_id');

  // Note: The ON CONFLICT clause will update last_used_at and increment use_count
  // This requires a database function or trigger (see Alternative 2 below)
}
```

### 2. Use MRU-Ordered Categories in CategoryDropdown

**File**: `lib/features/expenses/presentation/widgets/category_selector.dart`

```dart
/// Compact category selector as a dropdown.
class CategoryDropdown extends ConsumerWidget {
  const CategoryDropdown({
    super.key,
    required this.selectedCategoryId,
    required this.onCategorySelected,
    this.enabled = true,
  });

  final String? selectedCategoryId;
  final ValueChanged<String> onCategorySelected;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final userId = authState.user?.id;
    final groupId = authState.user?.groupId;

    if (userId == null || groupId == null) {
      return const Text('Nessun gruppo disponibile');
    }

    // NEW: Use MRU-ordered category provider instead of regular category provider
    final categoryState = ref.watch(categoryMRUProvider(userId));

    if (categoryState.isLoading) {
      return const LinearProgressIndicator();
    }

    if (categoryState.errorMessage != null) {
      return Text(categoryState.errorMessage!);
    }

    return DropdownButtonFormField<String>(
      value: selectedCategoryId,
      decoration: const InputDecoration(
        labelText: 'Categoria',
        prefixIcon: Icon(Icons.category_outlined),
      ),
      items: categoryState.categories.map((category) {
        return DropdownMenuItem(
          value: category.id,
          child: Text(category.name),
        );
      }).toList(),
      onChanged: enabled
          ? (value) {
              if (value != null) {
                onCategorySelected(value);
              }
            }
          : null,
    );
  }
}
```

### 3. New MRU Provider

**File**: `lib/features/categories/presentation/providers/category_mru_provider.dart` (NEW)

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/expense_category_entity.dart';
import '../../domain/repositories/category_repository.dart';
import 'category_repository_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// State for MRU-ordered categories
class CategoryMRUState {
  const CategoryMRUState({
    this.categories = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final List<ExpenseCategoryEntity> categories;
  final bool isLoading;
  final String? errorMessage;

  CategoryMRUState copyWith({
    List<ExpenseCategoryEntity>? categories,
    bool? isLoading,
    String? errorMessage,
  }) {
    return CategoryMRUState(
      categories: categories ?? this.categories,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

/// Provider for MRU-ordered categories
final categoryMRUProvider = StateNotifierProvider.family<CategoryMRUNotifier, CategoryMRUState, String>(
  (ref, userId) {
    final repository = ref.watch(categoryRepositoryProvider);
    final authState = ref.watch(authProvider);
    final groupId = authState.user?.groupId;

    return CategoryMRUNotifier(
      repository: repository,
      userId: userId,
      groupId: groupId ?? '',
    );
  },
);

class CategoryMRUNotifier extends StateNotifier<CategoryMRUState> {
  CategoryMRUNotifier({
    required this.repository,
    required this.userId,
    required this.groupId,
  }) : super(const CategoryMRUState()) {
    loadCategories();
  }

  final CategoryRepository repository;
  final String userId;
  final String groupId;

  Future<void> loadCategories() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final result = await repository.getCategoriesByMRU(
      userId: userId,
      groupId: groupId,
    );

    result.fold(
      (failure) => state = state.copyWith(
        isLoading: false,
        errorMessage: failure.message,
      ),
      (categories) => state = state.copyWith(
        categories: categories,
        isLoading: false,
      ),
    );
  }

  /// Refresh categories after expense creation
  void refresh() => loadCategories();
}
```

---

## Alternatives Considered

### Alternative 1: Track Usage in `expenses` Table

**Approach**: Query `expenses` table directly to determine MRU order

```sql
SELECT DISTINCT c.*, MAX(e.date) as last_expense_date
FROM expense_categories c
LEFT JOIN expenses e ON e.category_id = c.id AND e.created_by = ?
WHERE c.group_id = ?
GROUP BY c.id
ORDER BY last_expense_date DESC NULLS LAST, c.name ASC;
```

**Why Rejected**:
- ❌ Poor performance on large expense tables (requires full table scan + GROUP BY)
- ❌ No index can efficiently support this query pattern
- ❌ Scales poorly as expense count grows (10,000+ expenses)
- ❌ Cannot efficiently distinguish between user's expenses and group expenses

### Alternative 2: Database Function for Use Count Increment

**Approach**: Create PostgreSQL function to handle atomic increment

```sql
CREATE OR REPLACE FUNCTION update_category_usage(
  p_user_id UUID,
  p_category_id UUID
) RETURNS VOID AS $$
BEGIN
  INSERT INTO user_category_usage (user_id, category_id, first_used_at, last_used_at, use_count)
  VALUES (p_user_id, p_category_id, now(), now(), 1)
  ON CONFLICT (user_id, category_id)
  DO UPDATE SET
    last_used_at = now(),
    use_count = user_category_usage.use_count + 1;
END;
$$ LANGUAGE plpgsql;
```

**Why Considered**:
- ✅ Atomic increment (no race conditions)
- ✅ Cleaner client code (single function call)
- ✅ Consistent logic across all clients

**Tradeoff**: Adds complexity (requires migration + function management). **Recommend implementing this if race conditions become an issue.**

### Alternative 3: Track MRU in Category Selector State

**Approach**: Client-side caching of recently selected categories in Flutter state

**Why Rejected**:
- ❌ Doesn't persist across app restarts
- ❌ Doesn't sync across multiple devices
- ❌ Requires complex state management
- ❌ Inaccurate (based on selections, not actual expense saves)

---

## Performance Considerations

### Index Efficiency

The `idx_user_category_mru` index supports the critical MRU query:
- **Columns**: `(user_id, last_used_at DESC)`
- **Query**: `WHERE user_id = ? ORDER BY last_used_at DESC`
- **Performance**: O(log n) lookup + sequential scan of user's categories (~10-50 rows)
- **Storage**: Minimal overhead (one entry per user-category pair)

### Query Performance Estimates

Assuming typical data:
- 20-30 categories per group
- 5-10 categories actually used by each user
- 10,000 total expenses in system

**MRU Query Performance**:
- Index seek: <1ms
- Category join: <5ms
- **Total**: <10ms for dropdown population

### Storage Overhead

Per user-category pair: ~48 bytes
- `id` (UUID): 16 bytes
- `user_id` (UUID): 16 bytes
- `category_id` (UUID): 16 bytes
- `first_used_at` (TIMESTAMPTZ): 8 bytes
- `last_used_at` (TIMESTAMPTZ): 8 bytes
- `use_count` (INTEGER): 4 bytes
- Index overhead: ~32 bytes

**Total per user**: 20 categories × 80 bytes = **1.6 KB** (negligible)

---

## Testing Checklist

### Unit Tests
- [ ] `UserCategoryUsageModel.fromJson()` handles new fields
- [ ] `UserCategoryUsageEntity` equality comparison includes new fields
- [ ] Repository `getCategoriesByMRU()` returns correct ordering

### Integration Tests
- [ ] Creating expense updates `last_used_at` timestamp
- [ ] Creating expense increments `use_count`
- [ ] MRU query returns categories in correct order (recently used first)
- [ ] Categories never used appear last in alphabetical order
- [ ] Usage tracking failures don't block expense creation

### UI Tests
- [ ] Category dropdown shows most recently used categories at top
- [ ] After creating expense, category moves to top of dropdown
- [ ] Virgin categories appear at bottom alphabetically
- [ ] Dropdown works correctly when user has no expense history (cold start)

---

## Migration Checklist

1. ✅ Create migration `065_enhance_user_category_usage_for_mru.sql`
2. ✅ Update `UserCategoryUsageEntity` with new fields
3. ✅ Update `UserCategoryUsageModel` with new fields
4. ✅ Add `getCategoriesByMRU()` method to `CategoryRepository` interface
5. ✅ Implement `getCategoriesByMRU()` in `CategoryRepositoryImpl`
6. ✅ Add `getCategoriesByMRU()` query to `CategoryRemoteDataSource`
7. ✅ Update expense repository to track usage after save
8. ✅ Create `CategoryMRUProvider` for MRU-ordered state management
9. ✅ Update `CategoryDropdown` widget to use MRU provider
10. ✅ Add Drift table `UserCategoryUsageTable` for offline support
11. ✅ Add Drift migration to `OfflineDatabase` (schema version 5)
12. ✅ Test migration with existing production data
13. ✅ Test category ordering in dropdown (online + offline)

---

## Risks & Mitigation

### Risk 1: Migration Fails on Large Datasets
**Likelihood**: Low
**Impact**: Medium
**Mitigation**: Test migration on staging database with production-like data volume. Use `IF NOT EXISTS` and `IF NULL` checks for idempotency.

### Risk 2: Race Conditions on `use_count` Increment
**Likelihood**: Low (unlikely users create expenses simultaneously in same category)
**Impact**: Low (count would be slightly inaccurate, doesn't affect MRU ordering)
**Mitigation**: Accept eventual consistency for `use_count`. If accuracy becomes critical, implement database function (Alternative 2).

### Risk 3: Performance Degradation on Large Category Lists
**Likelihood**: Low (most groups have 20-30 categories)
**Impact**: Low
**Mitigation**: Index on `(user_id, last_used_at DESC)` ensures O(log n) performance. Monitor query performance in production.

### Risk 4: Offline Sync Conflicts
**Likelihood**: Medium (users may create expenses offline)
**Impact**: Low
**Mitigation**: Drift's sync mechanism handles upsert conflicts. Last-write-wins for `last_used_at` is acceptable for MRU ordering.

---

## Future Enhancements

### Phase 2: Advanced MRU Features
- **Time-based decay**: Weight recent usage more heavily than old usage
- **Context-aware ordering**: Different MRU lists for different expense types (group vs. personal)
- **Smart defaults**: Pre-populate category based on merchant name + MRU history

### Phase 3: Analytics
- **Usage insights**: "You use 'Groceries' 40% of the time"
- **Budget recommendations**: "Consider setting a budget for your top 3 categories"
- **Category suggestions**: "Other users in your group use 'Dining Out' frequently"

---

## References

- **Spec**: `specs/001-widget-category-fixes/spec.md` (FR-008: MRU ordering requirement)
- **Existing Migration**: `027_user_category_usage_table.sql` (virgin category tracking)
- **Entity**: `lib/features/categories/domain/entities/user_category_usage_entity.dart`
- **Provider**: `lib/features/categories/presentation/providers/category_provider.dart`
- **Dropdown Widget**: `lib/features/expenses/presentation/widgets/category_selector.dart`

---

## Summary

**Recommended Approach**:
1. Extend `user_category_usage` table with `last_used_at` and `use_count` columns
2. Update usage after expense save (fire-and-forget)
3. Query with LEFT JOIN to include virgin categories (ordered alphabetically at end)
4. Use composite index `(user_id, last_used_at DESC)` for efficient sorting
5. Track per-user (not per-group) for personalization
6. Add Drift table for offline MRU support

**Complexity**: Low-Medium (extends existing infrastructure)
**Performance**: Excellent (indexed queries, minimal overhead)
**Maintainability**: High (follows existing patterns, clear separation of concerns)

This approach balances simplicity, performance, and user experience while maintaining compatibility with the existing codebase architecture.
