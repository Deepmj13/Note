import 'package:note_v4/data/local/database.dart';
import 'api_client.dart';

/// Talks to the backend sync endpoints: /sync/notes and /sync/folders.
///
/// Timestamps travel as ISO-8601 strings; user_id is always taken from the
/// JWT on the server, so it is not sent here.
class SyncApi {
  SyncApi(this._client);

  final ApiClient _client;

  Future<List<Note>> pullNotes(String userId, DateTime since) async {
    final res = await _client.dio.get<List<dynamic>>(
      '/sync/notes',
      queryParameters: {
        'since': since.toUtc().toIso8601String(),
      },
    );
    final rows = res.data ?? const [];
    return rows
        .map((r) => _noteFromRow(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<Folder>> pullFolders(String userId, DateTime since) async {
    final res = await _client.dio.get<List<dynamic>>(
      '/sync/folders',
      queryParameters: {
        'since': since.toUtc().toIso8601String(),
      },
    );
    final rows = res.data ?? const [];
    return rows
        .map((r) => _folderFromRow(r as Map<String, dynamic>))
        .toList();
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
      version: BigInt.from(row['version'] as int? ?? 1),
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
