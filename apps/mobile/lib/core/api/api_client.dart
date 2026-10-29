import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiClient {
  static const String baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:3000');
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const String _accessTokenKey = 'lifevault_access_token';
  static const String _refreshTokenKey = 'lifevault_refresh_token';
  static const String _deviceIdKey = 'lifevault_device_id';

  Future<String?> get accessToken => _storage.read(key: _accessTokenKey);
  Future<String?> get refreshToken => _storage.read(key: _refreshTokenKey);
  Future<String?> get deviceId => _storage.read(key: _deviceIdKey);

  Future<void> setAccessToken(String token) async {
    await _storage.write(key: _accessTokenKey, value: token);
  }

  Future<void> setRefreshToken(String token) async {
    await _storage.write(key: _refreshTokenKey, value: token);
  }

  Future<String?> getOrCreateDeviceId() async {
    String? id = await _storage.read(key: _deviceIdKey);
    if (id == null) {
      id = DateTime.now().millisecondsSinceEpoch.toRadixString(36) + DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      await _storage.write(key: _deviceIdKey, value: id);
    }
    return id;
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  Map<String, String> _headers({bool auth = true, String? token}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (auth && token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<Map<String, dynamic>?> get(String path, {bool auth = true, String? token}) async {
    try {
      final t = auth ? (token ?? await accessToken) : null;
      final resp = await http.get(
        Uri.parse('$baseUrl$path'),
        headers: _headers(auth: auth, token: t),
      ).timeout(const Duration(seconds: 30));
      return _handleResponse(resp);
    } catch (e) {
      return _errorResponse(e.toString());
    }
  }

  Future<Map<String, dynamic>?> post(String path, {Map<String, dynamic>? body, bool auth = true, String? token}) async {
    try {
      final t = auth ? (token ?? await accessToken) : null;
      final resp = await http.post(
        Uri.parse('$baseUrl$path'),
        headers: _headers(auth: auth, token: t),
        body: body != null ? jsonEncode(body) : null,
      ).timeout(const Duration(seconds: 30));
      return _handleResponse(resp);
    } catch (e) {
      return _errorResponse(e.toString());
    }
  }

  Future<Map<String, dynamic>?> put(String path, {Map<String, dynamic>? body, bool auth = true, String? token}) async {
    try {
      final t = auth ? (token ?? await accessToken) : null;
      final resp = await http.put(
        Uri.parse('$baseUrl$path'),
        headers: _headers(auth: auth, token: t),
        body: body != null ? jsonEncode(body) : null,
      ).timeout(const Duration(seconds: 30));
      return _handleResponse(resp);
    } catch (e) {
      return _errorResponse(e.toString());
    }
  }

  Future<Map<String, dynamic>?> patch(String path, {Map<String, dynamic>? body, bool auth = true, String? token}) async {
    try {
      final t = auth ? (token ?? await accessToken) : null;
      final resp = await http.patch(
        Uri.parse('$baseUrl$path'),
        headers: _headers(auth: auth, token: t),
        body: body != null ? jsonEncode(body) : null,
      ).timeout(const Duration(seconds: 30));
      return _handleResponse(resp);
    } catch (e) {
      return _errorResponse(e.toString());
    }
  }

  Future<Map<String, dynamic>?> delete(String path, {bool auth = true, String? token}) async {
    try {
      final t = auth ? (token ?? await accessToken) : null;
      final resp = await http.delete(
        Uri.parse('$baseUrl$path'),
        headers: _headers(auth: auth, token: t),
      ).timeout(const Duration(seconds: 30));
      return _handleResponse(resp);
    } catch (e) {
      return _errorResponse(e.toString());
    }
  }

  Map<String, dynamic>? _handleResponse(http.Response resp) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (resp.body.isEmpty) return {'success': true};
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    if (resp.statusCode == 401) {
      return {'error': 'Unauthorized', 'statusCode': 401};
    }
    try {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      body['statusCode'] = resp.statusCode;
      return body;
    } catch (e) {
      return {'error': resp.body, 'statusCode': resp.statusCode};
    }
  }

  Map<String, dynamic> _errorResponse(String message) {
    return {'error': message, 'statusCode': -1};
  }
}
