import 'package:drift/drift.dart' as drift;
import '../../domain/entities/offline_expense_entity.dart';
import '../local/offline_database.dart';

/// Data model that converts between Drift database records and domain entities
class OfflineExpenseModel {
  final OfflineExpense driftData;

  OfflineExpenseModel(this.driftData);

  /// Convert from Drift record to domain entity
  OfflineExpenseEntity toEntity() {
    return OfflineExpenseEntity(
      id: driftData.id,
      userId: driftData.userId,
      amount: driftData.amount,
      date: driftData.date,
      categoryId: driftData.categoryId,
      merchant: driftData.merchant,
      notes: driftData.notes,
      isGroupExpense: driftData.isGroupExpense,
      localReceiptPath: driftData.localReceiptPath,
      receiptImageSize: driftData.receiptImageSize,
      syncStatus: driftData.syncStatus,
      retryCount: driftData.retryCount,
      lastSyncAttemptAt: driftData.lastSyncAttemptAt,
      syncErrorMessage: driftData.syncErrorMessage,
      hasConflict: driftData.hasConflict,
      serverVersionData: driftData.serverVersionData,
      localCreatedAt: driftData.localCreatedAt,
      localUpdatedAt: driftData.localUpdatedAt,
      reimbursableToLabel: driftData.reimbursableToLabel,
      reimbursableToUserId: driftData.reimbursableToUserId,
      reimbursableAmount: driftData.reimbursableAmount,
      reimbursementNote: driftData.reimbursementNote,
    );
  }

  /// Create Drift companion from entity for inserts
  static OfflineExpensesCompanion fromEntity(OfflineExpenseEntity entity) {
    return OfflineExpensesCompanion.insert(
      id: entity.id,
      userId: entity.userId,
      amount: entity.amount,
      date: entity.date,
      categoryId: entity.categoryId,
      merchant: drift.Value(entity.merchant),
      notes: drift.Value(entity.notes),
      isGroupExpense: drift.Value(entity.isGroupExpense),
      localReceiptPath: drift.Value(entity.localReceiptPath),
      receiptImageSize: drift.Value(entity.receiptImageSize),
      syncStatus: entity.syncStatus,
      retryCount: drift.Value(entity.retryCount),
      lastSyncAttemptAt: drift.Value(entity.lastSyncAttemptAt),
      syncErrorMessage: drift.Value(entity.syncErrorMessage),
      hasConflict: drift.Value(entity.hasConflict),
      serverVersionData: drift.Value(entity.serverVersionData),
      localCreatedAt: entity.localCreatedAt,
      localUpdatedAt: entity.localUpdatedAt,
      reimbursableToLabel: drift.Value(entity.reimbursableToLabel),
      reimbursableToUserId: drift.Value(entity.reimbursableToUserId),
      reimbursableAmount: drift.Value(entity.reimbursableAmount),
      reimbursementNote: drift.Value(entity.reimbursementNote),
    );
  }

  /// Create Drift companion from entity for updates
  static OfflineExpensesCompanion toCompanionForUpdate(
    OfflineExpenseEntity entity,
  ) {
    return OfflineExpensesCompanion(
      id: drift.Value(entity.id),
      userId: drift.Value(entity.userId),
      amount: drift.Value(entity.amount),
      date: drift.Value(entity.date),
      categoryId: drift.Value(entity.categoryId),
      merchant: drift.Value(entity.merchant),
      notes: drift.Value(entity.notes),
      isGroupExpense: drift.Value(entity.isGroupExpense),
      localReceiptPath: drift.Value(entity.localReceiptPath),
      receiptImageSize: drift.Value(entity.receiptImageSize),
      syncStatus: drift.Value(entity.syncStatus),
      retryCount: drift.Value(entity.retryCount),
      lastSyncAttemptAt: drift.Value(entity.lastSyncAttemptAt),
      syncErrorMessage: drift.Value(entity.syncErrorMessage),
      hasConflict: drift.Value(entity.hasConflict),
      serverVersionData: drift.Value(entity.serverVersionData),
      localCreatedAt: drift.Value(entity.localCreatedAt),
      localUpdatedAt: drift.Value(entity.localUpdatedAt),
      reimbursableToLabel: drift.Value(entity.reimbursableToLabel),
      reimbursableToUserId: drift.Value(entity.reimbursableToUserId),
      reimbursableAmount: drift.Value(entity.reimbursableAmount),
      reimbursementNote: drift.Value(entity.reimbursementNote),
    );
  }
}
