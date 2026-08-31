import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_v4/data/network/network_providers.dart';
import 'package:note_v4/data/repositories/note_repository.dart';
import 'package:note_v4/providers/sync_notifier.dart';

/// A signed-in user as surfaced to the app.
class AuthUser {
  const AuthUser({required this.id, this.email});

  final String id;
  final String? email;
}

/// Thrown when email/password authentication fails, carrying a user-facing
/// message.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthController extends Notifier<AuthUser?> {
  @override
  AuthUser? build() {
    // Wire session-expiry (401 on non-auth calls) back to this controller so
    // an expired/invalid token returns the user to the login screen.
    ref.read(apiClientProvider).onSessionExpired = _handleSessionExpired;
    ref.onDispose(() {
      ref.read(apiClientProvider).onSessionExpired = null;
    });
    _restoreSession();
    return null;
  }

  void _handleSessionExpired() {
    unawaited(_resetOnSessionExpired());
  }

  Future<void> _resetOnSessionExpired() async {
    await ref.read(tokenStorageProvider).clear();
    await ref.read(noteRepositoryProvider).clearLocalData();
    state = null;
  }

  /// Restores the session from the persisted JWT on startup. Runs the normal
  /// adopt-local-data + sync path when a valid token restores a user, then
  /// marks auth as ready so the app can decide which screen to show.
  Future<void> _restoreSession() async {
    try {
      final token = await ref.read(tokenStorageProvider).read();
      if (token == null || token.isEmpty) return;
      final data = await ref.read(authApiProvider).me();
      await _adoptAndSync(AuthUser(id: data.id, email: data.email));
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await ref.read(tokenStorageProvider).clear();
      }
    } catch (_) {
      // Ignore transient failures; the user just sees the login screen.
    } finally {
      ref.read(authReadyProvider.notifier).state = true;
    }
  }

  Future<void> _adoptAndSync(AuthUser user) async {
    await ref.read(noteRepositoryProvider).adoptLocalData(user.id);
    state = user;
    await ref.read(syncNotifierProvider.notifier).syncNow();
  }

  AuthException _mapDioError(DioException e) {
    final status = e.response?.statusCode;
    final message = switch (e.response?.data) {
      { 'error': final String msg } => msg,
      _ => null,
    };
    if (status == 409) {
      return AuthException(message ?? 'An account with this email already exists');
    }
    if (status == 401) {
      return const AuthException('Invalid email or password');
    }
    return AuthException(message ?? 'Something went wrong. Please try again.');
  }

  Future<void> signInWithEmail(String email, String password) async {
    try {
      final result = await ref
          .read(authApiProvider)
          .login(email: email, password: password);
      await ref.read(tokenStorageProvider).write(result.token);
      await _adoptAndSync(AuthUser(id: result.user.id, email: result.user.email));
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    try {
      final result = await ref
          .read(authApiProvider)
          .register(email: email, password: password);
      await ref.read(tokenStorageProvider).write(result.token);
      await _adoptAndSync(AuthUser(id: result.user.id, email: result.user.email));
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  Future<void> signOut() async {
    // Final sync for the outgoing user, then clear local data so no pending
    // changes are lost when switching accounts.
    await ref.read(syncNotifierProvider.notifier).syncNow();
    await ref.read(noteRepositoryProvider).clearLocalData();
    await ref.read(tokenStorageProvider).clear();
    state = null;
  }
}

/// Becomes true once the initial session-restore attempt settles, so the app
/// does not flash the login screen while a valid token is being validated.
final authReadyProvider = NotifierProvider<AuthReady, bool>(AuthReady.new);

class AuthReady extends Notifier<bool> {
  @override
  bool build() => false;
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthUser?>(AuthController.new);

/// The currently signed-in user's id, or null while signed out.
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authControllerProvider)?.id;
});
