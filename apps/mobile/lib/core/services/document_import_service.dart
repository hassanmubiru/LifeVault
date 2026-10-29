import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class DocumentImportService {
  Future<String> calculateHash(List<int> bytes) async {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  String calculateHashSync(List<int> bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  bool isSupportedType(String extension) {
    const supported = ['.pdf', '.txt', '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.doc', '.docx'];
    return supported.contains(extension.toLowerCase());
  }

  String getMimeType(String extension) {
    switch (extension.toLowerCase()) {
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
