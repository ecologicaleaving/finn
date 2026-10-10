import 'dart:typed_data';

import 'package:family_expense_tracker/core/utils/receipt_file_type.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _b(List<int> v) => Uint8List.fromList(v);

void main() {
  group('ReceiptFileType.detect', () {
    test('PDF', () {
      final t = ReceiptFileType.detect(_b([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31]));
      expect(t.extension, 'pdf');
      expect(t.contentType, 'application/pdf');
    });

    test('PNG', () {
      final t = ReceiptFileType.detect(_b([0x89, 0x50, 0x4E, 0x47, 0x0D]));
      expect(t.extension, 'png');
      expect(t.contentType, 'image/png');
    });

    test('JPEG', () {
      final t = ReceiptFileType.detect(_b([0xFF, 0xD8, 0xFF, 0xE0]));
      expect(t.extension, 'jpg');
      expect(t.contentType, 'image/jpeg');
    });

    test('WebP', () {
      final t = ReceiptFileType.detect(_b([
        0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, //
      ]));
      expect(t.extension, 'webp');
      expect(t.contentType, 'image/webp');
    });

    test('byte sconosciuti ricadono su jpg', () {
      final t = ReceiptFileType.detect(_b([1, 2, 3, 4, 5, 6]));
      expect(t.extension, 'jpg');
      expect(t.contentType, 'image/jpeg');
    });

    test('input vuoto ricade su jpg', () {
      final t = ReceiptFileType.detect(Uint8List(0));
      expect(t.extension, 'jpg');
    });
  });

  test('isPdfBytes', () {
    expect(ReceiptFileType.isPdfBytes(_b([0x25, 0x50, 0x44, 0x46, 0x2D])), isTrue);
    expect(ReceiptFileType.isPdfBytes(_b([0xFF, 0xD8, 0xFF])), isFalse);
  });

  test('storagePath usa estensione del tipo reale', () {
    final pdf = _b([0x25, 0x50, 0x44, 0x46, 0x2D, 1]);
    expect(ReceiptFileType.storagePath('u1', 'e1', pdf), 'u1/e1.pdf');
    expect(ReceiptFileType.storagePath('u1', 'e1', Uint8List(0)), 'u1/e1.jpg');
  });
}
