import '../api/api_client.dart';

class AuthService {
  final ApiClient _api;

  AuthService(this._api);

  Future<Map<String, dynamic>?> register({
    required String email,
    required String password,
  }) async {
    final resp = await _api.post('/auth/register', body: {
      'email': email,
      'password': password,
    }, auth: false);

    if (resp != null && resp['accessToken'] != null) {
      await _api.setAccessToken(resp['accessToken']);
      if (resp['refreshToken'] != null) {
        await _api.setRefreshToken(resp['refreshToken']);
      }
      final deviceId = await _api.getOrCreateDeviceId();
      if (resp['deviceToken'] != null && deviceId != null) {
        await _api.setRefreshToken(resp['deviceToken']);
      }
    }
    return resp;
  }

  Future<Map<String, dynamic>?> login({
    required String email,
    required String password,
  }) async {
    final deviceId = await _api.getOrCreateDeviceId();

    final resp = await _api.post('/auth/login', body: {
      'email': email,
      'password': password,
      'deviceId': deviceId,
    }, auth: false);

    if (resp != null && resp['accessToken'] != null) {
      await _api.setAccessToken(resp['accessToken']);
      if (resp['refreshToken'] != null) {
        await _api.setRefreshToken(resp['refreshToken']);
      }
      if (resp['deviceToken'] != null && deviceId != null) {
        await _api.setRefreshToken(resp['deviceToken']);
      }
    }
    return resp;
  }

  Future<Map<String, dynamic>?> refreshAccessToken() async {
    final refreshT = await _api.refreshToken;
    if (refreshT == null) return {'error': 'No refresh token'};

    final resp = await _api.post('/auth/refresh', body: {
      'refreshToken': refreshT,
    }, auth: false);

    if (resp != null && resp['accessToken'] != null) {
      await _api.setAccessToken(resp['accessToken']);
      if (resp['refreshToken'] != null) {
        await _api.setRefreshToken(resp['refreshToken']);
      }
    }
    return resp;
  }

  Future<Map<String, dynamic>?> me() async {
    return await _api.get('/auth/me');
  }

  Future<Map<String, dynamic>?> logout() async {
    final resp = await _api.post('/auth/logout');
    await _api.clearTokens();
    return resp;
  }

  Future<bool> isAuthenticated() async {
    final token = await _api.accessToken;
    return token != null;
  }
}