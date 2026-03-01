import 'package:drift/drift.dart';
import '../drift/tables/category_usage_table.dart';
import '../../../features/offline/data/local/offline_database.dart';

part 'category_usage_dao.g.dart';

/// Data Access Object for user_category_usage table operations.
///
/// Provides MRU (Most Recently Used) tracking for category selection.
/// Feature: 001-widget-category-fixes (User Story 3)
@DriftAccessor(tables: [UserCategoryUsage])
class CategoryUsageDao extends DatabaseAccessor<OfflineDatabase>
    with _$CategoryUsageDaoMixin {
  CategoryUsageDao(super.db);

  // =========================================================================
  // CREATE / UPDATE
  // =========================================================================

  /// Insert or update category usage tracking
  /// Called when an expense is saved with a category
  Future<void> upsertCategoryUsage({
    required String userId,
    required String categoryId,
    required DateTime lastUsedAt,
  }) async {
    // Try to find existing record
    final existing = await (select(userCategoryUsage)
          ..where((tbl) =>
              tbl.userId.equals(userId) & tbl.categoryId.equals(categoryId)))
        .getSingleOrNull();

    if (existing != null) {
      // Update existing record
      await (update(userCategoryUsage)
            ..where((tbl) => tbl.id.equals(existing.id)))
          .write(
        UserCategoryUsageCompanion(
          lastUsedAt: Value(lastUsedAt),
          useCount: Value(existing.useCount + 1),
          isVirgin: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } else {
      // Insert new record
      await into(userCategoryUsage).insert(
        UserCategoryUsageCompanion(
          id: Value(_generateUuid()),
          userId: Value(userId),
          categoryId: Value(categoryId),
          lastUsedAt: Value(lastUsedAt),
          useCount: const Value(1),
          isVirgin: const Value(false),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  /// Batch insert category usage records (for sync from Supabase)
  Future<void> batchInsertCategoryUsage(
      List<UserCategoryUsageCompanion> entries) {
    return batch((batch) {
      batch.insertAll(
        userCategoryUsage,
        entries,
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  // =========================================================================
  // READ
  // =========================================================================

  /// Get all category usage records for a user
  Future<List<CategoryUsageData>> getCategoryUsageByUser(String userId) {
    return (select(userCategoryUsage)
          ..where((tbl) => tbl.userId.equals(userId)))
        .get();
  }

  /// Get MRU-ordered category IDs for a user
  /// Returns list of category IDs sorted by most recently used
  /// Virgin categories (lastUsedAt == NULL) appear last
  Future<List<String>> getMRUCategoryIds(String userId) async {
    final query = select(userCategoryUsage)
      ..where((tbl) => tbl.userId.equals(userId))
      ..orderBy([
        (tbl) => OrderingTerm(
              expression: tbl.lastUsedAt,
              mode: OrderingMode.desc,
              nulls: NullsOrder.last,
            ),
      ]);

    final results = await query.get();
    return results.map((usage) => usage.categoryId).toList();
  }

  /// Get category usage for a specific category
  Future<CategoryUsageData?> getCategoryUsage(
    String userId,
    String categoryId,
  ) {
    return (select(userCategoryUsage)
          ..where((tbl) =>
              tbl.userId.equals(userId) & tbl.categoryId.equals(categoryId)))
        .getSingleOrNull();
  }

  /// Check if a category has been used (not virgin)
  Future<bool> isCategoryUsed(String userId, String categoryId) async {
    final usage = await getCategoryUsage(userId, categoryId);
    return usage != null && !usage.isVirgin;
  }

  // =========================================================================
  // DELETE
  // =========================================================================

  /// Delete all category usage records for a user
  /// Used when user leaves group or resets preferences
  Future<int> deleteCategoryUsageByUser(String userId) {
    return (delete(userCategoryUsage)
          ..where((tbl) => tbl.userId.equals(userId)))
        .go();
  }

  /// Delete specific category usage record
  Future<int> deleteCategoryUsage(String userId, String categoryId) {
    return (delete(userCategoryUsage)
          ..where((tbl) =>
              tbl.userId.equals(userId) & tbl.categoryId.equals(categoryId)))
        .go();
  }

  // =========================================================================
  // UTILITIES
  // =========================================================================

  /// Generate UUID for new records
  String _generateUuid() {
    // Simple UUID v4 generation
    // In production, use uuid package
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = timestamp.toString().hashCode.abs();
    return 'local-$timestamp-$random';
  }
}
