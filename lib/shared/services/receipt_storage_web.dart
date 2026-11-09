import 'dart:typed_data';

import 'package:hive/hive.dart';

import '../../core/utils/receipt_file_type.dart';

/// Browser receipts persist in IndexedDB until their upload has succeeded.
class ReceiptStorage {
  ReceiptStorage._();

  // IndexedDB restores lists without Dart's generic element type metadata.
  // Check their integer elements when reading instead of casting the whole box.
  static Future<Box<List>>? _opening;

  static Future<Box<List>> _box() async {
    final existing = _opening;
    if (existing != null) {
      final box = await existing;
      if (box.isOpen) return box;
    }
    final opening = Hive.openBox<List>('receipt_files');
    _opening = opening;
    try {
      return await opening;
    } catch (_) {
      if (identical(_opening, opening)) _opening = null;
      rethrow;
    }
  }

  static Future<String> write(String id, Uint8List bytes,
      {String? directory}) async {
    final key = 'finn-receipt:$id.${ReceiptFileType.detect(bytes).extension}';
    await (await _box()).put(key, bytes.toList());
    return key;
  }

  static Future<Uint8List?> read(String path) async {
    final bytes = (await _box()).get(path);
    return bytes == null ? null : Uint8List.fromList(bytes.cast<int>());
  }

  static Future<void> delete(String path) async {
    await (await _box()).delete(path);
  }
}
