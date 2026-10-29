import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

class FileStorageService {
  static final Map<String, Uint8List> _inMemoryFiles = {};

  Future<String> saveFile(Uint8List bytes, String originalName) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_$originalName';
    _inMemoryFiles[fileName] = bytes;

    try {
      final mimeType = _getMimeType(originalName);
      final jsBytes = bytes.toJS;
      final blob = web.Blob([jsBytes].toJS, web.BlobPropertyBag(type: mimeType));
      final objectUrl = web.URL.createObjectURL(blob);

      final anchor = web.document.createElement('a') as web.HTMLAnchorElement
        ..href = objectUrl
        ..download = originalName
        ..style.display = 'none';

      web.document.body?.append(anchor);
      anchor.click();
      anchor.remove();

      web.URL.revokeObjectURL(objectUrl);
    } catch (e) {
      // Fallback: try using data URL approach
      try {
        final dataUrl = 'data:${_getMimeType(originalName)};base64,${bytes.toBase64String()}';
        final anchor = web.document.createElement('a') as web.HTMLAnchorElement
          ..href = dataUrl
          ..download = originalName
          ..style.display = 'none';

        web.document.body?.append(anchor);
        anchor.click();
        anchor.remove();
      } catch (e2) {
        throw Exception('Failed to trigger download: $e, fallback: $e2');
      }
    }

    return fileName;
  }

  Future<Uint8List?> getFile(String fileName) async {
    return _inMemoryFiles[fileName];
  }

  Future<void> deleteFile(String fileName) async {
    _inMemoryFiles.remove(fileName);
  }

  String _getMimeType(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1) return 'application/octet-stream';
    final ext = fileName.substring(lastDot).toLowerCase();
    switch (ext) {
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

  bool get supportsDirectories => false;
}