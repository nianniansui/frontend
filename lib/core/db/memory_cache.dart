import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'local_db.dart';

class MemoryCache {
  // Web 端用内存 Map，key = id
  static final Map<String, Map<String, dynamic>> _webStore = {};

  Future<void> upsertMemory(Map<String, dynamic> memory) async {
    if (kIsWeb) {
      _webStore[memory['id'] as String] = Map.from(memory);
      return;
    }
    final db = await LocalDb.instance;
    await db.insert(
      'memories',
      {
        'id': memory['id'] as String,
        'user_id': memory['user_id'] as String? ?? '',
        'raw_text': memory['raw_text'] as String? ?? '',
        'summary': memory['summary'] as String?,
        'created_at': memory['created_at'] as String? ?? '',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getMemories(
    String userId, {
    int limit = 20,
  }) async {
    if (kIsWeb) {
      final result = _webStore.values
          .where((m) => m['user_id'] == userId)
          .toList()
        ..sort((a, b) => (b['created_at'] as String)
            .compareTo(a['created_at'] as String));
      return result.take(limit).toList();
    }
    final db = await LocalDb.instance;
    return db.query(
      'memories',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<void> clearOld(String userId, {int days = 30}) async {
    if (kIsWeb) {
      final cutoff =
          DateTime.now().subtract(Duration(days: days)).toIso8601String();
      _webStore.removeWhere((_, m) =>
          m['user_id'] == userId &&
          (m['created_at'] as String).compareTo(cutoff) < 0);
      return;
    }
    final db = await LocalDb.instance;
    final cutoff =
        DateTime.now().subtract(Duration(days: days)).toIso8601String();
    await db.delete(
      'memories',
      where: 'user_id = ? AND created_at < ?',
      whereArgs: [userId, cutoff],
    );
  }
}
