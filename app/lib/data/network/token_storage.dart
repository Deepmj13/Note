import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the JWT access token and its rotating refresh token securely
/// on-device. The refresh token is stored under its own key so it is never
/// mistaken for (or sent in place of) the access token.
class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'auth_token';
  static const _refreshTokenKey = 'auth_refresh_token';

  final FlutterSecureStorage _storage;

  Future<String?> read() => _storage.read(key: _tokenKey);

  Future<void> write(String token) => _storage.write(key: _tokenKey, value: token);

  Future<void> clear() => _storage.delete(key: _tokenKey);

  Future<String?> readRefresh() => _storage.read(key: _refreshTokenKey);

  Future<void> writeRefresh(String token) =>
      _storage.write(key: _refreshTokenKey, value: token);

  Future<void> clearRefresh() => _storage.delete(key: _refreshTokenKey);
}
