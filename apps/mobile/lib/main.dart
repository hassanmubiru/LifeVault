import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;

final documentsProvider = StateNotifierProvider<DocumentsNotifier, List<Document>>((ref) {
  return DocumentsNotifier();
});

class Document {
  final String id;
  final String title;
  final String type;
  final String filePath;
  final int size;
  final DateTime createdAt;
  final String? mimeType;

  Document({
    required this.id,
    required this.title,
    required this.type,
    required this.filePath,
    required this.size,
    required this.createdAt,
    this.mimeType,
  });
}

class DocumentsNotifier extends StateNotifier<List<Document>> {
  DocumentsNotifier() : super([]);

  Future<void> importDocument() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'jpg', 'jpeg', 'png', 'gif', 'bmp', 'doc', 'docx'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        PlatformFile file = result.files.first;
        String id = const Uuid().v4();
        String title = file.name;
        String extension = p.extension(file.name ?? '').toLowerCase();
        String mimeType = _getMimeType(extension);

        Document doc = Document(
          id: id,
          title: title,
          type: extension.replaceFirst('.', ''),
          filePath: file.path ?? '',
          size: file.size,
          createdAt: DateTime.now(),
          mimeType: mimeType,
        );

        state = [doc, ...state];
      }
    } catch (e, stackTrace) {
      debugPrint('Error importing document: $e');
      debugPrint('Stack trace: $stackTrace');
    }
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

  void removeDocument(String id) {
    state = state.where((doc) => doc.id != id).toList();
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

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

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
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchScreen()),
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
                      onPressed: () {
                        ref.read(documentsProvider.notifier).removeDocument(doc.id);
                      },
                    ),
                    onTap: () {},
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ref.read(documentsProvider.notifier).importDocument();
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
      backgroundColor: color.withOpacity(0.1),
      child: Icon(icon, color: color),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
      ),
      body: const Center(
        child: Text('Search functionality coming soon'),
      ),
    );
  }
}
