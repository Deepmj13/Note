import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
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
    } on DioException catch (e) {
      final isConnection =
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout;
      _scheduleRetry(
        waiting: isConnection ? SyncStatus.retrying : SyncStatus.error,
      );
    } catch (_) {
      _scheduleRetry(waiting: SyncStatus.error);
    } finally {
      _inFlight = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  void _scheduleRetry({SyncStatus waiting = SyncStatus.retrying}) {
    _retryTimer?.cancel();
    final multiplier = 1 << (_retryAttempt > 6 ? 6 : _retryAttempt);
    final delay = _baseRetryDelay * multiplier;
    final capped = delay > _maxRetryDelay ? _maxRetryDelay : delay;
    _retryAttempt++;
    state = waiting;
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

    // 0) Honor pending permanent deletes before pulling. Purged rows were
    //    hard-deleted locally while possibly offline; if the server still has
    //    them, a pull would resurrect them. Deleting on the server first and
    //    only then clearing the tombstone list keeps the trash permanent.
    //    Failure aborts the cycle so the retry loop completes the purge.
    final pendingPurges = await local.pendingPurges(userId);
    if (pendingPurges.isNotEmpty) {
      await remote.purgeNotes(userId, pendingPurges);
      await local.clearPendingPurges(userId);
    }

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

    // 4) Advance the incremental sync cursor. Advancing by wall-clock time
    //    alone can permanently skip rows authored by devices whose clock lags
    //    ahead. Advance to the newest timestamp actually seen from the server
    //    instead, clamped so the cursor never jumps into the future (which
    //    would skip rows written at real times in the meantime). Never moves
    //    backwards.
    final now = DateTime.now().toUtc();
    if (remoteNotes.isEmpty && remoteFolders.isEmpty) {
      // Nothing newer exists on the server; fast-forwarding is safe.
      await local.setLastSyncedAt(userId, now);
    } else {
      var latest = since;
      for (final note in remoteNotes) {
        if (note.updatedAt.isAfter(latest)) latest = note.updatedAt;
      }
      for (final folder in remoteFolders) {
        if (folder.updatedAt.isAfter(latest)) latest = folder.updatedAt;
      }
      await local.setLastSyncedAt(
        userId,
        latest.isAfter(now) ? now : latest,
      );
    }
  }
}

final syncNotifierProvider =
    NotifierProvider<SyncNotifier, SyncStatus>(SyncNotifier.new);
