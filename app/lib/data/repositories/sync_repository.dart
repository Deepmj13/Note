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

  /// Maximum rows the backend accepts in a single push batch (see server
  /// zod cap). Larger dirty sets are chunked automatically.
  static const int _batchSize = 500;

  Future<Set<String>> pushNotes(String userId, List<Note> notes) async {
    return _pushInBatches(
      (batch) => _api.pushNotes(userId, batch),
      notes,
    );
  }

  Future<Set<String>> pushFolders(String userId, List<Folder> folders) async {
    return _pushInBatches(
      (batch) => _api.pushFolders(userId, batch),
      folders,
    );
  }

  Future<List<Note>> pullNotes(String userId, DateTime since) {
    return _api.pullNotes(userId, since);
  }

  Future<List<Folder>> pullFolders(String userId, DateTime since) {
    return _api.pullFolders(userId, since);
  }

  /// Permanently deletes [ids] on the server (trash "delete forever").
  /// Batched to respect the server's per-request cap.
  Future<void> purgeNotes(String userId, List<String> ids) async {
    await _pushInBatches(
      (batch) async {
        await _api.purgeNotes(userId, batch);
        return batch.map((id) => id).toSet();
      },
      ids,
    );
  }

  Future<Set<String>> _pushInBatches<T>(
    Future<Set<String>> Function(List<T>) pushOne,
    List<T> rows,
  ) async {
    if (rows.isEmpty) return {};
    final applied = <String>{};
    for (var start = 0; start < rows.length; start += _batchSize) {
      final end = (start + _batchSize > rows.length)
          ? rows.length
          : start + _batchSize;
      applied.addAll(await pushOne(rows.sublist(start, end)));
    }
    return applied;
  }
}

final syncRepositoryProvider = Provider<SyncRepository>((ref) {
  return SyncRepository(ref.watch(syncApiProvider));
});
