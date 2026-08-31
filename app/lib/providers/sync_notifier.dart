import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_v4/data/repositories/note_repository.dart';
import 'package:note_v4/data/repositories/sync_repository.dart';
import 'package:note_v4/providers/auth_notifier.dart';

enum SyncStatus { idle, syncing, error, offline, retrying }

class SyncNotifier extends Notifier<SyncStatus> {
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Completer<void>? _inFlight;
  Timer? _retryTimer;
  int _retryAttempt = 0;

  static const _baseRetryDelay = Duration(seconds: 5);
  static const _maxRetryDelay = Duration(minutes: 5);

  @override
  SyncStatus build() {
    _initConnectivity();
    ref.onDispose(() {
      _connSub?.cancel();
      _retryTimer?.cancel();
    });
    return SyncStatus.idle;
  }

  void _initConnectivity() {
    try {
      _connSub = Connectivity().onConnectivityChanged.listen(
        (results) {
          if (results.contains(ConnectivityResult.none)) {
            _retryTimer?.cancel();
            _retryAttempt = 0;
            state = SyncStatus.offline;
          } else {
            syncNow();
          }
        },
        onError: (Object _) {},
      );
      _checkConnectivityAndSync();
    } catch (_) {
      // Connectivity is unavailable (e.g. in tests); sync still runs on demand.
    }
  }

  Future<void> _checkConnectivityAndSync() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (!results.contains(ConnectivityResult.none)) {
        await syncNow();
      }
    } catch (_) {}
  }

  /// Runs one full sync cycle: pull remote changes and merge them locally
  /// (last-write-wins), then push local dirty rows, then advance the
  /// incremental cursor. Concurrent calls collapse into a single run.
  ///
  /// On transient failure a retry is scheduled with exponential backoff
  /// (capped) so intermittent connectivity or server errors do not silently
  /// leave dirty rows unsynced.
  Future<void> syncNow() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    if (_inFlight != null) return _inFlight!.future;
    final completer = Completer<void>();
    _inFlight = completer;
    state = SyncStatus.syncing;

    try {
      await _runCycle(userId, allowRetry: true);
      _retryAttempt = 0;
      _retryTimer?.cancel();
      state = SyncStatus.idle;
    } catch (_) {
      _scheduleRetry();
    } finally {
      _inFlight = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final multiplier = 1 << (_retryAttempt > 6 ? 6 : _retryAttempt);
    final delay = _baseRetryDelay * multiplier;
    final capped = delay > _maxRetryDelay ? _maxRetryDelay : delay;
    _retryAttempt++;
    state = SyncStatus.retrying;
    _retryTimer = Timer(capped, () {
      unawaited(syncNow());
    });
  }

  Future<void> _runCycle(String userId, {required bool allowRetry}) async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      _retryAttempt = 0;
      state = SyncStatus.offline;
      return;
    }

    final remote = ref.read(syncRepositoryProvider);
    final local = ref.read(noteRepositoryProvider);

    // 1) Pull newer remote rows and merge them locally.
    final since =
        await local.lastSyncedAt(userId) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final remoteNotes = await remote.pullNotes(userId, since);
    final remoteFolders = await remote.pullFolders(userId, since);
    for (final note in remoteNotes) {
      await local.applyRemoteNote(note);
    }
    for (final folder in remoteFolders) {
      await local.applyRemoteFolder(folder);
    }

    // 2) Push dirty local rows (folders first, notes reference folders).
    //    Only rows the server accepted are marked synced.
    final dirtyFolders = await local.unSyncedFolders(userId);
    final appliedFolders = await remote.pushFolders(userId, dirtyFolders);
    await local.markFoldersSynced(appliedFolders);

    final dirtyNotes = await local.unSyncedNotes(userId);
    final appliedNotes = await remote.pushNotes(userId, dirtyNotes);
    await local.markNotesSynced(appliedNotes);

    // 3) Stale writes rejected by the server's conflict guard. Backdate the
    //    incremental cursor to just before the oldest rejected row and run
    //    one more cycle so the newer server state is pulled back and the
    //    stale local rows are reconciled.
    final rejected = <({String id, DateTime updatedAt})>{
      for (final f in dirtyFolders.where((f) => !appliedFolders.contains(f.id)))
        (id: f.id, updatedAt: f.updatedAt),
      for (final n in dirtyNotes.where((n) => !appliedNotes.contains(n.id)))
        (id: n.id, updatedAt: n.updatedAt),
    };
    if (rejected.isNotEmpty) {
      final oldest = rejected
          .map((r) => r.updatedAt)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      await local.setLastSyncedAt(
        userId,
        oldest.subtract(const Duration(milliseconds: 1)),
      );
      if (allowRetry) {
        await _runCycle(userId, allowRetry: false);
      }
      return;
    }

    // 4) Advance the incremental sync cursor.
    await local.setLastSyncedAt(userId, DateTime.now().toUtc());
  }
}

final syncNotifierProvider =
    NotifierProvider<SyncNotifier, SyncStatus>(SyncNotifier.new);
