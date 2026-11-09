import 'dart:io';
import 'dart:typed_data';

import 'package:family_expense_tracker/shared/services/receipt_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('receipt bytes survive reopening and cleanup preserves other receipts',
      () async {
    final directory = await Directory.systemTemp.createTemp('finn_receipts_');
    addTearDown(() => directory.delete(recursive: true));
    final pdf = Uint8List.fromList('%PDF-1.7\nreceipt'.codeUnits);
    final path = await ReceiptStorage.write('expense-one', pdf,
        directory: directory.path);
    final other = await ReceiptStorage.write('expense-two', pdf,
        directory: directory.path);
    expect(path.endsWith('.pdf'), isTrue);
    expect(await ReceiptStorage.read(path), pdf);
    await ReceiptStorage.delete(path);
    expect(await ReceiptStorage.read(path), isNull);
    expect(await ReceiptStorage.read(other), pdf);
    await ReceiptStorage.delete(path);
  });
}
