import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:family_expense_tracker/features/offline/data/datasources/offline_expense_local_datasource.dart';
import 'package:family_expense_tracker/features/offline/data/local/offline_database.dart';
import 'package:flutter_test/flutter_test.dart';

// Issue #67: receipts attached while offline are kept on the device and
// linked to the queued expense. An expense is never lost because of a receipt.

const _userId = 'user-1';

final _pdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 9, 9]);

void main() {
  late OfflineDatabase db;
  late Directory dir;
  late OfflineExpenseLocalDataSourceImpl offline;

  setUp(() async {
    db = OfflineDatabase.forTesting(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('receipts_test');
    offline = OfflineExpenseLocalDataSourceImpl(
      database: db,
      receiptsDirectory: () async => dir,
    );
  });

  tearDown(() async {
    await db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<String> create({Uint8List? receipt}) async {
    final created = await offline.createOfflineExpense(
      userId: _userId,
      amount: 12,
      date: DateTime(2026, 10, 1),
      categoryId: 'cat-1',
      receiptBytes: receipt,
    );
    return created.id;
  }

  Future<OfflineExpense> row(String id) => (db.select(db.offlineExpenses)
        ..where((t) => t.id.equals(id)))
      .getSingle();

  test('PDF offline: file saved as .pdf with identical content, path in row and queue',
      () async {
    final id = await create(receipt: _pdf);

    final r = await row(id);
    expect(r.localReceiptPath, isNotNull);
    expect(r.localReceiptPath!.endsWith('$id.pdf'), isTrue);
    expect(await File(r.localReceiptPath!).readAsBytes(), _pdf);
    expect(r.receiptImageSize, _pdf.length);

    final queue = await (db.select(db.syncQueueItems)
          ..where((t) => t.entityId.equals(id)))
        .get();
    expect(queue, hasLength(1));
    final payload = jsonDecode(queue.single.payload) as Map<String, dynamic>;
    expect(payload['local_receipt_path'], r.localReceiptPath);
  });

  test('expense without receipt keeps localReceiptPath null', () async {
    final id = await create();
    expect((await row(id)).localReceiptPath, isNull);
  });

  test('receipt write failure: expense and queue item are saved anyway', () async {
    // A file where the directory should be makes the write fail.
    final blocker = File('${dir.path}${Platform.pathSeparator}blocker');
    await blocker.writeAsString('x');
    final failing = OfflineExpenseLocalDataSourceImpl(
      database: db,
      receiptsDirectory: () async => Directory(blocker.path),
    );

    final created = await failing.createOfflineExpense(
      userId: _userId,
      amount: 5,
      date: DateTime(2026, 10, 1),
      categoryId: 'cat-1',
      receiptBytes: _pdf,
    );

    final r = await row(created.id);
    expect(r.localReceiptPath, isNull);
    final queue = await (db.select(db.syncQueueItems)
          ..where((t) => t.entityId.equals(created.id)))
        .get();
    expect(queue, hasLength(1));
  });

  test('discardUnsyncedExpense deletes the local receipt file', () async {
    final id = await create(receipt: _pdf);
    final path = (await row(id)).localReceiptPath!;
    expect(await File(path).exists(), isTrue);

    final discarded =
        await offline.discardUnsyncedExpense(expenseId: id, userId: _userId);

    expect(discarded, isTrue);
    expect(await File(path).exists(), isFalse);
  });

  test('getExpensesWithPendingReceipt returns only completed rows with a path',
      () async {
    final withReceiptPending = await create(receipt: _pdf);
    final withReceiptDone = await create(receipt: _pdf);
    final withoutReceipt = await create();
    await offline.updateSyncStatus(withReceiptDone, 'completed');
    await offline.updateSyncStatus(withoutReceipt, 'completed');

    final result = await offline.getExpensesWithPendingReceipt(_userId);

    expect(result.map((e) => e.id), [withReceiptDone]);
    expect(result.map((e) => e.id), isNot(contains(withReceiptPending)));
  });

  test('clearLocalReceiptPath clears the path only', () async {
    final id = await create(receipt: _pdf);
    final path = (await row(id)).localReceiptPath!;

    await offline.clearLocalReceiptPath(id);

    final r = await row(id);
    expect(r.localReceiptPath, isNull);
    expect(r.amount, 12);
    expect(await File(path).exists(), isTrue);
  });
}
