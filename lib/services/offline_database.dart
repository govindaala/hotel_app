// lib/services/offline_database.dart
import 'dart:convert';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Durable local queue for POS transactions created while the cloud is unavailable.
class OfflineDatabase {
  OfflineDatabase._();

  static final OfflineDatabase instance = OfflineDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final root = await getDatabasesPath();
    _database = await openDatabase(
      p.join(root, 'aala_pos_local.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE offline_operations (
            id TEXT PRIMARY KEY,
            store_code TEXT NOT NULL,
            entity TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_offline_operations_store ON offline_operations(store_code, created_at)',
        );
      },
    );
    return _database!;
  }

  String createId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> enqueue({
    required String id,
    required String storeCode,
    required String entity,
    required Map<String, dynamic> payload,
  }) async {
    final db = await database;
    await db.insert(
      'offline_operations',
      {
        'id': id,
        'store_code': storeCode,
        'entity': entity,
        'payload': jsonEncode(payload),
        'created_at': DateTime.now().toIso8601String(),
        'attempts': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> pending(String storeCode) async {
    final db = await database;
    return db.query(
      'offline_operations',
      where: 'store_code = ?',
      whereArgs: [storeCode],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> markSynced(String id) async {
    final db = await database;
    await db.delete('offline_operations', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> recordFailure(String id, Object error) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE offline_operations SET attempts = attempts + 1, last_error = ? WHERE id = ?',
      [error.toString(), id],
    );
  }
}
