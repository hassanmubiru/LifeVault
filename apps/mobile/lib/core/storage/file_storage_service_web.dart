// ignore: deprecated_member_use
// Using dart:html for web file downloads - works but deprecated in favor of package:web
import 'dart:typed_data';
import 'dart:html' as html;
import 'package:uuid/uuid.dart';

class FileStorageService {
  static final Map<String, Uint8List> _inMemoryFiles = {};

  Future<String> saveFile(Uint8List bytes, String originalName) async {
    final fileName = '${const Uuid().v4()}${_getExtension(originalName)}';
    _inMemoryFiles[fileName] = bytes;

    _triggerDownload(bytes, fileName, _getMimeType(originalName));

    return fileName;
  }

  Future<Uint8List?> getFileBytes(String fileName) async {
    return _inMemoryFiles[fileName];
  }

  Future<void> deleteFile(String fileName) async {
    _inMemoryFiles.remove(fileName);
  }

  void _triggerDownload(Uint8List bytes, String fileName, String mimeType) {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }

  String _getExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1) return '';
    return fileName.substring(lastDot);
  }

  String _getMimeType(String fileName) {
    final ext = _getExtension(fileName).toLowerCase();
    switch (ext) {
      case '.pdf': return 'application/pdf';
      case '.txt': return 'text/plain';
      case '.jpg': case '.jpeg': return 'image/jpeg';
      case '.png': return 'image/png';
      case '.gif': return 'image/gif';
      case '.doc': return 'application/msword';
      case '.docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default: return 'application/octet-stream';
    }
  }

  bool get supportsDirectories => false;
}
