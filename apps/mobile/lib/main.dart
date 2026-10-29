import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

final documentsProvider = StateNotifierProvider<DocumentsNotifier, List<Document>>((ref) {
  return DocumentsNotifier();
});

class Document {
  final String id;
  final String title;
  final String type;
  final String filePath;
  final int size;
  final int createdAt;
  final int updatedAt;
  final String? mimeType;
  final String contentHash;
  final String? extractedText;
  final String? metadata;

  Document({
    required this.id,
    required this.title,
    required this.type,
    required this.filePath,
    required this.size,
    required this.createdAt,
    required this.updatedAt,
    this.mimeType,
    required this.contentHash,
    this.extractedText,
    this.metadata,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'type': type,
      'mime_type': mimeType,
      'file_path': filePath,
      'content_hash': contentHash,
      'extracted_text': extractedText,
      'size': size,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'metadata': metadata,
    };
  }

  factory Document.fromMap(Map<String, dynamic> map) {
    return Document(
      id: map['id'] as String,
      title: map['title'] as String,
      type: map['type'] as String,
      filePath: map['file_path'] as String,
      size: map['size'] as int,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
      mimeType: map['mime_type'] as String?,
      contentHash: map['content_hash'] as String,
      extractedText: map['extracted_text'] as String?,
      metadata: map['metadata'] as String?,
    );
  }
}

class DocumentsNotifier extends StateNotifier<List<Document>> {
  DocumentsNotifier() : super([]) {
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('documents', orderBy: 'created_at DESC');
    state = maps.map((m) => Document.fromMap(m)).toList();
  }

  Future<void> importDocument() async {
    try {
      const XTypeGroup typeGroup = XTypeGroup(
        label: 'Documents',
        extensions: ['pdf', 'txt', 'jpg', 'jpeg', 'png', 'gif', 'bmp', 'doc', 'docx'],
      );

      final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);

      if (file != null) {
        final title = file.name;
        final extension = p.extension(file.name).toLowerCase();
        final mimeType = _getMimeType(extension);
        final size = await file.length();

        final sourceFile = File(file.path);
        final storageService = FileStorageService();
        final savedPath = await storageService.saveFile(sourceFile, title);

        final importService = DocumentImportService();
        final contentHash = await importService.calculateHash(File(savedPath));

        final now = DateTime.now().millisecondsSinceEpoch;

        final db = await DatabaseHelper.instance.database;
        final docId = const Uuid().v4();

        await db.insert('documents', {
          'id': docId,
          'title': title,
          'type': extension.replaceFirst('.', ''),
          'mime_type': mimeType,
          'file_path': savedPath,
          'content_hash': contentHash,
          'extracted_text': null,
          'size': size,
          'created_at': now,
          'updated_at': now,
          'metadata': '{}',
        });

        await db.execute(
          "INSERT INTO documents_fts(rowid, title, extracted_text) VALUES ((SELECT rowid FROM documents WHERE id = ?), ?, ?)",
          [docId, title, title],
        );

        await _loadDocuments();
      }
    } catch (e, stackTrace) {
      debugPrint('Error importing document: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  Future<void> deleteDocument(String id) async {
    try {
      final db = await DatabaseHelper.instance.database;

      final docs = await db.query('documents', where: 'id = ?', whereArgs: [id]);
      if (docs.isNotEmpty) {
        final filePath = docs.first['file_path'] as String?;
        if (filePath != null) {
          final storageService = FileStorageService();
          await storageService.deleteFile(filePath);
        }
      }

      await db.delete('documents', where: 'id = ?', whereArgs: [id]);

      await _loadDocuments();
    } catch (e) {
      debugPrint('Error deleting document: $e');
    }
  }

  Future<List<Document>> searchDocuments(String query) async {
    if (query.isEmpty) return state;

    final db = await DatabaseHelper.instance.database;
    final searchResults = await db.rawQuery('''
      SELECT d.* FROM documents d
      JOIN documents_fts fts ON d.rowid = fts.rowid
      WHERE documents_fts MATCH ? AND d.deleted_at IS NULL
      ORDER BY rank
    ''', ['$query*']);

    return searchResults.map((m) => Document.fromMap(m)).toList();
  }

  String _getMimeType(String extension) {
    switch (extension) {
      case '.pdf': return 'application/pdf';
      case '.txt': return 'text/plain';
      case '.jpg': return 'image/jpeg';
      case '.jpeg': return 'image/jpeg';
      case '.png': return 'image/png';
      case '.gif': return 'image/gif';
      case '.doc': return 'application/msword';
      case '.docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default: return 'application/octet-stream';
    }
  }
}

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
    String path = p.join(await getDatabasesPath(), 'lifevault.db');
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

class FileStorageService {
  Future<Directory> get _docsDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final docsDir = Directory(p.join(appDir.path, 'lifevault_docs'));
    if (!await docsDir.exists()) {
      await docsDir.create(recursive: true);
    }
    return docsDir;
  }

  Future<String> saveFile(File file, String originalName) async {
    final docsDir = await _docsDir;
    final ext = p.extension(originalName);
    final fileName = '${const Uuid().v4()}$ext';
    final targetPath = p.join(docsDir.path, fileName);
    await file.copy(targetPath);
    return targetPath;
  }

  Future<File> getFile(String path) async {
    return File(path);
  }

  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class DocumentImportService {
  Future<String> calculateHash(File file) async {
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  bool isSupportedType(String extension) {
    const supported = ['.pdf', '.txt', '.jpg', '.jpeg', '.png', '.gif', '.bmp'];
    return supported.contains(extension.toLowerCase());
  }
}

void main() {
  runApp(const ProviderScope(child: LifeVaultApp()));
}

class LifeVaultApp extends StatelessWidget {
  const LifeVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LifeVault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(documentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LifeVault'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              showSearch(
                context: context,
                delegate: DocumentSearchDelegate(ref),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {},
          ),
        ],
      ),
      body: documents.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No documents yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Tap + to import your first document',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: documents.length,
              itemBuilder: (context, index) {
                final doc = documents[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: _getIcon(doc.type),
                    title: Text(
                      doc.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${_formatSize(doc.size)} - ${_formatDate(doc.createdAt)}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Document'),
                            content: Text('Delete "${doc.title}"?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await ref.read(documentsProvider.notifier).deleteDocument(doc.id);
                        }
                      },
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DocumentDetailScreen(document: doc),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await ref.read(documentsProvider.notifier).importDocument();
        },
        icon: const Icon(Icons.add),
        label: const Text('Import'),
      ),
    );
  }

  Widget _getIcon(String type) {
    IconData icon;
    Color color;

    switch (type) {
      case 'pdf':
        icon = Icons.picture_as_pdf;
        color = Colors.red;
        break;
      case 'txt':
        icon = Icons.description;
        color = Colors.blue;
        break;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        icon = Icons.image;
        color = Colors.green;
        break;
      case 'doc':
      case 'docx':
        icon = Icons.article;
        color = Colors.blueGrey;
        break;
      default:
        icon = Icons.insert_drive_file;
        color = Colors.grey;
    }

    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.1),
      child: Icon(icon, color: color),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(int milliseconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    return '${date.day}/${date.month}/${date.year}';
  }
}

class DocumentSearchDelegate extends SearchDelegate<Document?> {
  final WidgetRef ref;

  DocumentSearchDelegate(this.ref);

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) {
      return const Center(child: Text('Enter a search term'));
    }
    return _buildSearchResults(context);
  }

  Widget _buildSearchResults(BuildContext context) {
    return FutureBuilder<List<Document>>(
      future: ref.read(documentsProvider.notifier).searchDocuments(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final results = snapshot.data ?? [];

        if (results.isEmpty) {
          return const Center(child: Text('No documents found'));
        }

        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final doc = results[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue.withValues(alpha: 0.1),
                child: const Icon(Icons.description, color: Colors.blue),
              ),
              title: Text(doc.title),
              subtitle: Text(doc.type),
              onTap: () {
                close(context, doc);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DocumentDetailScreen(document: doc),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class DocumentDetailScreen extends StatelessWidget {
  final Document document;

  const DocumentDetailScreen({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(document.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Type', document.type.toUpperCase()),
            _buildInfoRow('Size', _formatSize(document.size)),
            _buildInfoRow('Created', _formatDate(document.createdAt)),
            _buildInfoRow('Hash', '${document.contentHash.substring(0, 16)}...'),
            if (document.mimeType != null)
              _buildInfoRow('MIME Type', document.mimeType!),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(int milliseconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
