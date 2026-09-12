import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_v4/core/app_spacing.dart';
import 'package:note_v4/providers/sync_notifier.dart';
import 'package:note_v4/theme.dart';

/// A compact banner that surfaces non-trivial sync states (offline, retrying,
/// error) to the user. Hidden while idle or actively syncing.
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncNotifierProvider);
    final (icon, message) = switch (status) {
      SyncStatus.offline => (Icons.cloud_off_outlined, 'Offline — notes will sync when you reconnect'),
      SyncStatus.retrying => (Icons.sync_problem, 'Sync failed — retrying…'),
      SyncStatus.error => (Icons.error_outline, 'Sync failed — will retry automatically'),
      _ => (null, null),
    };
    if (icon == null || message == null) return const SizedBox.shrink();

    final palette = context.palette;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: palette.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: status == SyncStatus.offline ? palette.danger : palette.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: context.metadataText.copyWith(color: palette.secondaryText),
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(syncNotifierProvider.notifier).syncNow(),
            style: TextButton.styleFrom(
              foregroundColor: status == SyncStatus.offline
                  ? palette.danger
                  : palette.warning,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
