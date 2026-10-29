import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class FileStorageService {
  Future<Directory> get _docsDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final docsDir = Directory(p.join(appDir.path, 'lifevault_docs'));
    if (!await docsDir.exists()) {
      await docsDir.create(recursive: true);
    }
    return docsDir;
  }

  Future<String> saveFile(Uint8List bytes, String originalName) async {
    final docsDir = await _docsDir;
    final ext = p.extension(originalName);
    final fileName = '${const Uuid().v4()}$ext';
    final targetPath = p.join(docsDir.path, fileName);
    await File(targetPath).writeAsBytes(bytes);
    return targetPath;
  }

  Future<Uint8List?> getFileBytes(String path) async {
    final file = File(path);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  bool get supportsDirectories => true;
}
