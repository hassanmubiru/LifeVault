import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/collection_service.dart';
import '../core/services/tag_service.dart';
import '../core/services/reminder_service.dart';
import '../core/services/biometric_service.dart';
import '../core/api/api_client.dart';
import '../core/api/auth_service.dart';
import '../main.dart';

final apiClientProvider = Provider((ref) => ApiClient());
final authServiceProvider = Provider((ref) => AuthService(ref.watch(apiClientProvider)));
final biometricServiceProvider = Provider((ref) => BiometricService());
final collectionServiceProvider = Provider((ref) => CollectionService());
final tagServiceProvider = Provider((ref) => TagService());
final reminderServiceProvider = Provider((ref) => ReminderService());

class AppRouter {
  final WidgetRef ref;

  AppRouter(this.ref);

  late final GoRouter router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      final auth = ref.read(authServiceProvider);
      final isAuth = await auth.isAuthenticated();
      final isLogin = state.matchedLocation == '/login' || state.matchedLocation == '/register';

      if (!isAuth && !isLogin) return '/login';
      if (isAuth && isLogin) return '/';
      return null;
    },
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
          final doc = ref.read(documentsProvider).firstWhere(
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

class DocumentSearchDelegate extends SearchDelegate<Document?> {
  final WidgetRef ref;
  DocumentSearchDelegate(this.ref);

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
  bool _useBiometric = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final biometric = ref.read(biometricServiceProvider);
    final available = await biometric.isAvailable();
    if (available && mounted) setState(() => _useBiometric = available);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(widget.isLogin ? 'Welcome Back' : 'Create Account',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
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
                if (_useBiometric) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _authenticateBiometric,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Use Biometric'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  ),
                ],
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
    setState(() { _isLoading = true; _error = null; });
    final auth = ref.read(authServiceProvider);
    final result = widget.isLogin
        ? await auth.login(email: _emailController.text, password: _passwordController.text)
        : await auth.register(email: _emailController.text, password: _passwordController.text);

    if (mounted) {
      setState(() => _isLoading = false);
      if (result != null && result['error'] == null) {
        context.go('/');
      } else {
        setState(() => _error = result?['error']?.toString() ?? 'Authentication failed');
      }
    }
  }

  Future<void> _authenticateBiometric() async {
    final biometric = ref.read(biometricServiceProvider);
    final success = await biometric.authenticate();
    if (success && mounted) context.go('/');
  }
}

class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(collectionsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collections'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: collections.isEmpty
          ? const Center(child: Text('No collections yet'))
          : ListView.builder(
              itemCount: collections.length,
              itemBuilder: (context, index) {
                final col = collections[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Color(int.tryParse(col.color ?? '0xFF2196F3') ?? 0xFF2196F3).withValues(alpha: 0.1),
                    child: const Icon(Icons.folder, color: Colors.blue),
                  ),
                  title: Text(col.name),
                  subtitle: Text('${col.documentCount} documents'),
                  trailing: PopupMenuButton(
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                    onSelected: (action) {
                      if (action == 'delete') {
                        ref.read(collectionServiceProvider).deleteCollection(col.id);
                      }
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCollectionDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showCollectionDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Collection'),
        content: TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                final now = DateTime.now().millisecondsSinceEpoch;
                ref.read(collectionServiceProvider).createCollection(
                  Collection(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: nameController.text,
                    createdAt: now,
                    updatedAt: now,
                  ),
                );
              }
              Navigator.pop(ctx);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class TagsScreen extends ConsumerWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tags'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: tags.isEmpty
          ? const Center(child: Text('No tags yet'))
          : ListView.builder(
              itemCount: tags.length,
              itemBuilder: (context, index) {
                final tag = tags[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.teal.withValues(alpha: 0.1),
                    child: const Icon(Icons.label, color: Colors.teal),
                  ),
                  title: Text(tag.name),
                  subtitle: Text('${tag.documentCount} documents'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => ref.read(tagServiceProvider).deleteTag(tag.id),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showTagDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showTagDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Tag'),
        content: TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                ref.read(tagServiceProvider).createTag(
                  Tag(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: nameController.text,
                    createdAt: DateTime.now().millisecondsSinceEpoch,
                  ),
                );
              }
              Navigator.pop(ctx);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(remindersStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: reminders.isEmpty
          ? const Center(child: Text('No reminders set'))
          : ListView.builder(
              itemCount: reminders.length,
              itemBuilder: (context, index) {
                final reminder = reminders[index];
                return ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.orange,
                    child: Icon(Icons.notifications, color: Colors.white),
                  ),
                  title: Text(reminder.title),
                  subtitle: Text(_formatReminderTime(reminder.remindAt)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.snooze),
                        onPressed: () => ref.read(reminderServiceProvider).snoozeReminder(reminder.id, const Duration(hours: 1)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.check),
                        onPressed: () => ref.read(reminderServiceProvider).dismissReminder(reminder.id),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  String _formatReminderTime(DateTime time) {
    final now = DateTime.now();
    final diff = time.difference(now);
    if (diff.isNegative) return 'Due now';
    if (diff.inMinutes < 60) return 'In ${diff.inMinutes} minutes';
    if (diff.inHours < 24) return 'In ${diff.inHours} hours';
    return 'In ${diff.inDays} days';
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            trailing: Switch(
              value: false,
              onChanged: (v) {},
            ),
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
            onTap: () async {
              await ref.read(authServiceProvider).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}

final collectionsStreamProvider = StateProvider<List<Collection>>((ref) {
  final service = ref.watch(collectionServiceProvider);
  service.getAllCollections().then((cols) {
    Future.microtask(() => ref.state = cols);
  });
  return [];
});

final tagsStreamProvider = StateProvider<List<Tag>>((ref) {
  final service = ref.watch(tagServiceProvider);
  service.getAllTags().then((tags) {
    Future.microtask(() => ref.state = tags);
  });
  return [];
});

final remindersStreamProvider = StateProvider<List<Reminder>>((ref) {
  final service = ref.watch(reminderServiceProvider);
  service.getUpcomingReminders().then((reminders) {
    Future.microtask(() => ref.state = reminders);
  });
  service.startPeriodicCheck();
  return [];
});
