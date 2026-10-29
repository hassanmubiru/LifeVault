import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class Tag {
  final String id;
  final String name;
  final String? color;
  final int documentCount;
  final int createdAt;

  Tag({
    required this.id,
    required this.name,
    this.color,
    this.documentCount = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'color': color,
      'created_at': createdAt,
    };
  }

  factory Tag.fromMap(Map<String, dynamic> map) {
    return Tag(
      id: map['id'] as String,
      name: map['name'] as String,
      color: map['color'] as String?,
      documentCount: map['document_count'] as int? ?? 0,
      createdAt: map['created_at'] as int,
    );
  }
}

class TagService {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = p.join(await getDatabasesPath(), 'lifevault_tags.db');
    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tags (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            color TEXT,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('CREATE TABLE document_tags (document_id TEXT, tag_id TEXT, PRIMARY KEY(document_id, tag_id))');
        await db.execute('CREATE INDEX idx_tags_name ON tags(name)');
      },
    );
  }

  Future<List<Tag>> getAllTags() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT t.*, COUNT(dt.document_id) as document_count
      FROM tags t
      LEFT JOIN document_tags dt ON dt.tag_id = t.id
      GROUP BY t.id
      ORDER BY t.name ASC
    ''');
    return maps.map((m) => Tag.fromMap(m)).toList();
  }

  Future<List<Tag>> getTagsForDocument(String documentId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT t.* FROM tags t
      JOIN document_tags dt ON dt.tag_id = t.id
      WHERE dt.document_id = ?
      ORDER BY t.name ASC
    ''', [documentId]);
    return maps.map((m) => Tag.fromMap(m)).toList();
  }

  Future<void> createTag(Tag tag) async {
    final db = await database;
    await db.insert('tags', tag.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> deleteTag(String id) async {
    final db = await database;
    await db.delete('tags', where: 'id = ?', whereArgs: [id]);
    await db.delete('document_tags', where: 'tag_id = ?', whereArgs: [id]);
  }

  Future<void> addTagToDocument(String documentId, String tagId) async {
    final db = await database;
    await db.insert(
      'document_tags',
      {'document_id': documentId, 'tag_id': tagId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeTagFromDocument(String documentId, String tagId) async {
    final db = await database;
    await db.delete(
      'document_tags',
      where: 'document_id = ? AND tag_id = ?',
      whereArgs: [documentId, tagId],
    );
  }

  Future<List<String>> getDocumentIdsForTag(String tagId) async {
    final db = await database;
    final maps = await db.query(
      'document_tags',
      columns: ['document_id'],
      where: 'tag_id = ?',
      whereArgs: [tagId],
    );
    return maps.map((m) => m['document_id'] as String).toList();
  }
}