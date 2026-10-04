import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:family_expense_tracker/features/offline/data/datasources/offline_expense_local_datasource.dart';
import 'package:family_expense_tracker/features/offline/data/local/offline_database.dart';
import 'package:family_expense_tracker/features/offline/domain/services/batch_sync_service.dart';
import 'package:family_expense_tracker/features/offline/domain/services/sync_queue_processor.dart';
import 'package:flutter_test/flutter_test.dart';

// Issue #67: receipts saved offline are uploaded after the create succeeded,
// and a failed upload never re-queues or duplicates the expense.

const _userId = 'user-1';
final _pdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 7]);

class _FakeBatch implements BatchSyncService {
  bool createSucceeds = true;
  Object? uploadError;
  int createCalls = 0;
  int uploadCalls = 0;
  final List<String> uploadedIds = [];

  @override
  Future<Map<String, SyncItemResult>> batchCreateExpenses(
    List<SyncQueueItem> items,
  ) async {
    createCalls += items.length;
    return {
      for (final i in items)
        i.entityId: SyncItemResult(
          id: i.entityId,
          success: createSucceeds,
          errorMessage: createSucceeds ? null : 'boom',
        ),
    };
  }

  @override
  Future<String> uploadPendingReceipt({
    required String expenseId,
    required String localPath,
  }) async {
    uploadCalls++;
    if (uploadError != null) throw uploadError!;
    uploadedIds.add(expenseId);
    return '$_userId/$expenseId.pdf';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late OfflineDatabase db;
  late Directory dir;
  late OfflineExpenseLocalDataSourceImpl local;
  late _FakeBatch batch;
  late SyncQueueProcessor processor;

  setUp(() async {
    db = OfflineDatabase.forTesting(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('receipts_proc_test');
    local = OfflineExpenseLocalDataSourceImpl(
      database: db,
      receiptsDirectory: () async => dir,
    );
    batch = _FakeBatch();
    processor = SyncQueueProcessor(
      localDataSource: local,
      batchSyncService: batch,
      userId: _userId,
    );
  });

  tearDown(() async {
    await db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<String> createWithReceipt() async {
    final e = await local.createOfflineExpense(
      userId: _userId,
      amount: 10,
      date: DateTime(2026, 10, 1),
      categoryId: 'cat-1',
      receiptBytes: _pdf,
    );
    return e.id;
  }

  Future<OfflineExpense> row(String id) => (db.select(db.offlineExpenses)
        ..where((t) => t.id.equals(id)))
      .getSingle();

  Future<int> queueCount(String id) async => (await (db.select(db.syncQueueItems)
            ..where((t) => t.entityId.equals(id)))
          .get())
      .length;

  test('create OK + upload OK: path cleared, file removed, queue empty', () async {
    final id = await createWithReceipt();
    final path = (await row(id)).localReceiptPath!;

    final result = await processor.processQueue();

    expect(result.successful, 1);
    expect(batch.uploadedIds, [id]);
    final r = await row(id);
    expect(r.syncStatus, 'completed');
    expect(r.localReceiptPath, isNull);
    expect(await File(path).exists(), isFalse);
    expect(await queueCount(id), 0);
  });

  test('transient upload error: path kept, no duplicate create, retried', () async {
    final id = await createWithReceipt();
    final path = (await row(id)).localReceiptPath!;
    batch.uploadError = const SocketException('offline');

    final first = await processor.processQueue();

    expect(first.successful, 1);
    expect(first.failed, 0);
    var r = await row(id);
    expect(r.syncStatus, 'completed');
    expect(r.localReceiptPath, path);
    expect(await File(path).exists(), isTrue);
    expect(await queueCount(id), 0);

    // Second sync: no new create, upload retried and now succeeds.
    batch.uploadError = null;
    await processor.processQueue();

    expect(batch.createCalls, 1);
    expect(batch.uploadedIds, [id]);
    r = await row(id);
    expect(r.localReceiptPath, isNull);
  });

  test('permanent upload error: receipt dropped, expense stays', () async {
    final id = await createWithReceipt();
    final path = (await row(id)).localReceiptPath!;
    batch.uploadError = ReceiptUploadPermanentError('too large', 413);

    await processor.processQueue();

    final r = await row(id);
    expect(r.syncStatus, 'completed');
    expect(r.localReceiptPath, isNull);
    expect(await File(path).exists(), isFalse);
  });

  test('missing local file: path cleared, expense stays', () async {
    final id = await createWithReceipt();
    batch.uploadError = ReceiptFileMissing('gone');

    final result = await processor.processQueue();

    expect(result.successful, 1);
    final r = await row(id);
    expect(r.syncStatus, 'completed');
    expect(r.localReceiptPath, isNull);
  });

  test('create failed: upload never attempted, receipt kept', () async {
    final id = await createWithReceipt();
    batch.createSucceeds = false;

    await processor.processQueue();

    expect(batch.uploadCalls, 0);
    final r = await row(id);
    expect(r.syncStatus, isNot('completed'));
    expect(r.localReceiptPath, isNotNull);
    expect(await queueCount(id), 1);
  });
}
