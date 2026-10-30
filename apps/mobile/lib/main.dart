import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:go_router/go_router.dart';
import 'core/storage/file_storage_service.dart';
import 'core/services/document_import_service.dart';
import 'core/services/collection_service.dart';
import 'core/services/tag_service.dart';
import 'core/services/reminder_service.dart';
import 'core/api/api_client.dart';

final apiClient = ApiClient();

final documentsProvider = StateNotifierProvider<DocumentsNotifier, List<Document>>((ref) {
  return DocumentsNotifier();
});

final collectionsProvider = StateNotifierProvider<CollectionsNotifier, List<Collection>>((ref) {
  return CollectionsNotifier();
});

final tagsProvider = StateNotifierProvider<TagsNotifier, List<Tag>>((ref) {
  return TagsNotifier();
});

final remindersProvider = StateNotifierProvider<RemindersNotifier, List<Reminder>>((ref) {
  return RemindersNotifier();
});

class CollectionsNotifier extends StateNotifier<List<Collection>> {
  final CollectionService _service = CollectionService();
  CollectionsNotifier() : super([]) {
    _loadCollections();
  }

  Future<void> _loadCollections() async {
    state = await _service.getAllCollections();
  }

  Future<void> createCollection(String name, String? description) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final collection = Collection(
      id: const Uuid().v4(),
      name: name,
      description: description,
      createdAt: now,
      updatedAt: now,
    );
    await _service.createCollection(collection);
    await _loadCollections();
  }

  Future<void> deleteCollection(String id) async {
    await _service.deleteCollection(id);
    await _loadCollections();
  }

  Future<void> refresh() async {
    await _loadCollections();
  }
}

class TagsNotifier extends StateNotifier<List<Tag>> {
  final TagService _service = TagService();
  TagsNotifier() : super([]) {
    _loadTags();
  }

  Future<void> _loadTags() async {
    state = await _service.getAllTags();
  }

  Future<void> createTag(String name) async {
    final tag = Tag(
      id: const Uuid().v4(),
      name: name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _service.createTag(tag);
    await _loadTags();
  }

  Future<void> deleteTag(String id) async {
    await _service.deleteTag(id);
    await _loadTags();
  }

  Future<void> refresh() async {
    await _loadTags();
  }
}

class RemindersNotifier extends StateNotifier<List<Reminder>> {
  final ReminderService _service = ReminderService();
  RemindersNotifier() : super([]) {
    _loadReminders();
    _service.startPeriodicCheck();
  }

  Future<void> _loadReminders() async {
    state = await _service.getUpcomingReminders();
  }

  Future<void> createReminder(String documentId, String title, DateTime remindAt, {String? note}) async {
    final reminder = Reminder(
      id: const Uuid().v4(),
      documentId: documentId,
      title: title,
      note: note,
      remindAt: remindAt,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _service.addReminder(reminder);
    await _loadReminders();
  }

  Future<void> deleteReminder(String id) async {
    await _service.deleteReminder(id);
    await _loadReminders();
  }

  Future<void> dismissReminder(String id) async {
    await _service.dismissReminder(id);
    await _loadReminders();
  }

  Future<void> refresh() async {
    await _loadReminders();
  }
}

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
    final maps = await db.query('documents', where: 'deleted_at IS NULL', orderBy: 'created_at DESC');
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
        final bytes = await file.readAsBytes();
        final size = bytes.length;

        final storageService = FileStorageService();
        final savedPath = await storageService.saveFile(bytes, title);

        final importService = DocumentImportService();
        final contentHash = importService.calculateHashSync(bytes);
        final mimeType = importService.getMimeType(extension);

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
          'deleted_at': null,
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

      final now = DateTime.now().millisecondsSinceEpoch;
      await db.update(
        'documents',
        {'deleted_at': now, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );

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
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE documents ADD COLUMN collection_id TEXT');
      await db.execute('ALTER TABLE documents ADD COLUMN deleted_at INTEGER');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_documents_collection ON documents(collection_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_documents_deleted ON documents(deleted_at)');
    }
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
        metadata TEXT,
        collection_id TEXT,
        deleted_at INTEGER
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

class DocumentPreviewScreen extends StatelessWidget {
  final String documentId;
  final String filePath;
  final String title;
  final String type;

  const DocumentPreviewScreen({
    super.key,
    required this.documentId,
    required this.filePath,
    required this.title,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Text('Preview for $title (.$type)'),
      ),
    );
  }
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const AuthScreen(isLogin: true),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const AuthScreen(isLogin: false),
    ),
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const HomeContent(),
        ),
        GoRoute(
          path: '/collections',
          builder: (context, state) => const CollectionsScreen(),
        ),
        GoRoute(
          path: '/tags',
          builder: (context, state) => const TagsScreen(),
        ),
        GoRoute(
          path: '/reminders',
          builder: (context, state) => const RemindersScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/preview/:id',
      builder: (context, state) {
        final docId = state.pathParameters['id']!;
        final doc = appDocuments.firstWhere(
          (d) => d.id == docId,
          orElse: () => throw Exception('Document not found'),
        );
        return DocumentPreviewScreen(
          documentId: doc.id,
          filePath: doc.filePath,
          title: doc.title,
          type: doc.type,
        );
      },
    ),
  ],
);

List<Document> appDocuments = [];

class AuthScreen extends ConsumerStatefulWidget {
  final bool isLogin;
  const AuthScreen({super.key, required this.isLogin});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.isLogin ? 'Welcome Back' : 'Create Account',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                obscureText: true,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              if (_isLoading)
                const CircularProgressIndicator()
              else ...[
                ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: Text(widget.isLogin ? 'Login' : 'Register'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.go(widget.isLogin ? '/register' : '/login'),
                  child: Text(widget.isLogin ? "Don't have an account? Register" : "Already have an account? Login"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() { _error = 'Please fill in all fields'; _isLoading = false; });
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final deviceId = await apiClient.getOrCreateDeviceId();

      Map<String, dynamic>? result;
      if (widget.isLogin) {
        result = await apiClient.post('/auth/login', body: {
          'email': email,
          'password': password,
          'deviceId': deviceId,
        });
      } else {
        result = await apiClient.post('/auth/register', body: {
          'email': email,
          'password': password,
          'deviceId': deviceId,
        });
      }

      if (!mounted) return;

      if (result == null || result.containsKey('error')) {
        setState(() {
          _error = result?['error'] ?? 'Connection failed';
          _isLoading = false;
        });
        return;
      }

      if (result.containsKey('accessToken')) {
        await apiClient.setAccessToken(result['accessToken']);
        if (result.containsKey('refreshToken')) {
          await apiClient.setRefreshToken(result['refreshToken']);
        }
      }

      if (mounted) {
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Network error. Please try again.';
          _isLoading = false;
        });
      }
    }
  }
}

class MainShell extends StatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          setState(() => _currentIndex = i);
          switch (i) {
            case 0: context.go('/'); break;
            case 1: context.go('/collections'); break;
            case 2: context.go('/tags'); break;
            case 3: context.go('/reminders'); break;
            case 4: context.go('/settings'); break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.folder), label: 'Collections'),
          NavigationDestination(icon: Icon(Icons.label), label: 'Tags'),
          NavigationDestination(icon: Icon(Icons.notifications), label: 'Reminders'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class HomeContent extends ConsumerWidget {
  const HomeContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents = ref.watch(documentsProvider);
    appDocuments = documents;

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
                delegate: _DocumentSearchDelegate(ref),
              );
            },
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
                  Text('No documents yet', style: TextStyle(fontSize: 18, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('Tap + to import your first document', style: TextStyle(color: Colors.grey)),
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
                    title: Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${_formatSize(doc.size)} - ${_formatDate(doc.createdAt)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Document'),
                            content: Text('Delete "${doc.title}"?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await ref.read(documentsProvider.notifier).deleteDocument(doc.id);
                        }
                      },
                    ),
                    onTap: () => context.push('/preview/${doc.id}'),
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
    IconData icon; Color color;
    switch (type) {
      case 'pdf': icon = Icons.picture_as_pdf; color = Colors.red; break;
      case 'txt': icon = Icons.description; color = Colors.blue; break;
      case 'jpg': case 'jpeg': case 'png': case 'gif':
        icon = Icons.image; color = Colors.green; break;
      case 'doc': case 'docx': icon = Icons.article; color = Colors.blueGrey; break;
      default: icon = Icons.insert_drive_file; color = Colors.grey;
    }
    return CircleAvatar(backgroundColor: color.withValues(alpha: 0.1), child: Icon(icon, color: color));
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day}/${d.month}/${d.year}';
  }
}

class _DocumentSearchDelegate extends SearchDelegate<Document?> {
  final WidgetRef ref;
  _DocumentSearchDelegate(this.ref);

  @override List<Widget>? buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override Widget? buildLeading(BuildContext context) => IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override Widget buildResults(BuildContext context) => _buildSearchResults(context);
  @override Widget buildSuggestions(BuildContext context) => query.isEmpty
      ? const Center(child: Text('Enter a search term'))
      : _buildSearchResults(context);

  Widget _buildSearchResults(BuildContext context) {
    return FutureBuilder<List<Document>>(
      future: ref.read(documentsProvider.notifier).searchDocuments(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final results = snapshot.data ?? [];
        if (results.isEmpty) return const Center(child: Text('No documents found'));
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
                context.push('/preview/${doc.id}');
              },
            );
          },
        );
      },
    );
  }
}

class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(collectionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collections'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: collections.isEmpty
          ? const Center(child: Text('No collections yet'))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: collections.length,
              itemBuilder: (context, index) {
                final col = collections[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.withValues(alpha: 0.1),
                      child: const Icon(Icons.folder, color: Colors.blue),
                    ),
                    title: Text(col.name),
                    subtitle: Text('${col.documentCount} documents'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Collection'),
                            content: Text('Delete "${col.name}"?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await ref.read(collectionsProvider.notifier).deleteCollection(col.id);
                        }
                      },
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Collection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 8),
            TextField(controller: descController, decoration: const InputDecoration(labelText: 'Description (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                ref.read(collectionsProvider.notifier).createCollection(
                  nameController.text,
                  descController.text.isEmpty ? null : descController.text,
                );
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class TagsScreen extends StatelessWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tags'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: const Center(child: Text('No tags yet')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(remindersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: reminders.isEmpty
          ? const Center(child: Text('No reminders set'))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: reminders.length,
              itemBuilder: (context, index) {
                final reminder = reminders[index];
                final isDue = reminder.remindAt.isBefore(DateTime.now());
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isDue ? Colors.red.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                      child: Icon(Icons.notifications, color: isDue ? Colors.red : Colors.orange),
                    ),
                    title: Text(reminder.title),
                    subtitle: Text(
                      isDue
                          ? 'Due: ${_formatDateTime(reminder.remindAt)}'
                          : 'Scheduled: ${_formatDateTime(reminder.remindAt)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check),
                          onPressed: () => ref.read(remindersProvider.notifier).dismissReminder(reminder.id),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => ref.read(remindersProvider.notifier).deleteReminder(reminder.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('Biometric Lock'),
            subtitle: const Text('Enable biometric authentication'),
            trailing: Switch(value: false, onChanged: (v) {}),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Sync Now'),
            subtitle: const Text('Sync documents with server'),
            onTap: () {},
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () => context.go('/login'),
          ),
        ],
      ),
    );
  }
}

void main() {
  runApp(const ProviderScope(child: LifeVaultApp()));
}

class LifeVaultApp extends StatelessWidget {
  const LifeVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'LifeVault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      routerConfig: appRouter,
    );
  }
}
