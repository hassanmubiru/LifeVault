import 'dart:io';
import 'package:crypto/crypto.dart';

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
