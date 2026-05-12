import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class LocalDb {
  static Database? _db;

  static Future<Database> get instance async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final dbPath = p.join(await getDatabasesPath(), 'xiaosui.db');
    return openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE memories (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            raw_text TEXT NOT NULL,
            summary TEXT,
            audio_path TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_mem_user ON memories(user_id)');
        await db.execute('CREATE INDEX idx_mem_created ON memories(created_at)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE memories ADD COLUMN audio_path TEXT');
        }
      },
    );
  }
}
