import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

QueryExecutor openOfflineConnection() => LazyDatabase(() async {
      const storage = FlutterSecureStorage();
      var key = await storage.read(key: 'drift_encryption_key');
      if (key == null) {
        key = base64
            .encode(List.generate(32, (_) => Random.secure().nextInt(256)));
        await storage.write(key: 'drift_encryption_key', value: key);
      }
      final folder = await getApplicationDocumentsDirectory();
      return NativeDatabase.createInBackground(
        File(p.join(folder.path, 'offline_expenses.db')),
        setup: (db) {
          db.execute('PRAGMA key = "$key"');
          db.execute('PRAGMA cipher_page_size = 4096');
          db.execute('PRAGMA kdf_iter = 64000');
          db.execute('PRAGMA journal_mode = WAL');
          db.execute('PRAGMA synchronous = NORMAL');
          db.execute('PRAGMA temp_store = MEMORY');
        },
      );
    });
