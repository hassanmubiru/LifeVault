import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../api/api_client.dart';
import '../services/encryption_service.dart';

class DocumentService {
  final ApiClient _api;
  final EncryptionService _encryption = EncryptionService();

  DocumentService(this._api);

  Future<Map<String, dynamic>?> syncUpload({
    required String documentId,
    required File file,
    required String contentHash,
  }) async {
    final bytes = await file.readAsBytes();
    final salt = _generateSalt(16);
    final key = _encryption.deriveKey(documentId, salt);

    final encrypted = _encryption.encryptBytes(bytes, key);
    final iv = encrypted['iv'] as List<int>;
    final encryptedData = encrypted['encrypted'] as List<int>;

    final combined = [...iv, ...encryptedData.sublist(0, encryptedData.length - 16), ...encryptedData.sublist(encryptedData.length - 16)];

    return await _api.post('/sync/upload', body: {
      'documentId': documentId,
      'encryptedData': base64Encode(combined),
      'iv': base64Encode(iv),
      'authTag': base64Encode(encryptedData.sublist(encryptedData.length - 16)),
      'contentHash': contentHash,
      'salt': base64Encode(salt),
    });
  }

  Future<File?> syncDownload({
    required String documentId,
    required String savePath,
  }) async {
    final resp = await _api.get('/sync/download/$documentId');

    if (resp == null || resp['error'] != null) return null;

    final encryptedData = base64Decode(resp['encryptedData'] as String);
    final iv = base64Decode(resp['iv'] as String);
    final authTag = base64Decode(resp['authTag'] as String);

    final salt = _generateSaltFromIv(iv);
    final key = _encryption.deriveKey(documentId, salt);

    final combined = [...iv, ...authTag, ...encryptedData];
    final decrypted = _encryption.decryptBytes(combined, key);

    final file = File(savePath);
    await file.writeAsBytes(decrypted);
    return file;
  }

  Future<Map<String, dynamic>?> getSyncStatus() async {
    return await _api.get('/sync/status');
  }

  Future<Map<String, dynamic>?> getQueuedItems({int limit = 50, int offset = 0}) async {
    return await _api.get('/sync/queue?limit=$limit&offset=$offset');
  }

  Future<Map<String, dynamic>?> processQueue() async {
    return await _api.post('/sync/process');
  }

  Future<Map<String, dynamic>?> getDocuments({int page = 1, int limit = 20}) async {
    return await _api.get('/documents?page=$page&limit=$limit');
  }

  Future<Map<String, dynamic>?> getDocument(String id) async {
    return await _api.get('/documents/$id');
  }

  Future<Map<String, dynamic>?> createDocument(Map<String, dynamic> data) async {
    return await _api.post('/documents', body: data);
  }

  Future<Map<String, dynamic>?> updateDocument(String id, Map<String, dynamic> data) async {
    return await _api.patch('/documents/$id', body: data);
  }

  Future<Map<String, dynamic>?> deleteDocument(String id) async {
    return await _api.delete('/documents/$id');
  }

  List<int> _generateSalt(int length) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final bytes = utf8.encode(now.toString());
    final digest = sha256.convert(bytes);
    return digest.bytes.sublist(0, length);
  }

  List<int> _generateSaltFromIv(List<int> iv) {
    final combined = [...iv, ...utf8.encode('lifevault_salt')];
    return sha256.convert(combined).bytes.sublist(0, 16);
  }

  Uint8List deriveKeyForDocument(String documentId) {
    final salt = _generateSalt(16);
    final key = _encryption.deriveKey(documentId, salt);
    return Uint8List.fromList(key);
  }
}