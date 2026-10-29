import 'dart:typed_data';

class FileStorageService {
  Future<String> saveFile(Uint8List bytes, String originalName) {
    throw UnsupportedError('FileStorageService not supported on this platform');
  }

  Future<Uint8List?> getFileBytes(String path) {
    throw UnsupportedError('FileStorageService not supported on this platform');
  }

  Future<void> deleteFile(String path) {
    throw UnsupportedError('FileStorageService not supported on this platform');
  }

  bool get supportsDirectories => false;
}
