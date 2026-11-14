import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/receipt_file_type.dart';

/// Device receipt files retain their existing paths across app upgrades.
class ReceiptStorage {
  ReceiptStorage._();

  static Future<String> write(String id, Uint8List bytes,
      {String? directory}) async {
    final filename = '$id.${ReceiptFileType.detect(bytes).extension}';
    final folder = Directory(directory ??
        p.join((await getApplicationDocumentsDirectory()).path,
            'pending_receipts'));
    await folder.create(recursive: true);
    final file = File(p.join(folder.path, filename));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<Uint8List?> read(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  static Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
