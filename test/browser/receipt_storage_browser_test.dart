@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:family_expense_tracker/shared/services/receipt_storage.dart';
import 'package:hive/hive.dart';
import 'package:test/test.dart';

void main() {
  test(
      'offline PDF persists in IndexedDB after closing and reopening the store',
      () async {
    final id = 'browser-${DateTime.now().microsecondsSinceEpoch}';
    final pdf = Uint8List.fromList('%PDF-1.7\noffline receipt'.codeUnits);
    final first = await ReceiptStorage.write('$id-one', pdf);
    final second = await ReceiptStorage.write('$id-two', pdf);
    addTearDown(() async {
      await ReceiptStorage.delete(first);
      await ReceiptStorage.delete(second);
    });

    expect(first.startsWith('finn-receipt:'), isTrue);
    await Hive.box<List>('receipt_files').close();
    expect(await ReceiptStorage.read(first), pdf);
    await ReceiptStorage.delete(first);
    await Hive.box<List>('receipt_files').close();
    expect(await ReceiptStorage.read(first), isNull);
    expect(await ReceiptStorage.read(second), pdf);
  });
}
