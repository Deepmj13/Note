import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_v4/core/app_spacing.dart';
import 'package:note_v4/providers/sync_notifier.dart';
import 'package:note_v4/providers/sync_status_info.dart';
import 'package:note_v4/theme.dart';

/// A compact banner that surfaces sync state to the user:
///  - `offline` / `retrying` / `error` (with a manual retry),
///  - `syncing` (brief spinner),
///  - idle with unsynced changes queued ("N pending"),
///  - idle and in sync ("Synced just now…").
///
/// Hidden while idle with nothing queued and no recorded sync yet.
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncNotifierProvider);
    final queue = ref.watch(syncQueueInfoProvider).valueOrNull;
    final pending = queue?.pending ?? 0;
    final lastSyncedAt = queue?.lastSyncedAt;

    final SyncBannerContent? content;
    switch (status) {
      case SyncStatus.syncing:
        content = const SyncBannerContent(
          icon: null,
          message: 'Syncing…',
          accent: BannerAccent.progress,
          action: null,
        );
      case SyncStatus.offline:
        content = SyncBannerContent(
          message: pending > 0
              ? 'Offline — $pending change${pending == 1 ? '' : 's'} queued'
              : 'Offline — notes will sync when you reconnect',
          icon: Icons.cloud_off_outlined,
          accent: BannerAccent.danger,
          action: 'Try again',
        );
      case SyncStatus.retrying:
        content = const SyncBannerContent(
          message: 'Sync failed — retrying…',
          icon: Icons.sync_problem,
          accent: BannerAccent.warning,
          action: 'Try again',
        );
      case SyncStatus.error:
        content = const SyncBannerContent(
          message: 'Sync failed — will retry automatically',
          icon: Icons.error_outline,
          accent: BannerAccent.warning,
          action: 'Try again',
        );
      case SyncStatus.idle:
        if (pending > 0) {
          content = SyncBannerContent(
            message:
                '$pending change${pending == 1 ? '' : 's'} waiting to sync',
            icon: Icons.cloud_upload_outlined,
            accent: BannerAccent.warning,
            action: 'Sync now',
          );
        } else if (lastSyncedAt != null) {
          content = SyncBannerContent(
            message: 'Synced ${_recentLabel(lastSyncedAt)}',
            icon: Icons.check_circle_outline,
            accent: BannerAccent.success,
            action: null,
          );
        } else {
          content = null;
        }
    }

    if (content == null) return const SizedBox.shrink();

    final palette = context.palette;
    final color = switch (content.accent) {
      BannerAccent.danger => palette.danger,
      BannerAccent.warning => palette.warning,
      BannerAccent.success => palette.success,
      BannerAccent.progress => palette.accent,
    };
    final borderColor =
        content.accent == BannerAccent.progress ||
            content.accent == BannerAccent.success
        ? palette.divider
        : color.withValues(alpha: 0.5);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          if (content.icon != null) ...[
            Icon(content.icon, size: 18, color: color),
            const SizedBox(width: AppSpacing.sm),
          ],
          if (content.accent == BannerAccent.progress) ...[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Text(
              content.message,
              style: context.metadataText.copyWith(color: palette.secondaryText),
            ),
          ),
          if (content.action != null) ...[
            TextButton(
              onPressed: () =>
                  ref.read(syncNotifierProvider.notifier).syncNow(),
              style: TextButton.styleFrom(
                foregroundColor: color,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(content.action!),
            ),
          ],
        ],
      ),
    );
  }

  /// "just now" under a minute, then "Xm ago", "Xh ago", else a date+time.
  static String _recentLabel(DateTime t, {DateTime? now}) {
    final diff = (now ?? DateTime.now()).difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${t.month}/${t.day} ${t.hour}:${t.minute.toString().padLeft(2, '0')}';
  }
}

enum BannerAccent { progress, danger, warning, success }

class SyncBannerContent {
  const SyncBannerContent({
    required this.message,
    required this.accent,
    this.icon,
    this.action,
  });

  final String message;
  final BannerAccent accent;
  final IconData? icon;
  final String? action;
}