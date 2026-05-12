import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'local_db.dart';

class MemoryCache {
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
        'audio_path': memory['audio_path'] as String?,
        'created_at': memory['created_at'] as String? ?? '',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateFields(
    String id, {
    String? summary,
    String? rawText,
    String? audioPath,
  }) async {
    if (kIsWeb) {
      final row = _webStore[id];
      if (row == null) return;
      if (summary != null) row['summary'] = summary;
      if (rawText != null) row['raw_text'] = rawText;
      if (audioPath != null) row['audio_path'] = audioPath;
      return;
    }
    final db = await LocalDb.instance;
    final values = <String, Object?>{};
    if (summary != null) values['summary'] = summary;
    if (rawText != null) values['raw_text'] = rawText;
    if (audioPath != null) values['audio_path'] = audioPath;
    if (values.isEmpty) return;
    await db.update('memories', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteMemory(String id) async {
    if (kIsWeb) {
      _webStore.remove(id);
      return;
    }
    final db = await LocalDb.instance;
    await db.delete('memories', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getMemories(
    String userId, {
    int limit = 20,
    String? before,
  }) async {
    if (kIsWeb) {
      var result = _webStore.values
          .where((m) => m['user_id'] == userId)
          .toList()
        ..sort((a, b) => (b['created_at'] as String)
            .compareTo(a['created_at'] as String));
      if (before != null) {
        result = result
            .where((m) => (m['created_at'] as String).compareTo(before) < 0)
            .toList();
      }
      return result.take(limit).toList();
    }
    final db = await LocalDb.instance;
    if (before != null) {
      return db.query(
        'memories',
        where: 'user_id = ? AND created_at < ?',
        whereArgs: [userId, before],
        orderBy: 'created_at DESC',
        limit: limit,
      );
    }
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
