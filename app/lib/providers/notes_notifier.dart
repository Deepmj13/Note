import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:note_v4/data/local/database.dart';
import 'package:note_v4/data/repositories/note_repository.dart';
import 'package:note_v4/providers/auth_notifier.dart';
import 'package:note_v4/providers/sync_notifier.dart';

part 'notes_notifier.g.dart';

@riverpod
class NotesNotifier extends _$NotesNotifier {
  Timer? _syncTimer;

  @override
  Stream<List<Note>> build() {
    final userId = ref.watch(currentUserIdProvider);
    ref.onDispose(() => _syncTimer?.cancel());
    return ref.watch(noteRepositoryProvider).watchActiveNotes(userId);
  }

  /// Coalesces rapid mutations (e.g. editor autosaves) into a single sync.
  void _sync() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 1), () {
      unawaited(ref.read(syncNotifierProvider.notifier).syncNow());
    });
  }

  Future<void> addNote(Note note) async {
    await ref.read(noteRepositoryProvider).insertNote(note);
    _sync();
  }

  Future<void> importNotes(List<Note> notes) async {
    await ref.read(noteRepositoryProvider).insertNotes(notes);
    _sync();
  }

  Future<void> updateNote(Note note) async {
    await ref.read(noteRepositoryProvider).updateNote(note);
    _sync();
  }

  Future<void> deleteNote(String id) async {
    await ref.read(noteRepositoryProvider).softDelete(id);
    _sync();
  }

  Future<void> restoreNote(String id) async {
    await ref.read(noteRepositoryProvider).restoreNote(id);
    _sync();
  }

  /// Permanently deletes [id] locally and records a pending purge so the
  /// server removes it on the next sync (no trash resurrection).
  Future<void> purgeNote(String id) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    final repo = ref.read(noteRepositoryProvider);
    await repo.addPendingPurges(userId, [id]);
    await repo.purgeNotes([id]);
    _sync();
  }

  /// Permanently deletes every trashed note ("empty trash").
  Future<void> purgeAllTrashed() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    final repo = ref.read(noteRepositoryProvider);
    final trashed = await repo.trashedNotes(userId);
    if (trashed.isEmpty) return;
    final ids = trashed.map((n) => n.id).toList();
    await repo.addPendingPurges(userId, ids);
    await repo.purgeNotes(ids);
    _sync();
  }

  Future<void> setFavorite(String id, bool value) async {
    await ref.read(noteRepositoryProvider).setFavorite(id, value);
    _sync();
  }

  Future<void> setPinned(String id, bool value) async {
    await ref.read(noteRepositoryProvider).setPinned(id, value);
    _sync();
  }

  Future<void> moveToFolder(String id, String? folderId) async {
    await ref.read(noteRepositoryProvider).moveToFolder(id, folderId);
    _sync();
  }
}

/// Trashed notes for the current user (newest deletion first). Written by
/// hand (not codegen) because the pinned riverpod generator can't run under
/// the current Dart SDK.
final trashedNotesProvider = StreamProvider.autoDispose<List<Note>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  return ref.watch(noteRepositoryProvider).watchTrashedNotes(userId);
});
