import 'package:dio/dio.dart';
import 'package:note_v4/core/config.dart';
import 'package:note_v4/core/observability.dart';
import 'package:sentry_dio/sentry_dio.dart';
import 'token_storage.dart';

/// Shared [Dio] instance that attaches the persisted bearer token to every
/// request. The token is loaded lazily from secure storage on each request so
/// it stays in sync with the auth state.
///
/// When a non-auth request comes back 401 (expired/revoked access token), the
/// stored refresh token is exchanged for a fresh pair (single-flight, so
/// concurrent 401s trigger one refresh) and the original request is retried
/// once. If the refresh fails, the session is torn down via [onSessionExpired].
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
        onError: (e, handler) async {
          // Auth endpoints (login/register/refresh/logout) legitimately return
          // 401 on bad credentials and are never auto-refreshed.
          if (e.response?.statusCode != 401 || _isAuthEndpoint(e.requestOptions.path)) {
            handler.next(e);
            return;
          }

          // A retried request that still 401s means the refreshed token was
          // also rejected (or the account was revoked mid-flight).
          if (e.requestOptions.extra[_retriedAfterRefresh] == true) {
            await _clearTokens();
            onSessionExpired?.call();
            handler.next(e);
            return;
          }

          if (await _refreshOnce()) {
            final retry = e.requestOptions;
            retry.extra[_retriedAfterRefresh] = true;
            try {
              final response = await dio.fetch(retry);
              handler.resolve(response);
              return;
            } on DioException {
              // The retry went through the interceptors again; a second 401 was
              // already handled above (clear + onSessionExpired). Surface the
              // original failure to the caller.
              handler.next(e);
              return;
            }
          }

          await _clearTokens();
          onSessionExpired?.call();
          handler.next(e);
        },
      ),
    );
    if (sentryEnabled) {
      dio.addSentry();
    }
  }

  final TokenStorage _tokenStorage;

  /// Invoked when a non-auth request returns 401 and no refresh token could
  /// restore the session. The app wires this to return the user to the login
  /// screen.
  void Function()? onSessionExpired;

  final Dio dio;

  static const _retriedAfterRefresh = '__retried_after_refresh__';

  /// Single-flight guard so several concurrent 401s share one refresh call.
  Future<bool>? _inFlightRefresh;

  Future<bool> _refreshOnce() {
    final inFlight = _inFlightRefresh;
    if (inFlight != null) return inFlight;
    final future = _doRefresh().whenComplete(() => _inFlightRefresh = null);
    _inFlightRefresh = future;
    return future;
  }

  Future<bool> _doRefresh() async {
    final token = await _tokenStorage.readRefresh();
    if (token == null || token.isEmpty) return false;
    try {
      final res = await dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': token},
      );
      final data = res.data!;
      await _tokenStorage.write(data['token'] as String);
      await _tokenStorage.writeRefresh(data['refreshToken'] as String);
      return true;
    } on DioException {
      return false;
    }
  }

  Future<void> _clearTokens() async {
    await _tokenStorage.clear();
    await _tokenStorage.clearRefresh();
  }

  static bool _isAuthEndpoint(String path) {
    final normalized = path.split('?').first;
    return normalized == '/auth/login' ||
        normalized == '/auth/register' ||
        normalized == '/auth/refresh' ||
        normalized == '/auth/logout';
  }
}
