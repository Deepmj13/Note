import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_v4/data/local/database.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(driftDatabase(
    name: 'notes_db',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  ));
  ref.onDispose(db.close);
  return db;
});

class NoteRepository {
  final AppDatabase _db;

  NoteRepository(this._db);

  // ---- Live watches ----

  /// Watches active notes, optionally scoped to [userId]. A null userId keeps
  /// the legacy unfiltered behavior (used before authentication exists).
  Stream<List<Note>> watchActiveNotes(String? userId) {
    final query = _db.select(_db.notes)
      ..where((n) => n.isDeleted.equals(false))
      ..orderBy([
        (n) => OrderingTerm.desc(n.isPinned),
        (n) => OrderingTerm.desc(n.updatedAt),
      ]);
    if (userId != null) {
      query.where((n) => n.userId.equals(userId));
    }
    return query.watch();
  }

  Stream<List<Note>> watchNotesInFolder(String? folderId, String? userId) {
    final query = _db.select(_db.notes)
      ..where(
        (n) =>
            n.isDeleted.equals(false) &
            (folderId == null
                ? n.folderId.isNull()
                : n.folderId.equals(folderId)),
      )
      ..orderBy([
        (n) => OrderingTerm.desc(n.isPinned),
        (n) => OrderingTerm.desc(n.updatedAt),
      ]);
    if (userId != null) {
      query.where((n) => n.userId.equals(userId));
    }
    return query.watch();
  }

  Stream<List<Folder>> watchFolders(String? userId) {
    final query = _db.select(_db.folders)
      ..where((f) => f.isDeleted.equals(false))
      ..orderBy([(f) => OrderingTerm.asc(f.name)]);
    if (userId != null) {
      query.where((f) => f.userId.equals(userId));
    }
    return query.watch();
  }

  // ---- Notes: local mutations (every change marks the row dirty) ----

  Future<void> insertNote(Note note) async {
    await _db.into(_db.notes).insert(note);
  }

  Future<void> insertNotes(List<Note> notes) async {
    await _db.batch((batch) {
      batch.insertAll(_db.notes, notes);
    });
  }

  Future<void> updateNote(Note note) async {
    await _writeNote(note.id, _noteCompanion(note, synced: false));
  }

  Future<void> setFavorite(String id, bool value) async {
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        isFavorite: Value(value),
        updatedAt: Value(DateTime.now()),
        isSynced: const Value(false),
        version: Value(await _nextVersion(id)),
      ),
    );
  }

  Future<void> setPinned(String id, bool value) async {
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        isPinned: Value(value),
        updatedAt: Value(DateTime.now()),
        isSynced: const Value(false),
        version: Value(await _nextVersion(id)),
      ),
    );
  }

  Future<void> moveToFolder(String id, String? folderId) async {
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        folderId: Value(folderId),
        updatedAt: Value(DateTime.now()),
        isSynced: const Value(false),
        version: Value(await _nextVersion(id)),
      ),
    );
  }

  Future<void> softDelete(String id) async {
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
        isSynced: const Value(false),
        version: Value(await _nextVersion(id)),
      ),
    );
  }

  Future<void> restoreNote(String id) async {
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        isDeleted: const Value(false),
        updatedAt: Value(DateTime.now()),
        isSynced: const Value(false),
        version: Value(await _nextVersion(id)),
      ),
    );
  }

  // ---- Folders: local mutations (every change marks the row dirty) ----

  Future<void> insertFolder(Folder folder) async {
    await _db.into(_db.folders).insert(folder);
  }

  Future<void> renameFolder(String id, String name) async {
    await (_db.update(_db.folders)..where((f) => f.id.equals(id))).write(
      FoldersCompanion(
        name: Value(name),
        updatedAt: Value(DateTime.now()),
        isSynced: const Value(false),
      ),
    );
  }

  Future<void> deleteFolder(String id) async {
    await (_db.update(_db.folders)..where((f) => f.id.equals(id))).write(
      FoldersCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
        isSynced: const Value(false),
      ),
    );
  }

  Future<void> moveNotesOutOfFolder(String folderId) async {
    await (_db.update(_db.notes)..where((n) => n.folderId.equals(folderId)))
        .write(
          NotesCompanion(
            folderId: const Value(null),
            updatedAt: Value(DateTime.now()),
            isSynced: const Value(false),
          ),
        );
  }

  // ---- Sync support: dirty rows ----

  Future<List<Note>> unSyncedNotes(String userId) async {
    final query = _db.select(_db.notes)
      ..where((n) => n.isSynced.equals(false) & n.userId.equals(userId));
    return query.get();
  }

  Future<List<Folder>> unSyncedFolders(String userId) async {
    final query = _db.select(_db.folders)
      ..where((f) => f.isSynced.equals(false) & f.userId.equals(userId));
    return query.get();
  }

  Future<void> markNotesSynced(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (_db.update(_db.notes)..where((n) => n.id.isIn(list))).write(
      const NotesCompanion(isSynced: Value(true)),
    );
  }

  Future<void> markFoldersSynced(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (_db.update(_db.folders)..where((f) => f.id.isIn(list))).write(
      const FoldersCompanion(isSynced: Value(true)),
    );
  }

  // ---- Sync support: account lifecycle ----

  /// Adopts pre-existing local data for [newUserId] on first login.
  ///
  /// Only rows that still belong to legacy placeholders (`''` / `user1`)
  /// are reassigned, so switching accounts never leaks the previous user's
  /// data into the new account. Rows owned by a real user are left in place
  /// (invisible to the new user) until a final sync + clear runs on logout.
  Future<void> adoptLocalData(String newUserId) async {
    await (_db.update(_db.notes)
          ..where(
            (n) =>
                n.userId.isIn(legacyUserIds) &
                n.userId.equals(newUserId).not(),
          ))
        .write(
          NotesCompanion(
            userId: Value(newUserId),
            isSynced: const Value(false),
          ),
        );
    await (_db.update(_db.folders)
          ..where(
            (f) =>
                f.userId.isIn(legacyUserIds) &
                f.userId.equals(newUserId).not(),
          ))
        .write(
          FoldersCompanion(
            userId: Value(newUserId),
            isSynced: const Value(false),
          ),
        );
  }

  /// Removes all local notes, folders and sync metadata (called on logout).
  Future<void> clearLocalData() async {
    await _db.delete(_db.notes).go();
    await _db.delete(_db.folders).go();
    await _db.delete(_db.syncMeta).go();
  }

  // ---- Sync support: incremental cursor ----

  Future<DateTime?> lastSyncedAt(String userId) async {
    final row = await (_db.select(_db.syncMeta)
          ..where((m) => m.metaKey.equals('last_synced_at:$userId')))
        .getSingleOrNull();
    final raw = row?.value;
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setLastSyncedAt(String userId, DateTime time) async {
    await (_db.into(_db.syncMeta)).insertOnConflictUpdate(
      SyncMetaData(
        metaKey: 'last_synced_at:$userId',
        value: time.toUtc().toIso8601String(),
      ),
    );
  }

  // ---- App settings (persisted in the local key-value store) ----

  Future<String?> readSetting(String key) async {
    final row = await (_db.select(_db.syncMeta)
          ..where((m) => m.metaKey.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> writeSetting(String key, String value) async {
    await (_db.into(_db.syncMeta)).insertOnConflictUpdate(
      SyncMetaData(metaKey: key, value: value),
    );
  }

  // ---- Sync support: applying remote rows (last-write-wins) ----

  Future<void> applyRemoteNote(Note remote) async {
    final existing = await (_db.select(_db.notes)
          ..where((n) => n.id.equals(remote.id)))
        .getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.notes).insert(remote.copyWith(isSynced: true));
      return;
    }
    if (remote.updatedAt.isAfter(existing.updatedAt)) {
      await _writeNote(remote.id, _noteCompanion(remote, synced: true));
    } else if (!existing.isSynced &&
        remote.updatedAt.isAtSameMomentAs(existing.updatedAt)) {
      await (_db.update(_db.notes)..where((n) => n.id.equals(remote.id)))
          .write(const NotesCompanion(isSynced: Value(true)));
    }
  }

  Future<void> applyRemoteFolder(Folder remote) async {
    final existing = await (_db.select(_db.folders)
          ..where((f) => f.id.equals(remote.id)))
        .getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.folders).insert(remote.copyWith(isSynced: true));
      return;
    }
    if (remote.updatedAt.isAfter(existing.updatedAt)) {
      await _writeFolder(remote.id, _folderCompanion(remote, synced: true));
    } else if (!existing.isSynced &&
        remote.updatedAt.isAtSameMomentAs(existing.updatedAt)) {
      await (_db.update(_db.folders)..where((f) => f.id.equals(remote.id)))
          .write(const FoldersCompanion(isSynced: Value(true)));
    }
  }

  // ---- Helpers ----

  /// Legacy placeholder user ids used before authentication existed.
  static const legacyUserIds = ['', 'user1'];

  Future<void> _writeNote(String id, NotesCompanion companion) async {
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      companion,
    );
  }

  /// Next monotonically increasing version for [id] (used by flag/status
  /// mutations so every local change bumps the revision, not just content
  /// edits in the editor). Revisions drive server-side conflict resolution.
  Future<BigInt> _nextVersion(String id) async {
    final row = await (_db.select(_db.notes)..where((n) => n.id.equals(id)))
        .getSingleOrNull();
    return (row?.version ?? BigInt.zero) + BigInt.one;
  }

  Future<void> _writeFolder(String id, FoldersCompanion companion) async {
    await (_db.update(_db.folders)..where((f) => f.id.equals(id))).write(
      companion,
    );
  }

  NotesCompanion _noteCompanion(Note n, {required bool synced}) {
    return NotesCompanion(
      title: Value(n.title),
      content: Value(n.content),
      updatedAt: Value(n.updatedAt),
      isDeleted: Value(n.isDeleted),
      isSynced: Value(synced),
      version: Value(n.version),
      isFavorite: Value(n.isFavorite),
      isPinned: Value(n.isPinned),
      noteType: Value(n.noteType),
      folderId: Value(n.folderId),
    );
  }

  FoldersCompanion _folderCompanion(Folder f, {required bool synced}) {
    return FoldersCompanion(
      name: Value(f.name),
      parentFolderId: Value(f.parentFolderId),
      updatedAt: Value(f.updatedAt),
      isDeleted: Value(f.isDeleted),
      isSynced: Value(synced),
    );
  }
}

final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  return NoteRepository(ref.watch(databaseProvider));
});
