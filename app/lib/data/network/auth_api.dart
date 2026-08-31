import 'package:dio/dio.dart';
import 'api_client.dart';

class AuthUserData {
  const AuthUserData({required this.id, required this.email});

  final String id;
  final String email;

  factory AuthUserData.fromJson(Map<String, dynamic> json) {
    return AuthUserData(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
    );
  }
}

class AuthResult {
  const AuthResult({required this.token, required this.user});

  final String token;
  final AuthUserData user;
}

/// Talks to the backend auth endpoints: /auth/register, /auth/login, /auth/me.
class AuthApi {
  AuthApi(this._client);

  final ApiClient _client;

  Future<AuthResult> register({required String email, required String password}) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/auth/register',
      data: {'email': email, 'password': password},
    );
    return _resultFromResponse(res);
  }

  Future<AuthResult> login({required String email, required String password}) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    return _resultFromResponse(res);
  }

  Future<AuthUserData> me() async {
    final res = await _client.dio.get<Map<String, dynamic>>('/auth/me');
    return AuthUserData.fromJson(res.data!['user'] as Map<String, dynamic>);
  }

  AuthResult _resultFromResponse(Response<Map<String, dynamic>> res) {
    final data = res.data!;
    return AuthResult(
      token: data['token'] as String,
      user: AuthUserData.fromJson(data['user'] as Map<String, dynamic>),
    );
  }
}
