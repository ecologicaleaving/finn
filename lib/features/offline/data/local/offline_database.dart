import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// Budget management tables
import '../../../../core/database/drift/tables/income_sources_table.dart';
import '../../../../core/database/drift/tables/savings_goals_table.dart';
import '../../../../core/database/drift/tables/group_expense_assignments_table.dart';
import '../../../budgets/domain/entities/income_source_entity.dart';

// Recurring expenses tables
import '../../../../core/database/drift/tables/recurring_expenses_table.dart';
import '../../../../core/database/drift/tables/recurring_expense_instances_table.dart';

// Enums
import '../../../../core/enums/recurrence_frequency.dart';
import '../../../../core/enums/reimbursement_status.dart';

part 'offline_database.g.dart';

// Table 1: OfflineExpenses
// Stores expenses created or modified while offline
@TableIndex(name: 'offline_expenses_user_status_idx', columns: {#userId, #syncStatus})
@TableIndex(name: 'offline_expenses_user_created_idx', columns: {#userId, #localCreatedAt})
class OfflineExpenses extends Table {
  // Primary Key
  TextColumn get id => text()(); // UUID v4 generated client-side

  // User Isolation (FR-022)
  TextColumn get userId => text()(); // References auth.users(id)

  // Expense Fields (same as server expense model)
  RealColumn get amount => real()(); // Decimal amount
  DateTimeColumn get date => dateTime()(); // Transaction date
  TextColumn get categoryId => text()(); // References expense_categories(id)
  TextColumn get merchant => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isGroupExpense => boolean().withDefault(const Constant(true))();

  // Reimbursement tracking (Feature 012-expense-improvements)
  TextColumn get reimbursementStatus => text()
      .withDefault(const Constant('none'))
      .check(reimbursementStatus.isIn(['none', 'reimbursable', 'reimbursed']))();
  DateTimeColumn get reimbursedAt => dateTime().nullable()();

  // Recurring expense tracking (Feature 013-recurring-expenses)
  TextColumn get recurringExpenseId => text().nullable()(); // References recurring_expenses(id)
  BoolColumn get isRecurringInstance => boolean().withDefault(const Constant(false))(); // Whether this expense was auto-generated from a template

  // Receipt Image Reference (if uploaded offline)
  TextColumn get localReceiptPath => text().nullable()(); // Local file path
  IntColumn get receiptImageSize => integer().nullable()(); // Bytes, for SC-012 tracking

  // Sync Metadata
  TextColumn get syncStatus => text()(); // 'pending', 'syncing', 'completed', 'failed', 'conflict'
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSyncAttemptAt => dateTime().nullable()();
  TextColumn get syncErrorMessage => text().nullable()();

  // Conflict Resolution
  BoolColumn get hasConflict => boolean().withDefault(const Constant(false))();
  TextColumn get serverVersionData => text().nullable()(); // JSON of server version if conflict

  // Timestamps
  DateTimeColumn get localCreatedAt => dateTime()(); // Client-side creation time
  DateTimeColumn get localUpdatedAt => dateTime()(); // Client-side last modification

  @override
  Set<Column> get primaryKey => {id};
}

// Table 2: SyncQueueItems
// Manages ordered queue of sync operations
@TableIndex(name: 'sync_queue_user_status_idx', columns: {#userId, #syncStatus, #nextRetryAt})
@TableIndex(name: 'sync_queue_created_idx', columns: {#createdAt})
class SyncQueueItems extends Table {
  // Primary Key
  IntColumn get id => integer().autoIncrement()();

  // User Isolation
  TextColumn get userId => text()();

  // Operation Details
  TextColumn get operation => text()(); // 'create', 'update', 'delete'
  TextColumn get entityType => text()(); // 'expense', 'expense_image'
  TextColumn get entityId => text()(); // UUID of offline expense or server expense ID
  TextColumn get payload => text()(); // JSON serialized data for the operation

  // Sync Metadata
  TextColumn get syncStatus => text()(); // 'pending', 'syncing', 'completed', 'failed'
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextRetryAt => dateTime().nullable()(); // For exponential backoff
  TextColumn get errorMessage => text().nullable()();

  // Priority & Ordering
  IntColumn get priority => integer().withDefault(const Constant(0))(); // Higher = more urgent
  DateTimeColumn get createdAt => dateTime()();
}

// Table 3: OfflineExpenseImages
// Stores compressed receipt images until synced
@TableIndex(name: 'offline_images_expense_idx', columns: {#expenseId})
@TableIndex(name: 'offline_images_user_idx', columns: {#userId, #uploadStatus})
class OfflineExpenseImages extends Table {
  // Primary Key
  IntColumn get id => integer().autoIncrement()();

  // Relationships
  TextColumn get expenseId => text()(); // References offline_expenses(id) or synced server expense ID
  TextColumn get userId => text()();

  // Image Data
  BlobColumn get compressedImageData => blob()(); // Compressed JPEG bytes
  IntColumn get originalSizeBytes => integer()();
  IntColumn get compressedSizeBytes => integer()();
  RealColumn get compressionRatio => real()(); // originalSize / compressedSize

  // Upload Metadata
  TextColumn get uploadStatus => text()(); // 'pending', 'uploading', 'completed', 'failed'
  TextColumn get storagePath => text().nullable()(); // Supabase storage path after upload
  IntColumn get uploadRetryCount => integer().withDefault(const Constant(0))();
  TextColumn get uploadErrorMessage => text().nullable()();

  // Timestamps
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get uploadedAt => dateTime().nullable()();
}

// Table 4: SyncConflicts (Optional - for User Story 4 P4)
// Tracks conflicts detected during sync for user review
@TableIndex(name: 'sync_conflicts_user_idx', columns: {#userId, #resolvedAt})
class SyncConflicts extends Table {
  // Primary Key
  IntColumn get id => integer().autoIncrement()();

  // Relationships
  TextColumn get userId => text()();
  TextColumn get expenseId => text()(); // The conflicted expense ID

  // Conflict Data
  TextColumn get localVersionData => text()(); // JSON of local version
  TextColumn get serverVersionData => text()(); // JSON of server version
  TextColumn get conflictType => text()(); // 'update_conflict', 'delete_conflict'

  // Resolution
  TextColumn get resolutionAction => text().nullable()(); // 'accepted_server', 'created_new', 'discarded'
  DateTimeColumn get resolvedAt => dateTime().nullable()();

  // Timestamps
  DateTimeColumn get detectedAt => dateTime()();
}

// Table 5: CachedCategories
// Cache expense categories for offline access
@TableIndex(name: 'cached_categories_group_idx', columns: {#groupId})
class CachedCategories extends Table {
  // Primary Key
  TextColumn get id => text()(); // Category ID from server

  // Category Data
  TextColumn get name => text()();
  TextColumn get groupId => text()();
  BoolColumn get isDefault => boolean()();
  TextColumn get createdBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  // Cache Metadata
  DateTimeColumn get cachedAt => dateTime()(); // When this was cached

  @override
  Set<Column> get primaryKey => {id};
}

// Database Definition
@DriftDatabase(tables: [
  OfflineExpenses,
  SyncQueueItems,
  OfflineExpenseImages,
  SyncConflicts,
  CachedCategories,
  // Budget management tables
  IncomeSources,
  SavingsGoals,
  GroupExpenseAssignments,
  // Recurring expenses tables
  RecurringExpenses,
  RecurringExpenseInstances,
])
class OfflineDatabase extends _$OfflineDatabase {
  OfflineDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        // Add CachedCategories table for offline category caching
        await m.createTable(cachedCategories);
      }
      if (from < 3) {
        // Add budget management tables
        await m.createTable(incomeSources);
        await m.createTable(savingsGoals);
        await m.createTable(groupExpenseAssignments);
      }
      if (from < 4) {
        // Add recurring expenses tables (Feature 013)
        await m.createTable(recurringExpenses);
        await m.createTable(recurringExpenseInstances);

        // Add recurring expense fields to OfflineExpenses
        await m.addColumn(offlineExpenses, offlineExpenses.recurringExpenseId);
        await m.addColumn(offlineExpenses, offlineExpenses.isRecurringInstance);
      }
    },
  );

  // Helper method to open encrypted connection
  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      // Get encryption key from secure storage
      final secureStorage = const FlutterSecureStorage();
      String? key = await secureStorage.read(key: 'drift_encryption_key');

      if (key == null) {
        // Generate new 32-byte encryption key
        key = base64.encode(
          List<int>.generate(32, (i) => Random.secure().nextInt(256)),
        );
        await secureStorage.write(key: 'drift_encryption_key', value: key);
      }

      // Get database path
      final dbPath = await _getDatabasePath();
      final file = File(dbPath);

      // Create encrypted database with SQLCipher
      return NativeDatabase.createInBackground(
        file,
        setup: (rawDb) {
          // Set encryption key
          rawDb.execute('PRAGMA key = "$key"');
          // SQLCipher configuration for performance and security
          rawDb.execute('PRAGMA cipher_page_size = 4096');
          rawDb.execute('PRAGMA kdf_iter = 64000');
          // Performance optimizations
          rawDb.execute('PRAGMA journal_mode = WAL');
          rawDb.execute('PRAGMA synchronous = NORMAL');
          rawDb.execute('PRAGMA temp_store = MEMORY');
        },
      );
    });
  }

  static Future<String> _getDatabasePath() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    return p.join(dbFolder.path, 'offline_expenses.db');
  }
}
