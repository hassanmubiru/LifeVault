import 'package:sqflite/sqflite.dart';

class Collection {
  final String id;
  final String name;
  final String? description;
  final String? color;
  final int documentCount;
  final int createdAt;
  final int updatedAt;

  Collection({
    required this.id,
    required this.name,
    this.description,
    this.color,
    this.documentCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'color': color,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory Collection.fromMap(Map<String, dynamic> map) {
    return Collection(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      color: map['color'] as String?,
      documentCount: map['document_count'] as int? ?? 0,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
    );
  }

  Collection copyWith({
    String? id,
    String? name,
    String? description,
    String? color,
    int? documentCount,
    int? createdAt,
    int? updatedAt,
  }) {
    return Collection(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      color: color ?? this.color,
      documentCount: documentCount ?? this.documentCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class CollectionService {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = p.join(await getDatabasesPath(), 'lifevault_collections.db');
    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE collections (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT,
            color TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_collections_name ON collections(name)');
      },
    );
  }

  Future<List<Collection>> getAllCollections() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT c.*, COUNT(d.id) as document_count
      FROM collections c
      LEFT JOIN documents d ON d.collection_id = c.id AND d.deleted_at IS NULL
      GROUP BY c.id
      ORDER BY c.name ASC
    ''');
    return maps.map((m) => Collection.fromMap(m)).toList();
  }

  Future<Collection?> getCollection(String id) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT c.*, COUNT(d.id) as document_count
      FROM collections c
      LEFT JOIN documents d ON d.collection_id = c.id AND d.deleted_at IS NULL
      WHERE c.id = ?
      GROUP BY c.id
    ''', [id]);
    if (maps.isEmpty) return null;
    return Collection.fromMap(maps.first);
  }

  Future<void> createCollection(Collection collection) async {
    final db = await database;
    await db.insert('collections', collection.toMap());
  }

  Future<void> updateCollection(Collection collection) async {
    final db = await database;
    await db.update(
      'collections',
      collection.toMap(),
      where: 'id = ?',
      whereArgs: [collection.id],
    );
  }

  Future<void> deleteCollection(String id) async {
    final db = await database;
    await db.delete('collections', where: 'id = ?', whereArgs: [id]);
    await db.update(
      'documents',
      {'collection_id': null, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'collection_id = ?',
      whereArgs: [id],
    );
  }

  Future<void> assignDocumentToCollection(String documentId, String? collectionId) async {
    final db = await database;
    await db.update(
      'documents',
      {'collection_id': collectionId, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [documentId],
    );
  }
}