import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_v4/data/local/database.dart';
import 'package:note_v4/data/network/network_providers.dart';
import 'package:note_v4/data/network/sync_api.dart';

/// Remote sync operations against the Note backend API.
///
/// Timestamps are client-authored and written as-is so that last-write-wins
/// comparisons stay consistent between devices (no server overwrite of
/// `updated_at`).
class SyncRepository {
  SyncRepository(this._api);

  final SyncApi _api;

  Future<Set<String>> pushNotes(String userId, List<Note> notes) {
    return _api.pushNotes(userId, notes);
  }

  Future<Set<String>> pushFolders(String userId, List<Folder> folders) {
    return _api.pushFolders(userId, folders);
  }

  Future<List<Note>> pullNotes(String userId, DateTime since) {
    return _api.pullNotes(userId, since);
  }

  Future<List<Folder>> pullFolders(String userId, DateTime since) {
    return _api.pullFolders(userId, since);
  }
}

final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  return SyncRepository(ref.watch(syncApiProvider));
});
