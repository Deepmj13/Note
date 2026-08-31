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
