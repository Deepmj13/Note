import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_v4/core/app_spacing.dart';
import 'package:note_v4/data/local/database.dart';
import 'package:note_v4/providers/folders_notifier.dart';
import 'package:note_v4/providers/notes_notifier.dart';
import 'package:note_v4/theme.dart';
import 'package:note_v4/ui/widgets/confirm_sheet.dart';
import 'package:note_v4/ui/widgets/empty_state.dart';
import 'package:note_v4/ui/widgets/entrance.dart';
import 'package:note_v4/ui/widgets/folder_name_dialog.dart';
import 'package:note_v4/ui/widgets/section_header.dart';

class FoldersView extends ConsumerWidget {
  const FoldersView({
    super.key,
    this.onFolderTap,
    this.onCreateFolder,
    this.compact = false,
  });

  final void Function(Folder folder)? onFolderTap;
  final VoidCallback? onCreateFolder;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(foldersNotifierProvider);
    final notesAsync = ref.watch(notesNotifierProvider);

    return foldersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState(
        icon: Icons.error_outline,
        title: "Couldn't load folders",
        message: 'Something went wrong while loading your folders.',
      ),
      data: (folders) {
        if (folders.isEmpty) {
          return EmptyState(
            icon: Icons.create_new_folder_outlined,
            title: 'No folders yet',
            message: 'Create folders to organize your notes.',
            actionLabel: onCreateFolder != null ? 'Create folder' : null,
            onAction: onCreateFolder,
          );
        }

        final counts = <String, int>{};
        final notes = notesAsync.valueOrNull ?? const <Note>[];
        for (final note in notes) {
          final f = note.folderId;
          if (f != null) counts[f] = (counts[f] ?? 0) + 1;
        }

        final columns = _columnsFor(context);

        return LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth =
                (constraints.maxWidth - AppSpacing.md * (columns - 1)) /
                columns;
            return ListView(
              padding: compact
                  ? EdgeInsets.zero
                  : const EdgeInsets.all(AppSpacing.md),
              children: [
                if (compact)
                  SectionHeader(
                    title: 'Folders',
                    trailing: onCreateFolder != null
                        ? TextButton(
                            onPressed: onCreateFolder,
                            child: const Text('New folder'),
                          )
                        : null,
                  ),
                if (compact) const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    for (final folder in folders)
                      Entrance(
                        key: ValueKey('folder-${folder.id}'),
                        index: folders.indexOf(folder),
                        child: SizedBox(
                          width: cardWidth,
                          child: _FolderCard(
                            folder: folder,
                            count: counts[folder.id] ?? 0,
                            onTap: () => onFolderTap?.call(folder),
                            onMore: () =>
                                _showFolderActions(context, ref, folder),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  int _columnsFor(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1000) return 4;
    if (width >= 700) return 3;
    return 2;
  }

  Future<void> _showFolderActions(
    BuildContext context,
    WidgetRef ref,
    Folder folder,
  ) async {
    final action = await showModalBottomSheet<_FolderAction>(
      context: context,
      builder: (context) => _FolderActionSheet(folder: folder),
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case _FolderAction.rename:
        final name = await showFolderNameDialog(
          context,
          title: 'Rename folder',
          initialValue: folder.name,
          confirmLabel: 'Rename',
        );
        if (name != null && name.isNotEmpty && context.mounted) {
          await ref.read(foldersNotifierProvider.notifier).rename(
            folder.id,
            name,
          );
        }
      case _FolderAction.delete:
        final confirmed = await showConfirmSheet(
          context,
          title: 'Delete folder?',
          message: 'Notes inside "${folder.name}" will be moved out and '
              'kept in your notes.',
          confirmLabel: 'Delete',
          icon: Icons.delete_outline,
        );
        if (confirmed && context.mounted) {
          await ref.read(foldersNotifierProvider.notifier).remove(folder.id);
        }
    }
  }
}

enum _FolderAction { rename, delete }

class _FolderActionSheet extends StatelessWidget {
  const _FolderActionSheet({required this.folder});

  final Folder folder;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xs,
              ),
              child: Text(folder.name, style: context.sectionTitle),
            ),
            const SizedBox(height: AppSpacing.xs),
            _ActionRow(
              icon: Icons.edit_outlined,
              label: 'Rename',
              onTap: () => Navigator.pop(context, _FolderAction.rename),
            ),
            _ActionRow(
              icon: Icons.delete_outline,
              label: 'Delete folder',
              color: palette.danger,
              onTap: () => Navigator.pop(context, _FolderAction.delete),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final foreground = color ?? palette.primaryText;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: foreground),
              const SizedBox(width: AppSpacing.md),
              Text(label, style: context.bodyText.copyWith(color: foreground)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({
    required this.folder,
    required this.count,
    required this.onTap,
    required this.onMore,
  });

  final Folder folder;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          height: 132,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: palette.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: palette.accentContainer,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                    ),
                    child: Icon(
                      Icons.folder_outlined,
                      color: palette.accent,
                      size: 22,
                    ),
                  ),
                  InkWell(
                    onTap: onMore,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.more_vert,
                        size: 20,
                        color: palette.disabledText,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.noteTitle.copyWith(fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text(
                '$count note${count == 1 ? '' : 's'}',
                style: context.metadataText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
