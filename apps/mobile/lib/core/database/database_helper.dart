import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;
  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'lifevault.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE documents (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        type TEXT NOT NULL,
        mime_type TEXT,
        file_path TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        extracted_text TEXT,
        size INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        metadata TEXT
      )
    ''');

    await db.execute('''
      CREATE VIRTUAL TABLE documents_fts USING fts5(
        title, extracted_text, content='documents', content_rowid='rowid'
      )
    ''');

    await db.execute('''
      CREATE TRIGGER documents_ai AFTER INSERT ON documents BEGIN
        INSERT INTO documents_fts(rowid, title, extracted_text) 
        VALUES (new.rowid, new.title, new.extracted_text);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER documents_ad AFTER DELETE ON documents BEGIN
        INSERT INTO documents_fts(documents_fts, rowid, title, extracted_text) 
        VALUES('delete', old.rowid, old.title, old.extracted_text);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER documents_au AFTER UPDATE ON documents BEGIN
        INSERT INTO documents_fts(documents_fts, rowid, title, extracted_text) 
        VALUES('delete', old.rowid, old.title, old.extracted_text);
        INSERT INTO documents_fts(rowid, title, extracted_text) 
        VALUES (new.rowid, new.title, new.extracted_text);
      END
    ''');

    await db.execute('CREATE INDEX idx_documents_created_at ON documents(created_at)');
    await db.execute('CREATE INDEX idx_documents_type ON documents(type)');
    await db.execute('CREATE INDEX idx_documents_hash ON documents(content_hash)');
  }
}
