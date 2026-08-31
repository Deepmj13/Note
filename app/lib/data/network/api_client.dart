import 'dart:async';

import 'package:dio/dio.dart';
import 'package:note_v4/core/config.dart';
import 'package:note_v4/core/observability.dart';
import 'package:sentry_dio/sentry_dio.dart';
import 'token_storage.dart';

/// Shared [Dio] instance that attaches the persisted bearer token to every
/// request. The token is loaded lazily from secure storage on each request so
/// it stays in sync with the auth state.
class ApiClient {
  ApiClient(this._tokenStorage)
      : dio = Dio(
          BaseOptions(
            baseUrl: ApiConfig.baseUrl,
            connectTimeout: const Duration(seconds: 25),
            receiveTimeout: const Duration(seconds: 30),
          ),
        ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokenStorage.read();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (e, handler) {
          // A 401 on a non-auth endpoint means the stored token has expired or
          // been revoked. Clear it and surface the session as over so the app
          // can return to the login screen. Auth endpoints (which legitimately
          // return 401 on bad credentials) are left to their callers.
          if (e.response?.statusCode == 401 &&
              !_isAuthEndpoint(e.requestOptions.path)) {
            unawaited(_tokenStorage.clear());
            onSessionExpired?.call();
          }
          handler.next(e);
        },
      ),
    );
    if (sentryEnabled) {
      dio.addSentry();
    }
  }

  final TokenStorage _tokenStorage;

  /// Invoked when a non-auth request returns 401 (expired/revoked token).
  /// The app wires this to return the user to the login screen.
  void Function()? onSessionExpired;

  final Dio dio;

  static bool _isAuthEndpoint(String path) {
    final normalized = path.split('?').first;
    return normalized == '/auth/login' ||
        normalized == '/auth/register' ||
        normalized == '/auth/me';
  }
}
