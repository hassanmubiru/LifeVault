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
      
      // Create a JS ArrayBuffer from the bytes
      final jsArray = [bytes.buffer.asUint8List().toJS].toJS;
      final blob = web.Blob(jsArray, web.BlobPropertyBag(type: mimeType));
      final objectUrl = web.URL.createObjectURL(blob);

      final anchor = web.HTMLAnchorElement()
        ..href = objectUrl
        ..download = originalName
        ..style.display = 'none';

      web.document.body?.append(anchor);
      anchor.click();
      anchor.remove();

      web.URL.revokeObjectURL(objectUrl);
    } catch (e) {
      // Fallback: use data URL approach
      try {
        final dataUrl = 'data:${_getMimeType(originalName)};base64,${_base64Encode(bytes)}';
        final anchor = web.HTMLAnchorElement()
          ..href = dataUrl
          ..download = originalName
          ..style.display = 'none';

        web.document.body?.append(anchor);
        anchor.click();
        anchor.remove();
      } catch (e2) {
        rethrow;
      }
    }

    return fileName;
  }

  String _base64Encode(Uint8List bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      buffer.write(String.fromCharCode(bytes[i]));
    }
    return _btoa(buffer.toString());
  }

  String _btoa(String input) {
    final chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final result = StringBuffer();
    var i = 0;
    
    while (i < input.length) {
      final a = input.codeUnitAt(i++);
      final b = i < input.length ? input.codeUnitAt(i++) : 0;
      final c = i < input.length ? input.codeUnitAt(i++) : 0;
      
      final triplet = (a << 16) | (b << 8) | c;
      
      result.write(chars.codeUnitAt((triplet >> 18) & 0x3F));
      result.write(chars.codeUnitAt((triplet >> 12) & 0x3F));
      result.write(i - 2 < input.length ? chars.codeUnitAt((triplet >> 6) & 0x3F) : '=');
      result.write(i - 1 < input.length ? chars.codeUnitAt(triplet & 0x3F) : '=');
    }
    
    return result.toString();
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
