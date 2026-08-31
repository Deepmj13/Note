import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import 'auth_api.dart';
import 'sync_api.dart';
import 'token_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(tokenStorageProvider));
});

final authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(apiClientProvider));
});

final syncApiProvider = Provider<SyncApi>((ref) {
  return SyncApi(ref.watch(apiClientProvider));
});
