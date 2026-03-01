import 'package:drift/drift.dart';

/// Drift table definition for user_category_usage
///
/// Stores MRU (Most Recently Used) tracking for categories per user.
/// Syncs with Supabase user_category_usage table for cross-device consistency.
/// Feature: 001-widget-category-fixes (User Story 3)
@DataClassName('CategoryUsageData')
class UserCategoryUsage extends Table {
  /// Unique identifier (UUID)
  TextColumn get id => text()();

  /// User who uses this category
  TextColumn get userId => text()();

  /// Category being tracked
  TextColumn get categoryId => text()();

  /// Whether category has never been used (virgin state)
  BoolColumn get isVirgin => boolean().withDefault(const Constant(true))();

  /// Timestamp of most recent use in an expense
  /// NULL for virgin categories
  DateTimeColumn get lastUsedAt => dateTime().nullable()();

  /// Total number of times category was used
  IntColumn get useCount => integer().withDefault(const Constant(0))();

  /// Record creation timestamp
  DateTimeColumn get createdAt => dateTime()();

  /// Last update timestamp
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {userId, categoryId}, // Unique constraint on user-category pair
      ];
}
