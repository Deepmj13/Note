import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:note_v4/data/local/database.dart';
import 'package:note_v4/data/repositories/note_repository.dart';
import 'package:note_v4/providers/auth_notifier.dart';
import 'package:note_v4/providers/sync_notifier.dart';

part 'folders_notifier.g.dart';

@riverpod
class FoldersNotifier extends _$FoldersNotifier {
  Timer? _syncTimer;

  @override
  Stream<List<Folder>> build() {
    final userId = ref.watch(currentUserIdProvider);
    ref.onDispose(() => _syncTimer?.cancel());
    return ref.watch(noteRepositoryProvider).watchFolders(userId);
  }

  /// Coalesces rapid mutations into a single sync.
  void _sync() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 1), () {
      unawaited(ref.read(syncNotifierProvider.notifier).syncNow());
    });
  }

  Future<void> addFolder(Folder folder) async {
    await ref.read(noteRepositoryProvider).insertFolder(folder);
    _sync();
  }

  Future<void> rename(String id, String name) async {
    await ref.read(noteRepositoryProvider).renameFolder(id, name);
    _sync();
  }

  Future<void> remove(String id) async {
    final repo = ref.read(noteRepositoryProvider);
    await repo.moveNotesOutOfFolder(id);
    await repo.deleteFolder(id);
    _sync();
  }
}
