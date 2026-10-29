import 'dart:convert';
import 'package:crypto/crypto.dart';

class EncryptionService {
  List<int> deriveKey(String password, List<int> salt, {int iterations = 100000, int keyLength = 32}) {
    final hmac = Hmac(sha512, utf8.encode(password));
    List<int> digest = utf8.encode(password) + salt;

    for (var i = 0; i < iterations; i++) {
      digest = hmac.convert(digest).bytes;
    }

    return digest.sublist(0, keyLength);
  }

  Map<String, dynamic> encryptBytes(List<int> data, List<int> key) {
    final iv = _generateIv(12);
    final cipher = _AesGcmCipher(key, iv);
    final encrypted = cipher.encrypt(data);
    return {
      'encrypted': encrypted,
      'iv': iv,
    };
  }

  List<int> decryptBytes(List<int> encryptedData, List<int> key, List<int> iv) {
    final cipher = _AesGcmCipher(key, iv);
    return cipher.decrypt(encryptedData);
  }

  String encryptToBase64(List<int> data, List<int> key) {
    final result = encryptBytes(data, key);
    final iv = result['iv'] as List<int>;
    final encrypted = result['encrypted'] as List<int>;
    final combined = iv + encrypted;
    return base64Encode(combined);
  }

  List<int> decryptFromBase64(String encoded, List<int> key) {
    final combined = base64Decode(encoded);
    final iv = combined.sublist(0, 12);
    final encrypted = combined.sublist(12);
    return decryptBytes(encrypted, key, iv);
  }

  List<int> _generateIv(int length) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final bytes = utf8.encode(now.toString());
    final digest = sha256.convert(bytes);
    return digest.bytes.sublist(0, length);
  }
}

class _AesGcmCipher {
  final List<int> key;
  final List<int> iv;

  _AesGcmCipher(this.key, this.iv);

  List<int> encrypt(List<int> data) {
    final hmacKey = sha256.convert(key).bytes;
    final encrypted = <int>[];
    var counter = 0;

    for (var i = 0; i < data.length; i += 16) {
      final block = List<int>.filled(16, 0);
      final chunkEnd = (i + 16 < data.length) ? i + 16 : data.length;
      for (var j = i; j < chunkEnd; j++) {
        block[j - i] = data[j];
      }

      final counterBytes = _intToBytes(counter);
      final streamKey = sha256.convert([...hmacKey, ...counterBytes]).bytes;
      for (var k = 0; k < block.length; k++) {
        block[k] ^= streamKey[k];
      }
      encrypted.addAll(block);
      counter++;
    }

    final authTag = _computeAuthTag(data, encrypted);
    return [...encrypted, ...authTag];
  }

  List<int> decrypt(List<int> data) {
    if (data.length < 16) return [];

    final authTag = data.sublist(data.length - 16);
    final encrypted = data.sublist(0, data.length - 16);
    final hmacKey = sha256.convert(key).bytes;
    final decrypted = <int>[];
    var counter = 0;

    for (var i = 0; i < encrypted.length; i += 16) {
      final block = encrypted.sublist(i, i + 16 < encrypted.length ? i + 16 : encrypted.length);
      final counterBytes = _intToBytes(counter);
      final streamKey = sha256.convert([...hmacKey, ...counterBytes]).bytes;

      final plainBlock = List<int>.filled(block.length, 0);
      for (var k = 0; k < block.length; k++) {
        plainBlock[k] = block[k] ^ streamKey[k];
      }
      decrypted.addAll(plainBlock);
      counter++;
    }

    return decrypted;
  }

  List<int> _computeAuthTag(List<int> data, List<int> encrypted) {
    final combined = [...key, ...iv, ...data, ...encrypted];
    final digest = sha256.convert(combined);
    return digest.bytes.sublist(0, 16);
  }

  List<int> _intToBytes(int value) {
    return [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }
}