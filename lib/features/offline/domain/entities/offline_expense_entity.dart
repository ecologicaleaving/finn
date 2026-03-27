import 'package:equatable/equatable.dart';

/// Offline expense entity - represents an expense created or modified while offline
///
/// This entity is used in the domain layer and is converted to/from Drift models
/// for storage and ExpenseEntity for UI display.
class OfflineExpenseEntity extends Equatable {
  final String id; // UUID v4
  final String userId;
  final double amount;
  final DateTime date;
  final String categoryId;
  final String? merchant;
  final String? notes;
  final bool isGroupExpense;
  
  // Reimbursement v2 fields
  final String? reimbursableToLabel;
  final String? reimbursableToUserId;
  final double? reimbursableAmount;
  final String? reimbursementNote;
  
  final String? localReceiptPath;
  final int? receiptImageSize;
  final String syncStatus; // 'pending', 'syncing', 'completed', 'failed', 'conflict'
  final int retryCount;
  final DateTime? lastSyncAttemptAt;
  final String? syncErrorMessage;
  final bool hasConflict;
  final String? serverVersionData;
  final DateTime localCreatedAt;
  final DateTime localUpdatedAt;

  const OfflineExpenseEntity({
    required this.id,
    required this.userId,
    required this.amount,
    required this.date,
    required this.categoryId,
    this.merchant,
    this.notes,
    required this.isGroupExpense,
    this.reimbursableToLabel,
    this.reimbursableToUserId,
    this.reimbursableAmount,
    this.reimbursementNote,
    this.localReceiptPath,
    this.receiptImageSize,
    required this.syncStatus,
    this.retryCount = 0,
    this.lastSyncAttemptAt,
    this.syncErrorMessage,
    this.hasConflict = false,
    this.serverVersionData,
    required this.localCreatedAt,
    required this.localUpdatedAt,
  });

  /// Create a copy with updated fields
  OfflineExpenseEntity copyWith({
    String? id,
    String? userId,
    double? amount,
    DateTime? date,
    String? categoryId,
    String? merchant,
    String? notes,
    bool? isGroupExpense,
    String? reimbursableToLabel,
    String? reimbursableToUserId,
    double? reimbursableAmount,
    String? reimbursementNote,
    String? localReceiptPath,
    int? receiptImageSize,
    String? syncStatus,
    int? retryCount,
    DateTime? lastSyncAttemptAt,
    String? syncErrorMessage,
    bool? hasConflict,
    String? serverVersionData,
    DateTime? localCreatedAt,
    DateTime? localUpdatedAt,
  }) {
    return OfflineExpenseEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      categoryId: categoryId ?? this.categoryId,
      merchant: merchant ?? this.merchant,
      notes: notes ?? this.notes,
      isGroupExpense: isGroupExpense ?? this.isGroupExpense,
      reimbursableToLabel: reimbursableToLabel ?? this.reimbursableToLabel,
      reimbursableToUserId: reimbursableToUserId ?? this.reimbursableToUserId,
      reimbursableAmount: reimbursableAmount ?? this.reimbursableAmount,
      reimbursementNote: reimbursementNote ?? this.reimbursementNote,
      localReceiptPath: localReceiptPath ?? this.localReceiptPath,
      receiptImageSize: receiptImageSize ?? this.receiptImageSize,
      syncStatus: syncStatus ?? this.syncStatus,
      retryCount: retryCount ?? this.retryCount,
      lastSyncAttemptAt: lastSyncAttemptAt ?? this.lastSyncAttemptAt,
      syncErrorMessage: syncErrorMessage ?? this.syncErrorMessage,
      hasConflict: hasConflict ?? this.hasConflict,
      serverVersionData: serverVersionData ?? this.serverVersionData,
      localCreatedAt: localCreatedAt ?? this.localCreatedAt,
      localUpdatedAt: localUpdatedAt ?? this.localUpdatedAt,
    );
  }

  /// Check if this expense is pending sync
  bool get isPending => syncStatus == 'pending' || syncStatus == 'failed';

  /// Check if this expense is currently syncing
  bool get isSyncing => syncStatus == 'syncing';

  /// Check if this expense has been synced
  bool get isSynced => syncStatus == 'completed';

  /// Convert to JSON for sync queue payload
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'amount': amount,
      'date': date.toIso8601String(),
      'category_id': categoryId,
      'merchant': merchant,
      'notes': notes,
      'is_group_expense': isGroupExpense,
      'created_at': localCreatedAt.toIso8601String(),
      'local_updated_at': localUpdatedAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        amount,
        date,
        categoryId,
        merchant,
        notes,
        isGroupExpense,
        localReceiptPath,
        receiptImageSize,
        syncStatus,
        retryCount,
        lastSyncAttemptAt,
        syncErrorMessage,
        hasConflict,
        serverVersionData,
        localCreatedAt,
        localUpdatedAt,
      ];
}
