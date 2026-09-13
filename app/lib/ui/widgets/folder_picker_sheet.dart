import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_v4/core/app_spacing.dart';
import 'package:note_v4/data/local/database.dart';
import 'package:note_v4/providers/auth_notifier.dart';
import 'package:note_v4/providers/folders_notifier.dart';
import 'package:note_v4/theme.dart';
import 'package:note_v4/ui/widgets/folder_name_dialog.dart';
import 'package:uuid/uuid.dart';

class FolderPickResult {
  const FolderPickResult(this.folderId);
  final String? folderId;
}

Future<FolderPickResult?> showFolderPickerSheet(
  BuildContext context, {
  String? currentFolderId,
}) {
  return showModalBottomSheet<FolderPickResult>(
    context: context,
    builder: (context) => _FolderPickerSheet(currentFolderId: currentFolderId),
  );
}

class _FolderPickerSheet extends ConsumerWidget {
  const _FolderPickerSheet({this.currentFolderId});

  final String? currentFolderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(foldersNotifierProvider);

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
              child: Text('Move to folder', style: context.sectionTitle),
            ),
            const SizedBox(height: AppSpacing.xs),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _FolderTile(
                        icon: Icons.folder_off_outlined,
                        name: 'No folder',
                        selected: currentFolderId == null,
                        onTap: () =>
                            Navigator.pop(context, const FolderPickResult(null)),
                      ),
                      foldersAsync.maybeWhen(
                        data: (folders) => Column(
                          children: [
                            for (final folder in folders)
                              _FolderTile(
                                icon: Icons.folder_outlined,
                                name: folder.name,
                                selected: currentFolderId == folder.id,
                                onTap: () => Navigator.pop(
                                  context,
                                  FolderPickResult(folder.id),
                                ),
                              ),
                          ],
                        ),
                        orElse: () => const SizedBox.shrink(),
                      ),
                      const Divider(height: AppSpacing.xl),
                      _FolderTile(
                        icon: Icons.create_new_folder_outlined,
                        name: 'New folder',
                        showCheck: false,
                        onTap: () async {
                          final name = await showFolderNameDialog(context);
                          if (name == null || name.isEmpty) return;
                          if (!context.mounted) return;
                          final id = const Uuid().v4();
                          final now = DateTime.now();
                          await ref.read(foldersNotifierProvider.notifier).addFolder(
                            Folder(
                              id: id,
                              userId: ref.read(currentUserIdProvider) ?? '',
                              name: name,
                              parentFolderId: null,
                              createdAt: now,
                              updatedAt: now,
                              isDeleted: false,
                              isSynced: false,
                            ),
                          );
                          if (context.mounted) {
                            Navigator.pop(context, FolderPickResult(id));
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.icon,
    required this.name,
    required this.onTap,
    this.selected = false,
    this.showCheck = true,
  });

  final IconData icon;
  final String name;
  final VoidCallback onTap;
  final bool selected;
  final bool showCheck;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
              Icon(
                icon,
                size: 22,
                color: selected ? palette.accent : palette.secondaryText,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  name,
                  style: context.bodyText.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (showCheck && selected)
                Icon(Icons.check, size: 20, color: palette.accent),
            ],
          ),
        ),
      ),
    );
  }
}
