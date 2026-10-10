import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/exceptions.dart';
import '../../data/datasources/expense_remote_datasource.dart';
import 'expense_provider.dart';

/// Provider for fetching signed receipt image URLs from Supabase storage.
///
/// Takes a receipt path (stored in ExpenseEntity.receiptUrl) and returns
/// a time-limited signed URL that can be used to display the image.
///
/// Example usage:
/// ```dart
/// final signedUrlAsync = ref.watch(receiptImageUrlProvider(expense.receiptUrl!));
/// signedUrlAsync.when(
///   data: (url) => Image.network(url),
///   loading: () => CircularProgressIndicator(),
///   error: (e, _) => ErrorWidget(e),
/// );
/// ```
final receiptImageUrlProvider = FutureProvider.family<String, String>(
  (ref, receiptPath) async {
    if (receiptPath.isEmpty) {
      throw const ServerException(
        'Percorso ricevuta non valido',
        'INVALID_RECEIPT_PATH',
      );
    }

    final dataSource = ref.watch(expenseRemoteDataSourceProvider);

    try {
      final signedUrl = await dataSource.getReceiptUrl(receiptPath: receiptPath);
      return signedUrl;
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(
        'Impossibile caricare la ricevuta: ${e.toString()}',
        'RECEIPT_LOAD_FAILED',
      );
    }
  },
);

/// Provider for fetching receipt image URL for a specific expense.
///
/// This is a convenience provider that combines expense lookup with
/// receipt URL fetching. Returns null if the expense has no receipt.
///
/// Example usage:
/// ```dart
/// final receiptAsync = ref.watch(expenseReceiptProvider(expenseId));
/// receiptAsync.when(
///   data: (url) => url != null ? Image.network(url) : NoReceiptWidget(),
///   loading: () => CircularProgressIndicator(),
///   error: (e, _) => ErrorWidget(e),
/// );
/// ```
final expenseReceiptProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, expenseId) async {
    // First get the expense to check if it has a receipt
    final expenseAsync = await ref.watch(expenseProvider(expenseId).future);

    if (expenseAsync == null) {
      throw const ServerException(
        'Spesa non trovata',
        'EXPENSE_NOT_FOUND',
      );
    }

    // If no receipt URL, return null
    if (!expenseAsync.hasReceipt) {
      return null;
    }

    // Fetch the signed URL for the receipt
    final signedUrl = await ref.watch(
      receiptImageUrlProvider(expenseAsync.receiptUrl!).future,
    );

    return signedUrl;
  },
);

/// Scarica i byte di uno scontrino dallo storage.
///
/// Serve per aprire i PDF (anche quelli storici salvati come '.jpg').
final receiptFileBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, receiptPath) async {
  final dataSource = ref.watch(expenseRemoteDataSourceProvider);
  return dataSource.downloadReceipt(receiptPath: receiptPath);
});
