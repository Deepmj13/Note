import 'package:note_v4/data/local/database.dart';
import 'api_client.dart';

/// Talks to the backend sync endpoints: /sync/notes and /sync/folders.
///
/// Timestamps travel as ISO-8601 strings; user_id is always taken from the
/// JWT on the server, so it is not sent here. Pulls are paginated server-side:
/// each page is fetched by passing back the returned `next_cursor` until
/// `has_more` is false, so large result sets stream in without unbounded
/// memory on server or client.
class SyncApi {
  SyncApi(this._client);

  final ApiClient _client;

  static const _pageSize = 500;

  Future<List<Note>> pullNotes(String userId, DateTime since) async {
    final rows = await _pullAllRows('/sync/notes', since);
    return rows.map(_noteFromRow).toList();
  }

  Future<List<Folder>> pullFolders(String userId, DateTime since) async {
    final rows = await _pullAllRows('/sync/folders', since);
    return rows.map(_folderFromRow).toList();
  }

  Future<List<Map<String, dynamic>>> _pullAllRows(
    String path,
    DateTime since,
  ) async {
    final all = <Map<String, dynamic>>[];
    String? cursor;
    var hasMore = true;
    while (hasMore) {
      final res = await _client.dio.get<Map<String, dynamic>>(
        path,
        queryParameters: {
          'since': since.toUtc().toIso8601String(),
          'limit': _pageSize,
          'cursor': ?cursor,
        },
      );
      final data = res.data ?? const {};
      final rows = (data['rows'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      hasMore = data['has_more'] as bool? ?? false;
      final next = data['next_cursor'] as String?;
      all.addAll(rows);
      // Progress guards: a page must produce rows and actually advance the
      // cursor, otherwise a broken server response would loop forever.
      if (rows.isEmpty || next == null || next == cursor) {
        hasMore = false;
      } else {
        cursor = next;
      }
    }
    return all;
  }

  /// Pushes dirty notes and returns the ids the server accepted. Ids absent
  /// from the result were rejected by the conflict guard (a stale revision)
  /// and must be reconciled by a follow-up pull.
  Future<Set<String>> pushNotes(String userId, List<Note> notes) async {
    if (notes.isEmpty) return const {};
    final payload = notes.map(_noteToRow).toList();
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/sync/notes',
      data: payload,
    );
    return _parseApplied(res.data);
  }

  /// Pushes dirty folders and returns the ids the server accepted.
  Future<Set<String>> pushFolders(String userId, List<Folder> folders) async {
    if (folders.isEmpty) return const {};
    final payload = folders.map(_folderToRow).toList();
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/sync/folders',
      data: payload,
    );
    return _parseApplied(res.data);
  }

  /// Permanently deletes [ids] on the server. Used by trash "delete forever";
  /// only called after the same rows were hard-deleted locally.
  Future<void> purgeNotes(String userId, List<String> ids) async {
    if (ids.isEmpty) return;
    await _client.dio.post<Map<String, dynamic>>(
      '/sync/purge',
      data: {'ids': ids},
    );
  }

  static Set<String> _parseApplied(Map<String, dynamic>? data) {
    final applied = data?['applied'];
    if (applied is List) {
      return applied.map((e) => e.toString()).toSet();
    }
    return const {};
  }

  static Map<String, dynamic> _noteToRow(Note n) => {
        'id': n.id,
        'title': n.title,
        'content': n.content,
        'created_at': n.createdAt.toUtc().toIso8601String(),
        'updated_at': n.updatedAt.toUtc().toIso8601String(),
        'is_deleted': n.isDeleted,
        'version': n.version.toInt(),
        'is_favorite': n.isFavorite,
        'is_pinned': n.isPinned,
        'note_type': n.noteType.name,
        'folder_id': n.folderId,
      };

  static Map<String, dynamic> _folderToRow(Folder f) => {
        'id': f.id,
        'name': f.name,
        'parent_folder_id': f.parentFolderId,
        'created_at': f.createdAt.toUtc().toIso8601String(),
        'updated_at': f.updatedAt.toUtc().toIso8601String(),
        'is_deleted': f.isDeleted,
      };

  static Note _noteFromRow(Map<String, dynamic> row) {
    final typeName = row['note_type'] as String? ?? NoteType.text.name;
    return Note(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      title: row['title'] as String? ?? '',
      content: row['content'] as String? ?? '',
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
      isDeleted: row['is_deleted'] as bool? ?? false,
      isSynced: true,
      version: BigInt.from(num.tryParse('${row['version']}')?.toInt() ?? 1),
      isFavorite: row['is_favorite'] as bool? ?? false,
      isPinned: row['is_pinned'] as bool? ?? false,
      noteType: NoteType.values.asNameMap()[typeName] ?? NoteType.text,
      folderId: row['folder_id'] as String?,
    );
  }

  static Folder _folderFromRow(Map<String, dynamic> row) {
    return Folder(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      name: row['name'] as String? ?? '',
      parentFolderId: row['parent_folder_id'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
      isDeleted: row['is_deleted'] as bool? ?? false,
      isSynced: true,
    );
  }
}
